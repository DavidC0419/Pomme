//
//  MacWorkbenchTableRowView.swift
//  Pomme
//
//  Mac 策展人工作台表格列表单行视图 (Mac Curator Workbench Table Row)
//

import SwiftUI

struct MacWorkbenchTableRowView: View {
    let item: CollectionItem
    let isBatteryMode: Bool
    let isMultiSelectMode: Bool
    @Binding var selectedItemIDs: Set<String>
    let onUpdate: (CollectionItem) -> Void
    
    var body: some View {
        let snapshot = isBatteryMode ? BatteryMaintenanceManager.evaluateMaintenance(for: item) : nil
        let battStatus = snapshot?.status ?? (item.isDailyDriver ? .inUse : (BatteryMaintenanceManager.isAirTagInsulated(item) ? .healthy : .untracked))
        let isInsulated = BatteryMaintenanceManager.isAirTagInsulated(item)

        return HStack(spacing: 14) {
            if isMultiSelectMode {
                Button {
                    if selectedItemIDs.contains(item.id) {
                        selectedItemIDs.remove(item.id)
                    } else {
                        selectedItemIDs.insert(item.id)
                    }
                } label: {
                    Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedItemIDs.contains(item.id) ? Color.accentColor : .secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            
            // 软底座小缩略图
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .frame(width: 36, height: 36)
                
                Image(item.artworkAssetName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(isAirPodsMax2Device(item) ? 1.5 : 1.0)
                    .clipped()
                    .frame(width: 30, height: 30)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    if item.isDailyDriver {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    }
                }
                
                Text(item.resolvedProductName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 170, alignment: .leading)
            
            Text(item.model ?? "-")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            if isBatteryMode {
                // 电池巡检模式专有列
                HStack(spacing: 4) {
                    Image(systemName: isInsulated ? "checkmark.shield.fill" : battStatus.iconName)
                        .font(.system(size: 10))
                    Text(isInsulated ? (isChineseLanguage ? "绝缘中" : "Insulated") : (isChineseLanguage ? battStatus.shortLabelChinese : battStatus.shortLabel))
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(isInsulated ? Color.green : battStatus.color)
                .frame(width: 90, alignment: .leading)
                
                Text(isInsulated ? (isChineseLanguage ? "未激活" : "Inactive") : (snapshot?.elapsedDays.map { isChineseLanguage ? "\($0)天前" : "\($0)d ago" } ?? (isChineseLanguage ? "无记录" : "None")))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 85, alignment: .leading)
                
                Group {
                    if isInsulated {
                        Text(isChineseLanguage ? "零放电" : "0 drain")
                            .foregroundStyle(.secondary)
                    } else if battStatus == .inUse {
                        Text(isChineseLanguage ? "主力在用" : "In Use")
                            .foregroundStyle(.blue)
                    } else if battStatus == .overdue, let rem = snapshot?.remainingDays {
                        Text(isChineseLanguage ? "超期\(-rem)天" : "+\(-rem)d")
                            .foregroundStyle(.red)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    } else if let rem = snapshot?.remainingDays {
                        Text(isChineseLanguage ? "剩\(rem)天" : "\(rem)d left")
                            .foregroundStyle(battStatus == .dueSoon ? .orange : .primary)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11.5))
                .frame(width: 85, alignment: .leading)
                
                Spacer()
                
                if !isInsulated && BatteryMaintenanceManager.deviceHasRechargeableBattery(item) {
                    Button {
                        BatteryMaintenanceManager.logCharge(for: item, date: Date(), remainingLevel: .from80to100) { updated in
                            onUpdate(updated)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8.5))
                            Text(isChineseLanguage ? "登记补电" : "Log Charge")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(battStatus == .overdue ? Color.red : Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04), in: Capsule())
                        .overlay(Capsule().stroke((battStatus == .overdue ? Color.red : Color.accentColor).opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 105, alignment: .trailing)
                } else {
                    Text("-")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 105, alignment: .trailing)
                }
            } else {
                Text(item.serialNumber ?? "-")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(item.serialNumber?.isEmpty == false ? .primary : .secondary)
                    .frame(width: 130, alignment: .leading)
                
                Text(item.processor ?? "-")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                
                Spacer()
                
                if let price = item.price, !price.isEmpty {
                    let p = CuratorCatalogPDFExporter.parsePrice(price)
                    Text(p > 0 ? String(format: "¥%.2f", p) : price)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(width: 100, alignment: .trailing)
                } else {
                    Text("-")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
