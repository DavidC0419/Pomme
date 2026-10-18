//
//  MacDataHealthView.swift
//  Pomme
//
//  Mac 策展人数据健康体检面板 (Data Health Dashboard)
//  实时统计藏品完整度、缺图、缺价、缺序列号与电池待检项目，支持一键点击筛选补全。
//

import SwiftUI

enum DataHealthFilter: String, CaseIterable, Identifiable {
    case all = "All Issues"
    case missingPrice = "Missing Price"
    case missingSN = "Missing Serial Number"
    case missingSpecs = "Missing Specs"
    case batteryOverdue = "Battery Overdue"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .all: return isChineseLanguage ? "全部待补全" : "All Issues"
        case .missingPrice: return isChineseLanguage ? "缺少购入价格" : "Missing Price"
        case .missingSN: return isChineseLanguage ? "缺少序列号" : "Missing Serial Number"
        case .missingSpecs: return isChineseLanguage ? "缺少规格参数" : "Missing Specs"
        case .batteryOverdue: return isChineseLanguage ? "电池超期待检" : "Battery Overdue"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "checklist.checked"
        case .missingPrice: return "yensign.circle.fill"
        case .missingSN: return "barcode.viewfinder"
        case .missingSpecs: return "cpu.fill"
        case .batteryOverdue: return "battery.25percent"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .purple
        case .missingPrice: return .orange
        case .missingSN: return .blue
        case .missingSpecs: return .teal
        case .batteryOverdue: return .red
        }
    }
}

struct MacDataHealthSnapshot {
    let totalItems: Int
    let missingPriceItems: [CollectionItem]
    let missingSNItems: [CollectionItem]
    let missingSpecsItems: [CollectionItem]
    let batteryOverdueItems: [CollectionItem]
    let overallScore: Int
    
    static func analyze(items: [CollectionItem]) -> MacDataHealthSnapshot {
        guard !items.isEmpty else {
            return MacDataHealthSnapshot(totalItems: 0, missingPriceItems: [], missingSNItems: [], missingSpecsItems: [], batteryOverdueItems: [], overallScore: 100)
        }
        
        let now = Date()
        var missingPrice: [CollectionItem] = []
        var missingSN: [CollectionItem] = []
        var missingSpecs: [CollectionItem] = []
        var overdue: [CollectionItem] = []
        
        var totalPoints = 0
        let maxPoints = items.count * 4
        
        for item in items {
            var itemScore = 0
            
            // 1. 价格检查
            if let p = item.price, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                itemScore += 1
            } else {
                missingPrice.append(item)
            }
            
            // 2. 序列号检查
            if let sn = item.serialNumber, !sn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                itemScore += 1
            } else {
                missingSN.append(item)
            }
            
            // 3. 硬件规格检查 (处理器/型号)
            if (item.processor != nil && !item.processor!.isEmpty) || (item.model != nil && !item.model!.isEmpty) {
                itemScore += 1
            } else {
                missingSpecs.append(item)
            }
            
            // 4. 电池状态健康度
            if BatteryMaintenanceManager.deviceHasRechargeableBattery(item) && !item.batteryTrackingIgnored {
                if let eval = BatteryMaintenanceManager.evaluateMaintenance(for: item, relativeTo: now) {
                    if eval.status == .overdue {
                        overdue.append(item)
                    } else {
                        itemScore += 1
                    }
                } else {
                    itemScore += 1
                }
            } else {
                itemScore += 1
            }
            
            totalPoints += itemScore
        }
        
        let score = max(0, min(100, Int((Double(totalPoints) / Double(maxPoints)) * 100.0)))
        
        return MacDataHealthSnapshot(
            totalItems: items.count,
            missingPriceItems: missingPrice,
            missingSNItems: missingSN,
            missingSpecsItems: missingSpecs,
            batteryOverdueItems: overdue,
            overallScore: score
        )
    }
}

struct MacDataHealthView: View {
    let items: [CollectionItem]
    @Binding var activeFilter: DataHealthFilter?
    let onSelectFilteredItems: ([CollectionItem]) -> Void
    
