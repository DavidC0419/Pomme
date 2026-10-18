//
//  BatteryMaintenanceViews.swift
//  Pomme
//
//  老设备补电日记与防饿死维护视图 (Battery Maintenance Diary & Charge Log Views)
//  管理所有带电池的收藏硬件，追踪上次补电时间、按季度（90天）周期倒数、
//  高亮濒危防止电池深度放电饿死，支持单台/批量一键记录补电与本地提醒。
//

import SwiftUI
import UserNotifications

/// 解析藏品在电池维护管理中的品类分组标识
func itemCategoryKey(for item: CollectionItem) -> String {
    let root = itemRootCategory(item)
    if root == "Watch" || root == "Apple Watch" { return "Watch" }
    if root == "配件" || root == "Accessories" || root == "Audio Accessories" || root == "音频配件" ||
       item.category.localizedCaseInsensitiveContains("accessories") || item.category.localizedCaseInsensitiveContains("配件") {
        return "Accessories"
    }
    if root == "输入设备" || root == "Input Devices" { return "Input Devices" }
    if root.isEmpty { return item.category }
    return root
}

struct BatteryMaintenanceView: View {
    let items: [CollectionItem]
    let onUpdate: (CollectionItem) -> Void
    var onBatchUpdate: (([CollectionItem]) -> Void)? = nil
    let onDelete: (String) -> Void

    @ObservedObject private var orderStore = RootCategoryOrderStore.shared
    @State private var searchText = ""
    @State private var selectedFilter: MaintenanceFilter = .all
    @State private var selectedCategories: Set<String> = []
    @State private var expandedCategories: Set<String> = [] // 默认折叠，展开的分类保存在此处
    @State private var isUnactivatedAirTagsExpanded: Bool = true // 未启用 AirTag 独立专区默认展开
    @State private var quarterlyRemindersEnabled: Bool = true
    @State private var showingBatchChargeSheet: Bool = false
    @State private var showingDecommissionedSheet: Bool = false
    @State private var showingReorderSheet: Bool = false
    @State private var showingCloudSync: Bool = false
    @State private var lastUntrackedItem: CollectionItem? = nil
    @State private var editingChargeItem: CollectionItem? = nil
    @State private var inspectingItem: CollectionItem? = nil
    @State private var quickChargingItem: CollectionItem? = nil
    @AppStorage("batteryQuarterlyRemindersEnabled") private var storedReminderSetting: Bool = true

