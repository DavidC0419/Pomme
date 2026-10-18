//
//  MacGridItemCardView.swift
//  Pomme
//
//  苹果级现代阴影、圆角与悬浮动效卡片 (Mac Curator Workbench Grid Card)
//

import SwiftUI

struct MacGridItemCardView: View {
    let item: CollectionItem
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let isFavorite: Bool
    var isBatteryMode: Bool = false
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleDailyDriver: () -> Void
    var onLogCharge: (() -> Void)? = nil
    let onQuickLook: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let snapshot = isBatteryMode ? BatteryMaintenanceManager.evaluateMaintenance(for: item) : nil
        let battStatus = snapshot?.status ?? (item.isDailyDriver ? .inUse : (BatteryMaintenanceManager.isAirTagInsulated(item) ? .healthy : .untracked))
        let isInsulated = BatteryMaintenanceManager.isAirTagInsulated(item)
        
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                // 硬件展示展台 (Pedestal)
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(0.015),
                                    Color.primary.opacity(0.045)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 126)
                    
                    // 硬件正视图片 (带微动效与柔和景深阴影)
                    Image(item.artworkAssetName)
                        .resizable()
                        .scaledToFit()
                        .padding(isAirPodsMax2Device(item) ? 0 : 12)
                        .frame(maxWidth: .infinity, maxHeight: 126)
                        .scaleEffect((isHovered ? 1.035 : 1.0) * (isAirPodsMax2Device(item) ? 1.5 : 1.0))
                        .clipped()
                        .shadow(
                            color: Color.black.opacity(isHovered ? 0.12 : 0.04),
                            radius: isHovered ? 8 : 4,
                            x: 0,
                            y: isHovered ? 4 : 2
                        )
                        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovered)
                    
                    // 顶部徽章行
                    HStack {
                        if isBatteryMode {
                            HStack(spacing: 3) {
                                Image(systemName: isInsulated ? "checkmark.shield.fill" : battStatus.iconName)
                                    .font(.system(size: 8.5, weight: .bold))
                                Text(isInsulated ? (isChineseLanguage ? "绝缘中" : "Insulated") : (isChineseLanguage ? battStatus.shortLabelChinese : battStatus.shortLabel))
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundStyle(isInsulated ? Color.green : battStatus.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke((isInsulated ? Color.green : battStatus.color).opacity(0.3), lineWidth: 0.5))
                            .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                        } else if item.isDailyDriver {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8.5, weight: .bold))
                                Text(isChineseLanguage ? "主力" : "In Use")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 0.5))
                            .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                        }
                        
                        Spacer()
                        
                        if isMultiSelectMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                                .background(Circle().fill(Color.white.opacity(0.8)))
                        } else if isBatteryMode {
                            if !isInsulated && BatteryMaintenanceManager.deviceHasRechargeableBattery(item) {
                                Button {
                                    onLogCharge?()
                                } label: {
                                    HStack(spacing: 2) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 8))
                                        Text(isChineseLanguage ? "补电" : "Log")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(battStatus == .overdue ? Color.red : Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().stroke((battStatus == .overdue ? Color.red : Color.accentColor).opacity(0.3), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                                .help(isChineseLanguage ? "登记今日已补电 (≥70%)" : "Log Charge Today (≥70%)")
                            }
                        } else if isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                                .padding(5)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                        }
                    }
                    .padding(8)
                }
                
                // 藏品信息排版
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    
                    if isBatteryMode {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isInsulated ? Color.green : battStatus.color)
                                .frame(width: 5.5, height: 5.5)
                            if isInsulated {
                                Text(isChineseLanguage ? "绝缘片未拔出 · 零自放电" : "Insulated · Zero Drain")
                            } else if let el = snapshot?.elapsedDays {
                                Text(isChineseLanguage ? "\(el)天前维护" : "\(el)d since check")
                                Text("·")
                                Text(isChineseLanguage ? "周期\(snapshot?.cycleDays ?? 45)天" : "Cycle \(snapshot?.cycleDays ?? 45)d")
                            } else {
                                Text(isChineseLanguage ? "尚未登记初次维护" : "No maintenance record")
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        
                        HStack(alignment: .center, spacing: 6) {
                            if isInsulated {
                                Text(isChineseLanguage ? "拔出绝缘片即可激活" : "Pull tab to activate")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            } else if battStatus == .inUse {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8.5))
                                    Text(isChineseLanguage ? "主力在用日常免充" : "In use · Daily charged")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .foregroundStyle(.blue)
                            } else if battStatus == .overdue, let rem = snapshot?.remainingDays {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8.5))
                                    Text(isChineseLanguage ? "超期\(-rem)天 (面临饿死)" : "Overdue \(-rem)d")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(.red)
                            } else if let rem = snapshot?.remainingDays {
                                HStack(spacing: 3) {
                                    Image(systemName: battStatus == .dueSoon ? "clock.badge.exclamationmark" : "battery.100.bolt")
                                        .font(.system(size: 8.5))
                                    Text(isChineseLanguage ? "剩 \(rem) 天需补电" : "\(rem) days left")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(battStatus == .dueSoon ? .orange : .primary)
                            } else {
                                Text(isChineseLanguage ? "建议补电启动跟踪" : "Log check to track")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 1)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: categorySymbol(item.category))
                                .font(.system(size: 9.5))
                            Text(itemRootCategory(item))
                            if let year = item.releaseYear, !year.isEmpty {
                                Text("· \(year)")
                            } else if let model = item.model, !model.isEmpty {
                                Text("· \(model)")
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        
                        // 估值与渠道微标签
                        HStack(alignment: .center, spacing: 6) {
                            if let price = item.price, !price.isEmpty {
                                let p = CuratorCatalogPDFExporter.parsePrice(price)
                                HStack(spacing: 2) {
                                    Text("¥")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Text(p > 0 ? String(format: "%.0f", p) : price)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color.primary.opacity(0.04), in: Capsule())
                            }
                            
                            if let source = item.purchaseSource, !source.isEmpty {
                                Text(source)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.08) : macCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        isSelected ? Color.blue : Color.primary.opacity(isHovered ? 0.15 : 0.06),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : (isHovered ? 0.10 : 0.035)),
                radius: isHovered ? 12 : 5,
                x: 0,
                y: isHovered ? 6 : 2
            )
            .compositingGroup()
            .offset(y: isHovered ? -2.5 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.78), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if !isInsulated && BatteryMaintenanceManager.deviceHasRechargeableBattery(item) {
                Button {
                    onLogCharge?()
                } label: {
                    Label(isChineseLanguage ? "登记今日补电 (≥70%)" : "Log Charge Today (≥70%)", systemImage: "battery.100.bolt")
                }
            }
            
            Button {
                onToggleDailyDriver()
            } label: {
                Label(item.isDailyDriver ? (isChineseLanguage ? "取消在用主力" : "Unset Daily Driver") : (isChineseLanguage ? "设为在用主力" : "Set as Daily Driver"), systemImage: "bolt.badge.clock")
            }
            
            Button {
                onToggleFavorite()
            } label: {
                Label(isFavorite ? (isChineseLanguage ? "取消收藏" : "Remove Favorite") : (isChineseLanguage ? "加入收藏" : "Add Favorite"), systemImage: "star")
            }
            
            let tiers = categoryHierarchyTiers(name: item.name, category: item.category)
            CategoryCoverMenuContent(artworkAssetName: item.artworkAssetName, tiers: tiers)
            
            Divider()
            
            Button {
                onQuickLook()
            } label: {
                Label(isChineseLanguage ? "空格快速预览" : "Quick Look", systemImage: "eye")
            }
        }
    }
}
