//
//  MacWorkbenchBatteryBar.swift
//  Pomme
//
//  Mac 策展人工作台电池维护状态过滤胶囊栏与硬件品类胶囊栏 (Battery Maintenance Chips Bar)
//

import SwiftUI

enum MacBatteryStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case overdue = "Overdue"
    case dueSoon = "Due Soon"
    case healthy = "Healthy"
    case untracked = "Untracked"
    case unactivatedAirTags = "Unactivated AirTags"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .all: return isChineseLanguage ? "全部电池" : "All Hardware"
        case .overdue: return isChineseLanguage ? "已逾期" : "Overdue"
        case .dueSoon: return isChineseLanguage ? "建议补电" : "Due Soon"
        case .healthy: return isChineseLanguage ? "状态良好" : "Healthy"
        case .untracked: return isChineseLanguage ? "未记录" : "Untracked"
        case .unactivatedAirTags: return isChineseLanguage ? "绝缘 AirTag" : "Unactivated AirTags"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "battery.100.bolt"
        case .overdue: return "exclamationmark.triangle.fill"
        case .dueSoon: return "clock.badge.exclamationmark"
        case .healthy: return "checkmark.shield.fill"
        case .untracked: return "questionmark.circle"
        case .unactivatedAirTags: return "shield.lefthalf.filled.badge.checkmark"
        }
    }
}

// MARK: - 电池状态单项胶囊芯片 (Battery Status Chip)
struct MacBatteryStatusChip: View {
    let filter: MacBatteryStatusFilter
    let count: Int
    let color: Color
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? color : color.opacity(0.85))
                
                Text(filter.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                
                Text("\(count)")
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(
                        isSelected
                            ? color.opacity(0.2)
                            : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
                    .foregroundStyle(isSelected ? color : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.12) : Color.primary.opacity(0.035))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? color.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.2 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 电池巡检状态检索横向栏 (Battery Status Filter Chips Bar)
struct MacBatteryStatusChipsBar: View {
    @Binding var batteryStatusFilter: MacBatteryStatusFilter
    let counts: (all: Int, overdue: Int, dueSoon: Int, healthy: Int, untracked: Int, unactivated: Int)
    let onBatchCharge: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                MacBatteryStatusChip(
                    filter: .all,
                    count: counts.all,
                    color: .blue,
                    isSelected: batteryStatusFilter == .all
                ) {
                    toggleFilter(.all)
                }
                
                MacBatteryStatusChip(
                    filter: .overdue,
                    count: counts.overdue,
                    color: .red,
                    isSelected: batteryStatusFilter == .overdue
                ) {
                    toggleFilter(.overdue)
                }
                
                MacBatteryStatusChip(
                    filter: .dueSoon,
                    count: counts.dueSoon,
                    color: .orange,
                    isSelected: batteryStatusFilter == .dueSoon
                ) {
                    toggleFilter(.dueSoon)
                }
                
                MacBatteryStatusChip(
                    filter: .healthy,
                    count: counts.healthy,
                    color: .green,
                    isSelected: batteryStatusFilter == .healthy
                ) {
                    toggleFilter(.healthy)
                }
                
                MacBatteryStatusChip(
                    filter: .untracked,
                    count: counts.untracked,
                    color: .secondary,
                    isSelected: batteryStatusFilter == .untracked
                ) {
                    toggleFilter(.untracked)
                }
                
                if counts.unactivated > 0 || batteryStatusFilter == .unactivatedAirTags {
                    MacBatteryStatusChip(
                        filter: .unactivatedAirTags,
                        count: counts.unactivated,
                        color: .green,
                        isSelected: batteryStatusFilter == .unactivatedAirTags
                    ) {
                        toggleFilter(.unactivatedAirTags)
                    }
                }
                
                Spacer(minLength: 12)
                
                Button(action: onBatchCharge) {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.badge.checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text(isChineseLanguage ? "批量补电" : "Batch Charge")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(isChineseLanguage ? "一键批量登记多台设备补电" : "Batch record charge for multiple devices")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }
    
    private func toggleFilter(_ filter: MacBatteryStatusFilter) {
        withAnimation(.snappy(duration: 0.22)) {
            if batteryStatusFilter == filter && filter != .all {
                batteryStatusFilter = .all
            } else {
                batteryStatusFilter = filter
            }
        }
    }
}

// MARK: - 通用硬件品类胶囊按钮 (Category Chip Pill)
struct MacCategoryChipPill: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                
                Text("\(count)")
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.2 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}