    enum MaintenanceFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case overdue = "Overdue"
        case dueSoon = "Due Soon"
        case healthy = "Healthy"
        case untracked = "Untracked"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All Hardware"
            case .overdue: return "Overdue"
            case .dueSoon: return "Due Soon"
            case .healthy: return "Healthy"
            case .untracked: return "Untracked"
            }
        }
    }

    private let defaultBatteryCategoryOrder: [String] = [
        "iPhone", "Mac", "iPad", "Watch", "AirPods", "Beats", "iPod", "Vision Pro", "Accessories", "Input Devices", "Home"
    ]

    private var batteryCategoryOrder: [String] {
        orderStore.orderedBatteryCategories(from: defaultBatteryCategoryOrder)
    }

    // MARK: - 单次线性扫描与视图数据结构 (Single-Pass Processed Data Pipeline)
    struct DecoratedItem: Identifiable, Equatable {
        var id: String { item.id }
        let item: CollectionItem
        let categoryKey: String
        let status: BatteryMaintenanceStatus
        let rank: Int
        let remainingDays: Int?
        let elapsedDays: Int?

        static func == (lhs: DecoratedItem, rhs: DecoratedItem) -> Bool {
            lhs.item.id == rhs.item.id &&
            lhs.categoryKey == rhs.categoryKey &&
            lhs.status == rhs.status &&
            lhs.remainingDays == rhs.remainingDays &&
            lhs.elapsedDays == rhs.elapsedDays &&
            lhs.item.lastCharged == rhs.item.lastCharged &&
            lhs.item.customCycleDays == rhs.item.customCycleDays &&
            lhs.item.isDailyDriver == rhs.item.isDailyDriver &&
            lhs.item.batteryTrackingIgnored == rhs.item.batteryTrackingIgnored
        }
    }

    struct CategoryMaintenanceSection: Identifiable {
        var id: String { category }
        let category: String
        let items: [DecoratedItem]
        let statusCounts: (overdue: Int, dueSoon: Int, healthy: Int, untracked: Int)
    }

    struct ProcessedBatteryData {
        let allBatteryItems: [CollectionItem]
        let maintenanceQueueItems: [CollectionItem]
        let decommissionedItems: [CollectionItem]
        let unactivatedAirTags: [CollectionItem]
        let inUseExemptCount: Int
        let overdueCount: Int
        let dueSoonCount: Int
        let healthyCount: Int
        let untrackedCount: Int
        let categoryCounts: [String: Int]
        let availableCategories: [String]
        let sections: [CategoryMaintenanceSection]
    }

    private func processBatteryData() -> ProcessedBatteryData {
        // 1. 单次遍历：提取带电池设备并按硬件序列号防御性去重
        var seenSerials: Set<String> = []
        var allBattery: [CollectionItem] = []
        allBattery.reserveCapacity(items.count)

        for item in items {
            guard BatteryMaintenanceManager.deviceHasRechargeableBattery(item) else { continue }
            let isAirTag = item.category == "AirTag" || item.name.contains("AirTag")
            if let sn = item.serialNumber, isUniqueHardwareSerial(sn), !isAirTag {
                if seenSerials.contains(sn) { continue }
                seenSerials.insert(sn)
            }
            allBattery.append(item)
        }

        // 2. 单次遍历：分流为停用、日常在用、未启用绝缘AirTag、维护队列
        var decommissioned: [CollectionItem] = []
        var unactivatedAirTags: [CollectionItem] = []
        var queueItems: [CollectionItem] = []
        var inUseCount = 0

        for item in allBattery {
            if item.batteryTrackingIgnored {
                decommissioned.append(item)
            } else if BatteryMaintenanceManager.isAirTag(item) && BatteryMaintenanceManager.isAirTagInsulated(item) {
                // 尚未启用的备用 AirTag（插有绝缘片，物理切断回路，零自放电）：单独列出，绝不与补电设备混杂
                unactivatedAirTags.append(item)
            } else if item.isDailyDriver && !BatteryMaintenanceManager.isAirTag(item) {
                inUseCount += 1
            } else {
                queueItems.append(item)
            }
        }

        // 3. 单次遍历维护队列：预先计算状态与剩余天数，并累加全局与分类统计指标
        var overdue = 0
        var dueSoon = 0
        var healthy = 0
        var untracked = 0
        var catCounts: [String: Int] = [:]

        var decoratedQueue: [DecoratedItem] = []
        decoratedQueue.reserveCapacity(queueItems.count)

        for item in queueItems {
            let catKey = itemCategoryKey(for: item)
            catCounts[catKey, default: 0] += 1

            let snapshot = BatteryMaintenanceManager.evaluateMaintenance(for: item)
            let st = snapshot?.status ?? .untracked
            let rem = snapshot?.remainingDays
            let elapsed = snapshot?.elapsedDays
            let rk: Int
            switch st {
            case .overdue:
                overdue += 1
                rk = 0
            case .dueSoon:
                dueSoon += 1
                rk = 1
            case .untracked:
                untracked += 1
                rk = 2
            case .healthy:
                healthy += 1
                rk = 3
            case .inUse:
                rk = 4
            }

            decoratedQueue.append(DecoratedItem(
                item: item,
                categoryKey: catKey,
                status: st,
                rank: rk,
                remainingDays: rem,
                elapsedDays: elapsed
            ))
        }

        // 按用户偏好排序分类
        let order = batteryCategoryOrder
        let availCats = catCounts.keys.sorted { cat1, cat2 in
            let idx1 = order.firstIndex(of: cat1) ?? 999
            let idx2 = order.firstIndex(of: cat2) ?? 999
            if idx1 != idx2 { return idx1 < idx2 }
            return cat1 < cat2
        }

        // 4. 应用筛选条件（状态、多选分类、搜索）
        let filter = selectedFilter
        let categoriesFilter = selectedCategories
        let cleanSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var filteredDecorated = decoratedQueue.filter { dec in
            switch filter {
            case .all: break
            case .overdue: if dec.status != .overdue { return false }
            case .dueSoon: if dec.status != .dueSoon { return false }
            case .healthy: if dec.status != .healthy { return false }
            case .untracked: if dec.status != .untracked { return false }
            }

            if !categoriesFilter.isEmpty && !categoriesFilter.contains(dec.categoryKey) {
                return false
            }

            if !cleanSearch.isEmpty {
                let it = dec.item
                let matches = it.displayName.localizedCaseInsensitiveContains(cleanSearch) ||
                              it.category.localizedCaseInsensitiveContains(cleanSearch) ||
                              (it.model?.localizedCaseInsensitiveContains(cleanSearch) ?? false) ||
                              (it.serialNumber?.localizedCaseInsensitiveContains(cleanSearch) ?? false) ||
                              (it.battery?.localizedCaseInsensitiveContains(cleanSearch) ?? false) ||
                              (it.lastCharged?.localizedCaseInsensitiveContains(cleanSearch) ?? false)
                if !matches { return false }
            }

            return true
        }

        // 按优先级与剩余天数严格确定性排序（多级仲裁，彻底消除排序抖动和错位误触）
        filteredDecorated.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            let remA = a.remainingDays ?? -9999
            let remB = b.remainingDays ?? -9999
            if remA != remB { return remA < remB }
            if a.item.displayName != b.item.displayName { return a.item.displayName < b.item.displayName }
            if (a.item.color ?? "") != (b.item.color ?? "") { return (a.item.color ?? "") < (b.item.color ?? "") }
            return a.item.id < b.item.id
        }

        // 按品类打包成分组 Section
        var groupedSections: [String: [DecoratedItem]] = [:]
        for dec in filteredDecorated {
            groupedSections[dec.categoryKey, default: []].append(dec)
        }

        let sortedSectionKeys = groupedSections.keys.sorted { cat1, cat2 in
            let idx1 = order.firstIndex(of: cat1) ?? 999
            let idx2 = order.firstIndex(of: cat2) ?? 999
            if idx1 != idx2 { return idx1 < idx2 }
            return cat1 < cat2
        }

        var sections: [CategoryMaintenanceSection] = []
        sections.reserveCapacity(sortedSectionKeys.count)
        for cat in sortedSectionKeys {
            guard let list = groupedSections[cat], !list.isEmpty else { continue }
            var catOverdue = 0
            var catDueSoon = 0
            var catHealthy = 0
            var catUntracked = 0

            for d in list {
                switch d.status {
                case .overdue: catOverdue += 1
                case .dueSoon: catDueSoon += 1
                case .healthy: catHealthy += 1
                case .untracked: catUntracked += 1
                default: break
                }
            }

            sections.append(CategoryMaintenanceSection(
                category: cat,
                items: list,
                statusCounts: (catOverdue, catDueSoon, catHealthy, catUntracked)
            ))
        }

        let filteredUnactivated = unactivatedAirTags.filter { it in
            if cleanSearch.isEmpty { return true }
            return it.displayName.localizedCaseInsensitiveContains(cleanSearch) ||
                   it.category.localizedCaseInsensitiveContains(cleanSearch) ||
                   (it.model?.localizedCaseInsensitiveContains(cleanSearch) ?? false) ||
                   (it.serialNumber?.localizedCaseInsensitiveContains(cleanSearch) ?? false) ||
                   (it.customName?.localizedCaseInsensitiveContains(cleanSearch) ?? false) ||
                   (it.notes?.localizedCaseInsensitiveContains(cleanSearch) ?? false)
        }

        return ProcessedBatteryData(
            allBatteryItems: allBattery,
            maintenanceQueueItems: queueItems,
            decommissionedItems: decommissioned,
            unactivatedAirTags: filteredUnactivated,
            inUseExemptCount: inUseCount,
            overdueCount: overdue,
            dueSoonCount: dueSoon,
            healthyCount: healthy,
            untrackedCount: untracked,
            categoryCounts: catCounts,
            availableCategories: availCats,
            sections: sections
        )
    }

    var body: some View {
        let data = processBatteryData()

        VStack(spacing: 0) {
            // 吸顶搜索
            PinnedSearchField(
                text: $searchText,
                prompt: "Search battery hardware (MacBook, iPod, Beats, Model, SN)"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. 顶部统计大盘 (Dashboard Cards)
                    metricsDashboard(data: data)

                    // 2. 季度周期提醒开关与批量补电操作栏
                    actionControlBar

                    // 3. 分类多选筛选胶囊条 (Category Multi-Select Filter Bar)
                    categoryFilterBar(data: data)

                    // 撤销停止跟踪横幅 (Undo Banner)
                    if let last = lastUntrackedItem {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.slash.fill")
                                .foregroundStyle(.orange)
                            Text("Stopped battery tracking for \(last.displayName)")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Button("Undo") {
                                withAnimation {
                                    BatteryMaintenanceManager.toggleBatteryTracking(for: last, onUpdate: onUpdate)
                                    lastUntrackedItem = nil
                                }
                            }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // 4. 设备补电维护卡片列表（按产品品类分组，采用 Section 深度惰性加载，彻底告别滑动卡顿）
                    if data.sections.isEmpty && data.unactivatedAirTags.isEmpty {
                        emptyFilterView
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(data.sections) { section in
                                let isExpanded = expandedCategories.contains(section.category)
                                Section {
                                    if isExpanded {
                                        ForEach(section.items) { dec in
                                            BatteryDeviceRowView(
                                                item: dec.item,
                                                categoryKey: section.category,
                                                isCategorySelected: selectedCategories.contains(section.category),
                                                precomputedStatus: dec.status,
                                                precomputedDaysElapsed: dec.elapsedDays,
                                                precomputedDaysRemaining: dec.remainingDays,
                                                onToggleCategory: { cat in
                                                    toggleCategoryFilter(cat)
                                                },
                                                onLogChargedToday: {
                                                    quickChargingItem = dec.item
                                                },
                                                onResetCycleToBase: {
                                                    withAnimation {
                                                        BatteryMaintenanceManager.resetCycleToBase(for: dec.item, onUpdate: onUpdate)
                                                    }
                                                },
                                                onOpenCustomLog: {
                                                    editingChargeItem = dec.item
                                                },
                                                onToggleDailyDriver: {
                                                    withAnimation {
                                                        BatteryMaintenanceManager.toggleDailyDriver(for: dec.item, onUpdate: onUpdate)
                                                    }
                                                },
                                                onToggleBatteryTracking: {
                                                    withAnimation {
                                                        BatteryMaintenanceManager.toggleBatteryTracking(for: dec.item, onUpdate: onUpdate)
                                                        lastUntrackedItem = dec.item
                                                    }
                                                },
                                                onInspect: {
                                                    inspectingItem = dec.item
                                                },
                                                onUpdateItem: onUpdate
                                            )
                                            .equatable()
                                        }
                                    }
                                } header: {
                                    categoryHeaderCard(for: section, isExpanded: isExpanded)
                                }
                            }

                            // 5. 专门单独列出的「未启用 AirTag · 绝缘片封存」独立专区（绝不与补电设备混淆）
                            if !data.unactivatedAirTags.isEmpty && (selectedFilter == .all || selectedFilter == .healthy) {
                                unactivatedAirTagsSection(items: data.unactivatedAirTags)
                            }
                        }
                    }
                }
                .padding()
            }
            .dismissKeyboardOnScroll()
            .onChange(of: searchText) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expandedCategories = Set(data.sections.map(\.category))
                    }
                }
            }
        }
        .navigationTitle("Battery Maintenance")
        .platformInlineTitleMode()
        .toolbar {
            ToolbarItem(placement: .appTopBarTrailing) {
                Menu {
                    Button {
                        showingBatchChargeSheet = true
                    } label: {
                        Label("Batch Record Charging", systemImage: "bolt.badge.checkmark")
                    }

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if expandedCategories.count == data.sections.count {
                                expandedCategories.removeAll()
                            } else {
                                expandedCategories = Set(data.sections.map(\.category))
                            }
                        }
                    } label: {
                        Label(
                            expandedCategories.count == data.sections.count ? "Collapse All Categories" : "Expand All Categories",
                            systemImage: expandedCategories.count == data.sections.count ? "chevron.right.circle" : "chevron.down.circle"
                        )
                    }

                    Button {
                        showingReorderSheet = true
                    } label: {
                        Label("Adjust Category Order", systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        showingDecommissionedSheet = true
                    } label: {
                        Label("Decommissioned Units (\(data.decommissionedItems.count))", systemImage: "bolt.slash")
                    }

                    if !data.unactivatedAirTags.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isUnactivatedAirTagsExpanded = true
                            }
                        } label: {
                            Label("Unactivated AirTags (\(data.unactivatedAirTags.count))", systemImage: "shield.lefthalf.filled.badge.checkmark")
                        }
                    }

                    Button {
                        toggleQuarterlyNotifications()
                    } label: {
                        Label(
                            quarterlyRemindersEnabled ? "Disable Daily 8 PM Reminders" : "Enable Daily 8 PM Reminders",
                            systemImage: quarterlyRemindersEnabled ? "bell.fill" : "bell.slash"
                        )
                    }

                    Divider()

                    Button {
                        showingCloudSync = true
                    } label: {
                        Label("iCloud Multi-Device Sync...", systemImage: "icloud.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingCloudSync) {
            CloudSyncSettingsSheet()
        }
        .sheet(item: $editingChargeItem) { item in
            CustomChargeLogSheet(
                item: item,
                onSave: { updated in
                    onUpdate(updated)
                    editingChargeItem = nil
                }
            )
        }
        .sheet(isPresented: $showingBatchChargeSheet) {
            BatchChargeLogSheet(
                items: data.maintenanceQueueItems,
                onBatchLog: { selectedItems, date, level, rawBatt in
                    BatteryMaintenanceManager.batchLogCharge(
                        for: selectedItems,
                        date: date,
                        remainingLevel: level,
                        batteryLevel: rawBatt,
                        onBatchUpdate: onBatchUpdate,
                        onUpdate: onUpdate
                    )
                }
            )
        }
        .sheet(isPresented: $showingDecommissionedSheet) {
            DecommissionedUnitsSheet(
                items: data.decommissionedItems,
                onResumeTracking: { item in
                    withAnimation {
                        BatteryMaintenanceManager.toggleBatteryTracking(for: item, onUpdate: onUpdate)
                    }
                }
            )
        }
        .sheet(isPresented: $showingReorderSheet) {
            ReorderBatteryCategoriesSheet(
                availableCategories: data.availableCategories,
                defaultCategories: defaultBatteryCategoryOrder
            )
        }
        .sheet(item: $inspectingItem) { item in
            NavigationStack {
                CollectionDetailView(
                    item: item,
                    favoriteIDs: .constant([]),
                    onSave: { updated in
                        onUpdate(updated)
                        inspectingItem = updated
                    },
                    onDelete: { id in
                        onDelete(id)
                        inspectingItem = nil
                    }
                )
            }
        }
        .confirmationDialog(
            "Record Charging · Observed Remaining Battery",
            isPresented: Binding(
                get: { quickChargingItem != nil },
                set: { if !$0 { quickChargingItem = nil } }
            ),
            titleVisibility: .visible,
            presenting: quickChargingItem
        ) { item in
            Button("80% - 100%") {
                withAnimation {
                    BatteryMaintenanceManager.logCharge(for: item, remainingLevel: .from80to100, onUpdate: onUpdate)
                }
            }
            Button("50% - 80%") {
                withAnimation {
                    BatteryMaintenanceManager.logCharge(for: item, remainingLevel: .from50to80, onUpdate: onUpdate)
                }
            }
            Button("20% - 50%") {
                withAnimation {
                    BatteryMaintenanceManager.logCharge(for: item, remainingLevel: .from20to50, onUpdate: onUpdate)
                }
            }
            Button("< 20%") {
                withAnimation {
                    BatteryMaintenanceManager.logCharge(for: item, remainingLevel: .under20, onUpdate: onUpdate)
                }
            }
            Button("0%", role: .destructive) {
                withAnimation {
                    BatteryMaintenanceManager.logCharge(for: item, remainingLevel: .zero, onUpdate: onUpdate)
                }
            }
            Button(isChineseLanguage ? "未充电" : "No Charge") {
                withAnimation {
                    BatteryMaintenanceManager.logCharge(for: item, remainingLevel: .noCharge, onUpdate: onUpdate)
                }
            }
            Button(isChineseLanguage ? "未记录" : "Unrecorded") {
                withAnimation {
                    BatteryMaintenanceManager.logCharge(for: item, remainingLevel: .unrecorded, onUpdate: onUpdate)
                }
            }
            Button(isChineseLanguage ? "取消" : "Cancel", role: .cancel) {
                quickChargingItem = nil
            }
        } message: { item in
            let cur = BatteryMaintenanceManager.cycleDays(for: item)
            let base = BatteryMaintenanceManager.baseCycleDays(for: item)
            let elapsed = BatteryMaintenanceManager.daysSinceLastCharged(item) ?? 0
            Text("\(item.displayName) · \(elapsed)d elapsed · Current cycle: \(cur)d (Base: \(base)d)")
        }
        .onAppear {
            quarterlyRemindersEnabled = storedReminderSetting
            if quarterlyRemindersEnabled {
                BatteryMaintenanceManager.scheduleQuarterlyReminders(for: items)
            }
        }
    }

    // MARK: - 统计总览卡片 (Metrics Dashboard)
    private func metricsDashboard(data: ProcessedBatteryData) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // 濒危已逾期（防饿死）
                MetricSummaryCard(
                    title: "Overdue",
                    count: data.overdueCount,
                    subtitle: "Starvation Risk",
                    color: .red,
                    icon: "exclamationmark.triangle.fill",
                    isSelected: selectedFilter == .overdue
                ) {
                    selectStatusFilter(.overdue, queueItems: data.maintenanceQueueItems)
                }

                // 建议近期补电
                MetricSummaryCard(
                    title: "Due Soon",
                    count: data.dueSoonCount,
                    subtitle: "Approaching Window",
                    color: .orange,
                    icon: "clock.badge.exclamationmark",
                    isSelected: selectedFilter == .dueSoon
                ) {
                    selectStatusFilter(.dueSoon, queueItems: data.maintenanceQueueItems)
                }
            }

            HStack(spacing: 10) {
                // 状态良好
                MetricSummaryCard(
                    title: "Healthy",
                    count: data.healthyCount,
                    subtitle: "Within Safe Cycle",
                    color: .green,
                    icon: "checkmark.shield.fill",
                    isSelected: selectedFilter == .healthy
                ) {
                    selectStatusFilter(.healthy, queueItems: data.maintenanceQueueItems)
                }

                // 尚未记录初次日期
                MetricSummaryCard(
                    title: "Untracked",
                    count: data.untrackedCount,
                    subtitle: "Initial Charge Needed",
                    color: .secondary,
                    icon: "questionmark.circle",
                    isSelected: selectedFilter == .untracked
                ) {
                    selectStatusFilter(.untracked, queueItems: data.maintenanceQueueItems)
                }
            }
        }
    }

    // MARK: - 快捷功能操作条
    private var actionControlBar: some View {
        HStack(spacing: 12) {
            // 季度通知状态指示与快捷开关
            Button {
                toggleQuarterlyNotifications()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: quarterlyRemindersEnabled ? "bell.badge.fill" : "bell.slash")
                        .font(.caption)
                        .foregroundStyle(quarterlyRemindersEnabled ? Color.green : Color.secondary)
                    Text(quarterlyRemindersEnabled ? "Quarterly Alerts Active" : "Alerts Paused")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // 一键批量补电按钮
            Button {
                showingBatchChargeSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.badge.checkmark")
                        .font(.caption.weight(.bold))
                    Text("Batch Charge")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 分类多选筛选胶囊条 (Category Multi-Select Filter Bar)
    private func categoryFilterBar(data: ProcessedBatteryData) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "全部品类" (All Categories)
                let isAllSelected = selectedCategories.isEmpty
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedCategories.removeAll()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("All")
                            .font(.caption.weight(isAllSelected ? .bold : .medium))
                        Text("\(data.maintenanceQueueItems.count)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(isAllSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.08), in: Capsule())
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(isAllSelected ? Color.accentColor : Color.primary.opacity(0.05), in: Capsule())
                    .foregroundStyle(isAllSelected ? .white : .primary)
                }
                .buttonStyle(.plain)

                // 各品类胶囊 (支持多选)
                ForEach(data.availableCategories, id: \.self) { cat in
                    let isSelected = selectedCategories.contains(cat)
                    let count = data.categoryCounts[cat] ?? 0

                    Button {
                        toggleCategoryFilter(cat)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: categorySymbol(cat))
                                .font(.system(size: 10, weight: .semibold))
                            Text(categoryTitle(cat))
                                .font(.caption.weight(isSelected ? .bold : .medium))
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.08), in: Capsule())
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.accentColor : Color.primary.opacity(0.05), in: Capsule())
                        .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

                // 调整分类顺序按钮
                Button {
                    showingReorderSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text(isChineseLanguage ? "排序" : "Reorder")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isChineseLanguage ? "调整分类排序" : "Reorder Categories")
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 状态筛选与联动展开分类
    private func selectStatusFilter(_ filter: MaintenanceFilter, queueItems: [CollectionItem]) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if selectedFilter == filter {
                selectedFilter = .all
                expandedCategories.removeAll()
            } else {
                selectedFilter = filter

                let targetItems: [CollectionItem] = {
                    switch filter {
                    case .all:
                        return queueItems
                    case .overdue:
                        return queueItems.filter { BatteryMaintenanceManager.maintenanceStatus(for: $0) == .overdue }
                    case .dueSoon:
                        return queueItems.filter { BatteryMaintenanceManager.maintenanceStatus(for: $0) == .dueSoon }
                    case .healthy:
                        return queueItems.filter { BatteryMaintenanceManager.maintenanceStatus(for: $0) == .healthy }
                    case .untracked:
                        return queueItems.filter { BatteryMaintenanceManager.maintenanceStatus(for: $0) == .untracked }
                    }
                }()

                let relevantCategories = Set(targetItems.map { itemCategoryKey(for: $0) })
                expandedCategories = relevantCategories
            }
        }
    }

    private func toggleCategoryFilter(_ cat: String) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if selectedCategories.contains(cat) {
                selectedCategories.remove(cat)
            } else {
                selectedCategories.insert(cat)
                expandedCategories.insert(cat)
            }
        }
    }

    // MARK: - 现代化卡片式品类标头（大面积点击 + 状态指示胶囊）
    private func categoryHeaderCard(for section: CategoryMaintenanceSection, isExpanded: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                if isExpanded {
                    expandedCategories.remove(section.category)
                } else {
                    expandedCategories.insert(section.category)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: categorySymbol(section.category))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(categoryTitle(section.category))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("\(section.items.count)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                            .foregroundStyle(.secondary)
                    }

                    // 品类健康状态标签（直接使用预计算好的统计数，0 循环损耗）
                    categoryStatusBadge(counts: section.statusCounts)
                }

                Spacer(minLength: 8)

                // 显式加大点击面积的详情展开/折叠胶囊指示器 (Super-Generous Hit Target Pill)
                HStack(spacing: 6) {
                    Text(appLocalized(isExpanded ? "Collapse" : "Details"))
                        .font(.footnote.weight(.semibold))
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.footnote.weight(.bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isExpanded ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08), in: Capsule())
                .foregroundStyle(isExpanded ? Color.accentColor : Color.primary)
                .frame(minHeight: 44)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(isExpanded ? 0.05 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isExpanded ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 品类标头健康状态徽标（直接接收预计算计数）
    @ViewBuilder
    private func categoryStatusBadge(counts: (overdue: Int, dueSoon: Int, healthy: Int, untracked: Int)) -> some View {
        if counts.overdue > 0 {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text(counts.overdue > 1 ? "Overdue (\(counts.overdue))" : "Overdue")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.12), in: Capsule())
        } else if counts.dueSoon > 0 {
            HStack(spacing: 3) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text(counts.dueSoon > 1 ? "Due Soon (\(counts.dueSoon))" : "Due Soon")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12), in: Capsule())
        } else if counts.healthy > 0 && counts.untracked == 0 {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
                Text("Healthy")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12), in: Capsule())
        } else if counts.healthy > 0 {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
                Text("Healthy (\(counts.healthy))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12), in: Capsule())
        } else if counts.untracked > 0 {
            HStack(spacing: 3) {
                Image(systemName: "questionmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Untracked")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    // MARK: - 未启用绝缘 AirTag 独立专区 (Unactivated AirTags · Insulated Storage)
    @ViewBuilder
    private func unactivatedAirTagsSection(items: [CollectionItem]) -> some View {
        Section {
            if isUnactivatedAirTagsExpanded {
                ForEach(items) { item in
                    UnactivatedAirTagRowView(
                        item: item,
                        onActivate: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                BatteryMaintenanceManager.toggleAirTagInsulationTab(for: item, onUpdate: onUpdate)
                            }
                        },
                        onInspect: {
                            inspectingItem = item
                        }
                    )
                }
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isUnactivatedAirTagsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.green)
                        .frame(width: 34, height: 34)
                        .background(Color.green.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(appLocalized("Unactivated AirTags · Insulated Storage"))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)

                            Text("\(items.count)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: Capsule())
                                .foregroundStyle(.green)
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(appLocalized("Zero Drain · Tab Inserted · Exempt from Charging"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Text(appLocalized(isUnactivatedAirTagsExpanded ? "Collapse" : "Details"))
                            .font(.caption2.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(isUnactivatedAirTagsExpanded ? 90 : 0))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isUnactivatedAirTagsExpanded ? Color.green.opacity(0.15) : Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(isUnactivatedAirTagsExpanded ? Color.green : Color.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.green.opacity(isUnactivatedAirTagsExpanded ? 0.05 : 0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isUnactivatedAirTagsExpanded ? Color.green.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    // MARK: - 空结果
    private var emptyFilterView: some View {
        VStack(spacing: 12) {
            Image(systemName: "battery.100.bolt")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No devices matching this filter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func toggleQuarterlyNotifications() {
        quarterlyRemindersEnabled.toggle()
        storedReminderSetting = quarterlyRemindersEnabled
        if quarterlyRemindersEnabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        BatteryMaintenanceManager.scheduleDailyBatteryReminders(for: items)
                    }
                }
            }
        } else {
            let center = UNUserNotificationCenter.current()
            center.getPendingNotificationRequests { requests in
                let ids = requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix("battery_quarterly_") || $0.hasPrefix("battery_daily_") }
                if !ids.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: ids)
                }
            }
        }
    }
}

// MARK: - 统计摘要单卡片
struct MetricSummaryCard: View {
    let title: String
    let count: Int
    let subtitle: String
    let color: Color
    let icon: String
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                    Spacer()
                    Text("\(count)")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? color.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 未启用绝缘 AirTag 专属独立卡片 (Unactivated AirTag Row View)
struct UnactivatedAirTagRowView: View, Equatable {
    let item: CollectionItem
    let onActivate: () -> Void
    let onInspect: () -> Void

    static func == (lhs: UnactivatedAirTagRowView, rhs: UnactivatedAirTagRowView) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.item.isDailyDriver == rhs.item.isDailyDriver &&
        lhs.item.battery == rhs.item.battery &&
        lhs.item.notes == rhs.item.notes
    }

    var body: some View {
        HStack(spacing: 12) {
            // 设备缩略图
            Button(action: onInspect) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.08))
                        .frame(width: 58, height: 58)
                    Image(item.artworkAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                }
            }
            .buttonStyle(.plain)

            // 信息主体
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let engraving = BatteryMaintenanceManager.airTagEngravingDescription(item) {
                        Text(engraving)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }

                    Text("Insulated")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 6) {
                    if let model = item.model, !model.isEmpty {
                        Text(model)
                    }
                    if let year = item.releaseYear, !year.isEmpty {
                        Text("· \(year)")
                    }
                    Text("· CR2032 Tab Stored")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                    Text("Circuit Disconnected · Pull Tab to Activate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            // 拔掉绝缘片启用按钮
            Button(action: onActivate) {
                VStack(spacing: 2) {
                    Image(systemName: "power")
                        .font(.body.weight(.bold))
                    Text(appLocalized("Pull Tab"))
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 54, height: 52)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pull tab to activate \(item.displayName)")
        }
        .padding(12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - 单台设备补电条目卡片 (Battery Device Row View)
struct BatteryDeviceRowView: View, Equatable {
    let item: CollectionItem
    var categoryKey: String? = nil
    var isCategorySelected: Bool = false
    var precomputedStatus: BatteryMaintenanceStatus? = nil
    var precomputedDaysElapsed: Int? = nil
    var precomputedDaysRemaining: Int? = nil
    var onToggleCategory: ((String) -> Void)? = nil
    var onLogChargedToday: () -> Void
    var onResetCycleToBase: (() -> Void)? = nil
    var onOpenCustomLog: () -> Void
    var onToggleDailyDriver: () -> Void
    var onToggleBatteryTracking: () -> Void
    var onInspect: () -> Void
    var onUpdateItem: ((CollectionItem) -> Void)? = nil

    static func == (lhs: BatteryDeviceRowView, rhs: BatteryDeviceRowView) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.item.lastCharged == rhs.item.lastCharged &&
        lhs.item.customCycleDays == rhs.item.customCycleDays &&
        lhs.item.isDailyDriver == rhs.item.isDailyDriver &&
        lhs.item.batteryTrackingIgnored == rhs.item.batteryTrackingIgnored &&
        lhs.item.name == rhs.item.name &&
        lhs.item.color == rhs.item.color &&
        lhs.item.battery == rhs.item.battery &&
        lhs.categoryKey == rhs.categoryKey &&
        lhs.isCategorySelected == rhs.isCategorySelected &&
        lhs.precomputedStatus == rhs.precomputedStatus &&
        lhs.precomputedDaysElapsed == rhs.precomputedDaysElapsed &&
        lhs.precomputedDaysRemaining == rhs.precomputedDaysRemaining
    }

    private var resolvedCategoryKey: String {
        categoryKey ?? itemCategoryKey(for: item)
    }

    private var isAirTag: Bool {
        BatteryMaintenanceManager.isAirTag(item)
    }

    private var isCoinCell: Bool {
        BatteryMaintenanceManager.isCoinCellDevice(item)
    }

    private var isInsulated: Bool {
        BatteryMaintenanceManager.isAirTagInsulated(item)
    }

    private var status: BatteryMaintenanceStatus {
        precomputedStatus ?? (BatteryMaintenanceManager.maintenanceStatus(for: item) ?? .untracked)
    }

    private var daysElapsed: Int? {
        precomputedDaysElapsed ?? BatteryMaintenanceManager.daysSinceLastCharged(item)
    }

    private var daysRemaining: Int? {
        precomputedDaysRemaining ?? BatteryMaintenanceManager.daysRemainingUntilDue(item)
    }

    var body: some View {
        HStack(spacing: 12) {
            // 设备缩略图
            Button(action: onInspect) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 58, height: 58)
                    Image(item.artworkAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                }
            }
            .buttonStyle(.plain)

            // 信息主体
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isAirTag {
                        if let engraving = BatteryMaintenanceManager.airTagEngravingDescription(item) {
                            Text(engraving)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        if isInsulated {
                            Text("Insulated")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        } else {
                            Text("In Use · CR2032")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: Capsule())
                        }
                    } else if isCoinCell {
                        Text("CR2032")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 4)

                    // 设备品类徽标标签
                    categoryPill
                }

                // 型号与序列号 / 电池类型
                HStack(spacing: 6) {
                    if let model = item.model, !model.isEmpty {
                        Text(model)
                    }
                    if let color = item.color, !color.isEmpty {
                        Text("· \(deviceColorLabel(color))")
                    }
                    if isCoinCell {
                        Text("· CR2032 Coin Cell")
                            .foregroundStyle(.secondary)
                    } else if let batt = item.battery, !batt.isEmpty {
                        Text("· \(batt)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                // 补电 / 换电池周期倒计时
                HStack(spacing: 4) {
                    if isAirTag && isInsulated {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Insulated · Zero Drain · Pull Tab to Activate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        if let last = item.lastCharged, !last.isEmpty {
                            Text(isCoinCell ? "\(appLocalized("Last Battery Replacement")): \(last)" : "Last: \(last)")
                            if let days = daysElapsed {
                                Text("(\(days)d ago)")
                            }
                        } else {
                            Text(isCoinCell ? "No Battery Replacement Date Recorded" : "No charge date recorded")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isCoinCell {
                            if let rem = daysRemaining {
                                if rem < 0 {
                                    Text("Overdue by \(-rem)d (Replace CR2032)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.red)
                                } else {
                                    Text("Due in \(rem)d (365d Cycle)")
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                }
                            } else {
                                Text("365d Cycle")
                                    .font(.caption2)
                                    .foregroundStyle(Color.secondary)
                            }
                        } else {
                            let cycle = BatteryMaintenanceManager.cycleDays(for: item)
                            let base = BatteryMaintenanceManager.baseCycleDays(for: item)
                            let isDynamic = (item.customCycleDays != nil && item.customCycleDays != base)
                            let cycleTag = isDynamic ? (isChineseLanguage ? "\(cycle)d 动态" : "\(cycle)d Dynamic") : "\(cycle)d"
                            if let rem = daysRemaining {
                                if rem < 0 {
                                    Text("Overdue by \(-rem)d (\(cycleTag))")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.red)
                                } else {
                                    Text("Due in \(rem)d (\(cycleTag))")
                                        .font(.caption2)
                                        .foregroundStyle(isDynamic ? Color.accentColor : Color.secondary)
                                }
                            } else {
                                Text("\(cycleTag) cycle")
                                    .font(.caption2)
                                    .foregroundStyle(isDynamic ? Color.accentColor : Color.secondary)
                            }
                        }
                    }
                }
                .font(.caption2)
            }

            // 动作按钮
            if isAirTag && isInsulated {
                Button {
                    withAnimation {
                        BatteryMaintenanceManager.toggleAirTagInsulationTab(for: item) { updated in
                            onUpdateItem?(updated)
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "power")
                            .font(.body.weight(.bold))
                        Text("Pull Tab to Activate")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pull insulation tab and activate AirTag")
            } else if isCoinCell {
                Button {
                    withAnimation {
                        BatteryMaintenanceManager.logCoinCellBatteryReplaced(for: item) { updated in
                            onUpdateItem?(updated)
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "battery.100.bolt")
                            .font(.body.weight(.bold))
                        Text(appLocalized("Replace"))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(width: 52, height: 52)
                    .background(status == .overdue ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(status == .overdue ? Color.red : Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record battery replaced for \(item.displayName)")
            } else {
                Button {
                    onLogChargedToday()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.body.weight(.bold))
                        Text("Charged")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(width: 52, height: 52)
                    .background(status == .overdue ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(status == .overdue ? Color.red : Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log charge for \(item.displayName)")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            if isAirTag {
                if isInsulated {
                    Button {
                        withAnimation {
                            BatteryMaintenanceManager.toggleAirTagInsulationTab(for: item) { updated in
                                onUpdateItem?(updated)
                            }
                        }
                    } label: {
                        Label("Pull Tab to Activate (In Use)", systemImage: "power")
                    }

                    Button {
                        withAnimation {
                            BatteryMaintenanceManager.logAirTagBatteryReplaced(for: item) { updated in
                                onUpdateItem?(updated)
                            }
                        }
                    } label: {
                        Label("Replace CR2032 Battery Today", systemImage: "battery.100.bolt")
                    }
                } else {
                    Button {
                        withAnimation {
                            BatteryMaintenanceManager.logAirTagBatteryReplaced(for: item) { updated in
                                onUpdateItem?(updated)
                            }
                        }
                    } label: {
                        Label("Replace CR2032 Battery (Reset 365d)", systemImage: "battery.100.bolt")
                    }

                    Button {
                        withAnimation {
                            BatteryMaintenanceManager.toggleAirTagInsulationTab(for: item) { updated in
                                onUpdateItem?(updated)
                            }
                        }
                    } label: {
                        Label("Insert Insulation Tab (Stored)", systemImage: "shield.slash")
                    }
                }

                Button {
                    onOpenCustomLog()
                } label: {
                    Label("Custom Battery Specs & Notes...", systemImage: "pencil.and.list.clipboard")
                }
            } else {
                Button {
                    onLogChargedToday()
                } label: {
                    Label(isChineseLanguage ? "今日已补电" : "Charged Today", systemImage: "bolt.fill")
                }

                Button {
                    withAnimation {
                        BatteryMaintenanceManager.logNoChargeNeeded(for: item) { updated in
                            onUpdateItem?(updated)
                        }
                    }
                } label: {
                    Label(isChineseLanguage ? "未充电 (电量充足 ≥70%)" : "No Charge (Sufficient ≥70%)", systemImage: "battery.75percent")
                }

                if item.customCycleDays != nil, let onResetCycleToBase {
                    Button {
                        onResetCycleToBase()
                    } label: {
                        Label("Reset to Base Cycle (\(BatteryMaintenanceManager.baseCycleDays(for: item))d)", systemImage: "arrow.counterclockwise")
                    }
                }

                Button {
                    onOpenCustomLog()
                } label: {
                    Label("Custom Charge Date & Health...", systemImage: "pencil.and.list.clipboard")
                }

                Divider()

                Button {
                    onToggleDailyDriver()
                } label: {
                    Label(
                        item.isDailyDriver ? "Remove from Daily Drivers" : "Mark as Daily Driver (Exempt)",
                        systemImage: item.isDailyDriver ? "sparkles.slash" : "sparkles"
                    )
                }
            }

            Button {
                onToggleBatteryTracking()
            } label: {
                Label(
                    item.batteryTrackingIgnored ? "Resume Battery Tracking" : "Stop Tracking Battery (Broken / Dead)",
                    systemImage: item.batteryTrackingIgnored ? "bolt.circle" : "bolt.slash"
                )
            }

            Button {
                onInspect()
            } label: {
                Label("Inspect Hardware Details", systemImage: "info.circle")
            }
        }
    }

    // MARK: - 设备分类标签（点击支持快速筛选与多选）
    private var categoryPill: some View {
        Button {
            onToggleCategory?(resolvedCategoryKey)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: categorySymbol(resolvedCategoryKey))
                    .font(.system(size: 9, weight: .semibold))
                Text(categoryTitle(resolvedCategoryKey))
                    .font(.system(size: 10, weight: isCategorySelected ? .bold : .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                isCategorySelected ? Color.accentColor : Color.primary.opacity(0.06),
                in: Capsule()
            )
            .foregroundStyle(isCategorySelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 自定义补电与健康录入面板 (Custom Charge Log Sheet)
struct CustomChargeLogSheet: View {
    let item: CollectionItem
    var onSave: (CollectionItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var chargeDate: Date = Date()
    @State private var remainingLevel: BatteryRemainingLevel = .unrecorded
    @State private var batteryHealth: String = ""
    @State private var maintenanceNote: String = ""
    @State private var batteryTrackingIgnored: Bool = false
    @State private var isAirTagInsulated: Bool = false

    private var isAirTag: Bool {
        BatteryMaintenanceManager.isAirTag(item)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hardware") {
                    HStack(spacing: 12) {
                        Image(item.artworkAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.subheadline.bold())
                            if let sn = item.serialNumber {
                                Text("SN: \(sn)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Maintenance Tracking") {
                    Toggle("Stop Tracking Battery (Broken / Dead Unit)", isOn: $batteryTrackingIgnored)
                }

                if isAirTag {
                    Section("Insulation Tab & Power State") {
                        Toggle("Insulation Tab Inserted (Zero Drain · Exempt)", isOn: $isAirTagInsulated)
                        if isAirTagInsulated {
                            Text("Physical pull-tab breaks battery contact. Zero self-discharge, zero starvation risk, no maintenance needed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Insulation tab pulled. Active daily driver consuming CR2032 coin cell (~365-day cycle).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !isAirTagInsulated {
                        Section("CR2032 Installation / Activation Date") {
                            DatePicker("Date Installed", selection: $chargeDate, displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                        }
                    }

                    Section("Battery Specs & Notes") {
                        TextField("Battery Specs (e.g. Panasonic CR2032)", text: $batteryHealth)
                        TextField("Engraving & Use Notes (e.g. Engraved: DC / Keychain)", text: $maintenanceNote)
                    }
                } else {
                    Section("Charge Date") {
                        DatePicker("Date Charged", selection: $chargeDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                    }

                    Section("Remaining Battery & Dynamic Cycle") {
                        Picker("Remaining Level", selection: $remainingLevel) {
                            ForEach(BatteryRemainingLevel.allCases) { lvl in
                                Text(lvl.label).tag(lvl)
                            }
                        }
                        .pickerStyle(.menu)

                        let current = BatteryMaintenanceManager.cycleDays(for: item)
                        let (base, next, isEarly) = BatteryMaintenanceManager.calculateAdaptedCycle(for: item, at: chargeDate, remainingLevel: remainingLevel)
                        HStack {
                            Text("Cycle Adjustment")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if isEarly {
                                Text("\(current)d → \(next)d (Drained in \(base)d · \(remainingLevel.cycleAdjustmentDays)d)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.red)
                            } else if next != current {
                                let adj = next - current
                                Text("\(current)d → \(next)d (\(adj > 0 ? "+\(adj)" : "\(adj)")d)")
                                    .font(.caption.bold())
                                    .foregroundStyle(adj > 0 ? Color.green : Color.red)
                            } else {
                                Text("\(current)d (Unchanged)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Battery Health & Notes") {
                        TextField("Battery Health (e.g. 90%, Good)", text: $batteryHealth)
                        TextField("Maintenance Notes (e.g. replaced cable, fully charged)", text: $maintenanceNote)
                    }
                }
            }
            .navigationTitle(isAirTag ? "AirTag Battery & Insulation" : "Record Charging")
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isAirTag {
                            var updated = item
                            updated.batteryTrackingIgnored = batteryTrackingIgnored
                            updated.customCycleDays = 365
                            let healthText = batteryHealth.trimmingCharacters(in: .whitespacesAndNewlines)
                            let defaultInsulatedBattery = isChineseLanguage ? "CR2032 (已插绝缘片)" : "CR2032 (Insulated)"
                            let defaultActiveBattery = isChineseLanguage ? "CR2032 纽扣电池" : "CR2032 Coin Cell"
                            if isAirTagInsulated {
                                updated.isDailyDriver = false
                                updated.battery = healthText.isEmpty ? defaultInsulatedBattery : healthText
                                let clean = maintenanceNote.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty {
                                    let insulatedPrefix = isChineseLanguage ? "已插绝缘片 · 零耗电免维护 · " : "Insulated · Zero Drain · "
                                    updated.notes = (clean.contains("绝缘片") || clean.contains("Insulated")) ? clean : insulatedPrefix + clean
                                }
                            } else {
                                updated.isDailyDriver = true
                                updated.lastCharged = BatteryMaintenanceManager.formatChargeDate(chargeDate)
                                updated.battery = healthText.isEmpty ? defaultActiveBattery : healthText
                                let clean = maintenanceNote.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty {
                                    updated.notes = clean
                                }
                            }
                            updated.updatedAt = Date()
                            onSave(updated)
                            dismiss()
                            return
                        }

                        var updated = item
                        updated.batteryTrackingIgnored = batteryTrackingIgnored
                        BatteryMaintenanceManager.logCharge(
                            for: updated,
                            date: chargeDate,
                            remainingLevel: remainingLevel,
                            batteryLevel: batteryHealth.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: maintenanceNote.trimmingCharacters(in: .whitespacesAndNewlines),
                            onUpdate: onSave
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                batteryTrackingIgnored = item.batteryTrackingIgnored
                if isAirTag {
                    isAirTagInsulated = BatteryMaintenanceManager.isAirTagInsulated(item)
                    if let b = item.battery, !b.isEmpty {
                        batteryHealth = b
                    } else {
                        batteryHealth = isAirTagInsulated ? (isChineseLanguage ? "CR2032 (已插绝缘片)" : "CR2032 (Insulated)") : (isChineseLanguage ? "CR2032 纽扣电池" : "CR2032 Coin Cell")
                    }
                    if let n = item.notes, !n.isEmpty {
                        maintenanceNote = n
                    }
                } else {
                    if let b = item.battery {
                        batteryHealth = b
                    }
                }
                if let parsed = BatteryMaintenanceManager.parseChargeDate(item.lastCharged) {
                    chargeDate = parsed
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
    }
}

// MARK: - 批量补电面板 (Batch Charge Log Sheet)
struct BatchChargeLogSheet: View {
    let items: [CollectionItem]
    var onBatchLog: ([CollectionItem], Date, BatteryRemainingLevel, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<String> = []
    @State private var chargeDate: Date = Date()
    @State private var remainingLevel: BatteryRemainingLevel = .unrecorded
    @State private var batteryLevel: String = ""
    @State private var search: String = ""

    private var filteredItems: [CollectionItem] {
        let clean = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nonInsulated = items.filter { !BatteryMaintenanceManager.isAirTagInsulated($0) }
        guard !clean.isEmpty else { return nonInsulated }
        return nonInsulated.filter {
            $0.displayName.localizedCaseInsensitiveContains(clean) ||
            $0.category.localizedCaseInsensitiveContains(clean) ||
            ($0.model?.localizedCaseInsensitiveContains(clean) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Charging Details") {
                    DatePicker("Date Charged", selection: $chargeDate, displayedComponents: [.date])

                    Picker("Observed Remaining Level", selection: $remainingLevel) {
                        ForEach(BatteryRemainingLevel.allCases) { lvl in
                            Text("\(lvl.label) (\(lvl.adjustmentBadge))").tag(lvl)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Battery Level Note (Optional, e.g. 100%)", text: $batteryLevel)
                }

                Section {
                    HStack {
                        Button("Select All Overdue") {
                            let overdue = items.filter { BatteryMaintenanceManager.maintenanceStatus(for: $0) == .overdue }
                            selectedIDs.formUnion(overdue.map(\.id))
                        }
                        Spacer()
                        Button("Select All") {
                            selectedIDs = Set(items.map(\.id))
                        }
                        Button("Clear") {
                            selectedIDs.removeAll()
                        }
                    }
                    .font(.caption.weight(.medium))
                }

                Section("Select Devices (\(selectedIDs.count) selected)") {
                    ForEach(filteredItems) { item in
                        HStack(spacing: 12) {
                            Image(item.artworkAssetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.lastCharged.map { "Last: \($0)" } ?? "Untracked")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedIDs.contains(item.id) ? Color.accentColor : Color.secondary.opacity(0.4))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedIDs.contains(item.id) {
                                selectedIDs.remove(item.id)
                            } else {
                                selectedIDs.insert(item.id)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search devices to batch charge")
            .navigationTitle("Batch Charge Log")
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete (\(selectedIDs.count))") {
                        let chosen = items.filter { selectedIDs.contains($0.id) }
                        onBatchLog(chosen, chargeDate, remainingLevel, batteryLevel.isEmpty ? nil : batteryLevel)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .onAppear {
                // 默认勾选所有已逾期的设备
                let overdue = items.filter { BatteryMaintenanceManager.maintenanceStatus(for: $0) == .overdue }
                selectedIDs = Set(overdue.map(\.id))
            }
        }
        .frame(minWidth: 360, minHeight: 480)
    }
}

// MARK: - 已停用电池跟踪/尸体设备管理面板 (Decommissioned Units Sheet)
struct DecommissionedUnitsSheet: View {
    let items: [CollectionItem]
    var onResumeTracking: (CollectionItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Decommissioned Units",
                        systemImage: "checkmark.seal.fill",
                        description: Text("All battery-equipped devices are currently actively tracked.")
                    )
                } else {
                    List {
                        Section {
                            Text("These devices are marked as broken, unbootable, or preserved for display only. They are excluded from quarterly charging reminders.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Section("Untracked Hardware (\(items.count))") {
                            ForEach(items) { item in
                                HStack(spacing: 12) {
                                    Image(item.artworkAssetName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayName)
                                            .font(.subheadline.weight(.semibold))
                                        HStack(spacing: 4) {
                                            Text(categoryTitle(item.category))
                                            if let model = item.model {
                                                Text("· \(model)")
                                            }
                                            if let color = item.color, !color.isEmpty {
                                                Text("· \(deviceColorLabel(color))")
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        onResumeTracking(item)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.uturn.backward")
                                            Text("Resume")
                                        }
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Untracked Hardware")
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
    }
}