    private var snapshot: MacDataHealthSnapshot {
        MacDataHealthSnapshot.analyze(items: items)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 顶部健康度仪表盘 (Apple Fitness / Activity 风格)
                HStack(spacing: 16) {
                    // 圆环进度评分
                    ZStack {
                        Circle()
                            .stroke(scoreColor(snapshot.overallScore).opacity(0.18), lineWidth: 8)
                            .frame(width: 64, height: 64)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.overallScore) / 100.0)
                            .stroke(
                                scoreColor(snapshot.overallScore),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 64, height: 64)
                        
                        Text("\(snapshot.overallScore)%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor(snapshot.overallScore))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChineseLanguage ? "藏品数据健康度" : "Data Health Score")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text(scoreDescription(snapshot.overallScore))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                
                Text(isChineseLanguage ? "待补全维度 · 点击直达过滤" : "Issues to Resolve · Click to Filter")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                // 待补齐指标卡片列表
                VStack(spacing: 10) {
                    healthMetricRow(
                        filter: .missingPrice,
                        title: isChineseLanguage ? "缺少购入价格" : "Missing Purchase Price",
                        count: snapshot.missingPriceItems.count,
                        items: snapshot.missingPriceItems
                    )
                    
                    healthMetricRow(
                        filter: .missingSN,
                        title: isChineseLanguage ? "缺少机身序列号" : "Missing Serial Number",
                        count: snapshot.missingSNItems.count,
                        items: snapshot.missingSNItems
                    )
                    
                    healthMetricRow(
                        filter: .missingSpecs,
                        title: isChineseLanguage ? "缺少硬件规格 / 芯片" : "Missing Specs / Processor",
                        count: snapshot.missingSpecsItems.count,
                        items: snapshot.missingSpecsItems
                    )
                    
                    healthMetricRow(
                        filter: .batteryOverdue,
                        title: isChineseLanguage ? "电池超期待巡检" : "Battery Overdue Check",
                        count: snapshot.batteryOverdueItems.count,
                        items: snapshot.batteryOverdueItems
                    )
                }
                
                Spacer()
            }
            .padding(16)
        }
    }
    
    private func healthMetricRow(filter: DataHealthFilter, title: String, count: Int, items: [CollectionItem]) -> some View {
        Button {
            if activeFilter == filter {
                activeFilter = nil
            } else {
                activeFilter = filter
                onSelectFilteredItems(items)
            }
        } label: {
            HStack(spacing: 12) {
                // 鲜活微图标底座
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(filter.color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: filter.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(filter.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(count == 0 ? (isChineseLanguage ? "全部完备" : "All complete") : (isChineseLanguage ? "\(count) 件待补全" : "\(count) items remaining"))
                        .font(.system(size: 11))
                        .foregroundStyle(count == 0 ? .green : .secondary)
                }
                
                Spacer()
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(activeFilter == filter ? filter.color : Color.primary.opacity(0.06), in: Capsule())
                        .foregroundStyle(activeFilter == filter ? .white : .primary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(activeFilter == filter ? filter.color.opacity(0.08) : Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(activeFilter == filter ? filter.color : Color.primary.opacity(0.06), lineWidth: activeFilter == filter ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 { return .green }
        if score >= 75 { return .blue }
        if score >= 60 { return .orange }
        return .red
    }
    
    private func scoreDescription(_ score: Int) -> String {
        if isChineseLanguage {
            if score >= 90 { return "馆藏建档极其完备，随时可导出标准资产保全画册。" }
            if score >= 75 { return "建档良好，再补齐部分价格与序列号即可达标。" }
            if score >= 60 { return "部分藏品信息缺失较多，建议按列表逐步填充。" }
            return "基础建档亟待完善，点击下方标签直达对应藏品快速录入。"
        } else {
            if score >= 90 { return "Curator dossier is exceptionally thorough." }
            if score >= 75 { return "Good coverage. Fill remaining prices and serials to reach perfection." }
            if score >= 60 { return "Notable details missing. Recommended to update via quick filter." }
            return "Dossier requires attention. Click items below to fill in details."
        }
    }
}
