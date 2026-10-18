//
//  MacWorkbenchBatterySectionView.swift
//  Pomme
//
//  Mac 策展人工作台电池维护双层快速检索控制栏 (Hardware Category & Battery Status Filter)
//

import SwiftUI

struct MacWorkbenchBatterySectionView: View {
    let collectionItems: [CollectionItem]
    @Binding var selectedBatteryCategory: String?
    @Binding var batteryStatusFilter: MacBatteryStatusFilter
    let onBatchCharge: () -> Void
    
    @Environment(\.locale) private var locale
    private var isChineseLanguage: Bool {
        locale.identifier.hasPrefix("zh") || Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }
    
    private var batteryTotalCount: Int {
        collectionItems.filter {
            (BatteryMaintenanceManager.deviceHasRechargeableBattery($0) || BatteryMaintenanceManager.isAirTag($0)) && !$0.batteryTrackingIgnored
        }.count
    }
    
    private var batteryCategoryCounts: [String: Int] {
        let batteryItems = collectionItems.filter {
            (BatteryMaintenanceManager.deviceHasRechargeableBattery($0) || BatteryMaintenanceManager.isAirTag($0)) && !$0.batteryTrackingIgnored
        }
        var counts: [String: Int] = [:]
        for item in batteryItems {
            let cat = itemRootCategory(item)
            counts[cat, default: 0] += 1
        }
        return counts
    }
    
    private var sortedBatteryCategories: [String] {
        let counts = batteryCategoryCounts
        return counts.keys.sorted { cat0, cat1 in
            let c0 = counts[cat0] ?? 0
            let c1 = counts[cat1] ?? 0
            if c0 != c1 { return c0 > c1 }
            return categoryTitle(cat0).localizedStandardCompare(categoryTitle(cat1)) == .orderedAscending
        }
    }
    
    private var batteryCounts: (all: Int, overdue: Int, dueSoon: Int, healthy: Int, untracked: Int, unactivated: Int) {
        var batteryItems = collectionItems.filter {
            (BatteryMaintenanceManager.deviceHasRechargeableBattery($0) || BatteryMaintenanceManager.isAirTag($0)) && !$0.batteryTrackingIgnored
        }
        if let cat = selectedBatteryCategory {
            batteryItems = batteryItems.filter { itemRootCategory($0) == cat }
        }
        var overdue = 0
        var dueSoon = 0
        var healthy = 0
        var untracked = 0
        var unactivated = 0
        
        for item in batteryItems {
            if BatteryMaintenanceManager.isAirTag(item) && BatteryMaintenanceManager.isAirTagInsulated(item) {
                unactivated += 1
            } else if item.isDailyDriver && !BatteryMaintenanceManager.isAirTag(item) {
                healthy += 1
            } else {
                let st = BatteryMaintenanceManager.evaluateMaintenance(for: item)?.status ?? .untracked
                switch st {
                case .overdue: overdue += 1
                case .dueSoon: dueSoon += 1
                case .healthy, .inUse: healthy += 1
                case .untracked: untracked += 1
                }
            }
        }
        return (batteryItems.count, overdue, dueSoon, healthy, untracked, unactivated)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tier 1: 硬件品类过滤 (Category Chips)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 全部硬件品类
                    MacCategoryChipPill(
                        title: isChineseLanguage ? "全部品类" : "All Categories",
                        icon: "square.grid.2x2",
                        count: batteryTotalCount,
                        isSelected: selectedBatteryCategory == nil
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            selectedBatteryCategory = nil
                        }
                    }
                    
                    // 仅展示包含电池设备的品类
                    ForEach(sortedBatteryCategories, id: \.self) { cat in
                        let count = batteryCategoryCounts[cat] ?? 0
                        MacCategoryChipPill(
                            title: categoryTitle(cat),
                            icon: categorySymbol(cat),
                            count: count,
                            isSelected: selectedBatteryCategory == cat
                        ) {
                            withAnimation(.snappy(duration: 0.22)) {
                                if selectedBatteryCategory == cat {
                                    selectedBatteryCategory = nil
                                } else {
                                    selectedBatteryCategory = cat
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }
            
            Divider()
                .opacity(0.35)
                .padding(.horizontal, 16)
            
            // Tier 2: 电池健康状态胶囊 (Status Chips)
            MacBatteryStatusChipsBar(
                batteryStatusFilter: $batteryStatusFilter,
                counts: batteryCounts,
                onBatchCharge: onBatchCharge
            )
        }
        .background(macWindowBackground)
    }
}
