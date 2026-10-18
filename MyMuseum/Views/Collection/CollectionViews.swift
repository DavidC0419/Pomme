//
//  CollectionViews.swift
//  Pomme
//
//  藏品模块视图 (Collection Module Views)
//  包含我的藏品首页 (CollectionView)、藏品详情 (CollectionDetailView)、编辑 (EditCollectionItemView)、
//  添加设备 (AddDeviceCatalogView / AddCollectionDetailsView) 以及分类展示列表等。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 我的藏品主视图 (Collection View)
struct CollectionView: View {
    let items: [CollectionItem]
    let onUpdate: (CollectionItem) -> Void
    var onBatchUpdate: (([CollectionItem]) -> Void)? = nil
    let onDelete: (String) -> Void
    @State private var searchText = ""
    @State private var showingAddDevice = false
    @State private var importingCSV = false
    @State private var exportingCSV = false
    @State private var csvDocument = MuseumCSVDocument(data: Data())
    @State private var csvFilename = "MyMuseum-Devices"
    @State private var csvAlertMessage: String?
    @State private var showingClearSampleAlert = false
    @State private var showingMuseumTitleEditor = false
    @State private var museumTitleDraft = ""
    @State private var navigationPath: [HomeNavigationRoute] = []
    @AppStorage("museumTitle") private var museumTitle = ""
    @AppStorage("favoriteDeviceIDs") private var favoriteIDsData = Data()
    @AppStorage("ownedDeviceIDs") private var ownedIDsData = Data()
    @AppStorage("wantedDeviceIDs") private var wantedIDsData = Data()

    private var favoriteIDs: Binding<Set<String>> {
        Binding(
            get: { decodeIDs(from: favoriteIDsData) },
            set: { favoriteIDsData = encodeIDs($0) }
        )
    }

    private var ownedIDs: Binding<Set<String>> {
        Binding(get: { decodeIDs(from: ownedIDsData) }, set: { ownedIDsData = encodeIDs($0) })
    }

    private var wantedIDs: Binding<Set<String>> {
        Binding(get: { decodeIDs(from: wantedIDsData) }, set: { wantedIDsData = encodeIDs($0) })
    }

    @State private var showingReorderSheet = false
    @State private var showingCloudSync = false
    @ObservedObject private var syncManager = CloudVaultSyncManager.shared
    @ObservedObject private var rootOrderStore = RootCategoryOrderStore.shared

    private struct CollectionDashboardData {
        let defaultCategories: [String]
        let categories: [String]
        let likedOwnedItems: [CollectionItem]
        let likedOwnedCatalogDevices: [Device]
        let inUseCount: Int
        let batterySummary: (total: Int, overdue: Int, dueSoon: Int)
        let categoryCounts: [String: Int]
        let categoryFallbacks: [String: String]
    }

    private var dashboardData: CollectionDashboardData {
        let now = Date()
        let favs = favoriteIDs.wrappedValue
        let owned = ownedIDs.wrappedValue

        var likedItems: [CollectionItem] = []
        var inventoryProductIDs = Set<String>()
        var inUse = 0
        var batteryTotal = 0
        var batteryOverdue = 0
        var batteryDueSoon = 0
        var catCounts: [String: Int] = [:]
        var catFallbacks: [String: String] = [:]
        var catMatchesSearch: [String: Bool] = [:]

        let isSearching = !searchText.isEmpty

        for item in items {
            if let cid = item.catalogID {
                inventoryProductIDs.insert(cid)
            }

            if favs.contains(item.favoriteKey) {
                likedItems.append(item)
            }

            if item.isDailyDriver {
                inUse += 1
            }

            if BatteryMaintenanceManager.deviceHasRechargeableBattery(item),
               (!item.isDailyDriver || BatteryMaintenanceManager.isAirTag(item)),
               !item.batteryTrackingIgnored {
                batteryTotal += 1
                if let snapshot = BatteryMaintenanceManager.evaluateMaintenance(for: item, relativeTo: now) {
                    if snapshot.status == .overdue {
                        batteryOverdue += 1
                    } else if snapshot.status == .dueSoon {
                        batteryDueSoon += 1
                    }
                }
            }

            let rootCat = itemRootCategory(item)
            catCounts[rootCat, default: 0] += 1
            if catFallbacks[rootCat] == nil {
                catFallbacks[rootCat] = item.artworkAssetName
            }

            if isSearching && catMatchesSearch[rootCat] != true {
                let matches = [item.displayName, item.name, item.category, item.model, item.productIdentifier, item.processor]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(searchText) }
                if matches {
                    catMatchesSearch[rootCat] = true
                }
            }
        }

        let likedDevices: [Device]
        if !favs.isEmpty && !owned.isEmpty {
            let candidateIDs = favs.intersection(owned).subtracting(inventoryProductIDs)
            if !candidateIDs.isEmpty {
                likedDevices = SearchCatalogProductIndex.products
                    .filter { candidateIDs.contains($0.id) }
                    .map(\.catalogDevice)
            } else {
                likedDevices = []
            }
        } else {
            likedDevices = []
        }

        let defCats = catCounts.keys
            .filter { isSearching ? (catMatchesSearch[$0] == true) : true }
            .sorted {
                categoryTitle($0).localizedStandardCompare(categoryTitle($1)) == .orderedAscending
            }

        let orderedCats = rootOrderStore.orderedCategories(from: defCats, isEncyclopedia: false)

        return CollectionDashboardData(
            defaultCategories: defCats,
            categories: orderedCats,
            likedOwnedItems: likedItems,
            likedOwnedCatalogDevices: likedDevices,
            inUseCount: inUse,
            batterySummary: (total: batteryTotal, overdue: batteryOverdue, dueSoon: batteryDueSoon),
            categoryCounts: catCounts,
            categoryFallbacks: catFallbacks
        )
    }

    private var defaultCategories: [String] { dashboardData.defaultCategories }
    private var categories: [String] { dashboardData.categories }
    private var likedOwnedItems: [CollectionItem] { dashboardData.likedOwnedItems }
    private var likedOwnedCatalogDevices: [Device] { dashboardData.likedOwnedCatalogDevices }
    private var batterySummaryCounts: (total: Int, overdue: Int, dueSoon: Int) { dashboardData.batterySummary }

    var body: some View {
        let dashboard = dashboardData
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // 搜索框吸顶，浏览长列表时不随滚动离开视线
                PinnedSearchField(text: $searchText, prompt: "Search your collection, models, or specs")
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center) {
                                HStack(spacing: 8) {
                                    Text(museumTitle.isEmpty ? appLocalized("My Apple Device Museum") : museumTitle)
                                        .font(.largeTitle.bold())
                                    Button {
                                        museumTitleDraft = museumTitle.isEmpty ? appLocalized("My Apple Device Museum") : museumTitle
                                        showingMuseumTitleEditor = true
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(appLocalized("Customize Museum Name"))
                                }
                                Spacer(minLength: 8)
                                Button { showingAddDevice = true } label: {
                                    Label("Add Device", systemImage: "plus")
                                        .labelStyle(.iconOnly)
                                        .font(.title3.weight(.semibold))
                                        .frame(width: 44, height: 44)
                                        .background(Color.accentColor, in: Circle())
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add Device")
                                Button { showingCloudSync = true } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: syncManager.isSyncing ? "arrow.triangle.2.circlepath.icloud" : (syncManager.isConfigured ? "icloud.fill" : "icloud"))
                                            .font(.title3.weight(.semibold))
                                            .frame(width: 44, height: 44)
                                            .foregroundStyle(syncManager.isConfigured ? Color.cyan : Color.primary)

                                        if syncManager.isConfigured {
                                            Circle()
                                                .fill(syncManager.isSyncing ? Color.blue : Color.green)
                                                .frame(width: 8, height: 8)
                                                .offset(x: -4, y: 8)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("iCloud Multi-Device Sync")

                                Menu {
                                    if SampleDataManager.hasSampleItems(in: items) {
                                        Button(role: .destructive) {
                                            showingClearSampleAlert = true
                                        } label: {
                                            Label(isChineseLanguage ? "快速清空演示示例数据" : "Clear Sample Devices", systemImage: "trash")
                                        }
                                        Divider()
                                    } else {
                                        Button {
                                            NotificationCenter.default.post(name: .loadSampleDevices, object: nil)
                                        } label: {
                                            Label(isChineseLanguage ? "载入功能演示示例数据 (6件)" : "Load Demonstration Sample Devices", systemImage: "sparkles")
                                        }
                                        Divider()
                                    }
                                    Button("Export Existing Devices CSV") {
                                        csvDocument = MuseumCSVDocument(data: MuseumCSV.export(items))
                                        csvFilename = "MyMuseum-Devices"
                                        exportingCSV = true
                                    }
                                    Button("Download Blank CSV Template") {
                                        csvDocument = MuseumCSVDocument(data: MuseumCSV.blankTemplate())
                                        csvFilename = "MyMuseum-Template"
                                        exportingCSV = true
                                    }
                                    Divider()
                                    Button("Import CSV") { importingCSV = true }
                                    Divider()
                                    Button {
                                        showingCloudSync = true
                                    } label: {
                                        Label("iCloud Multi-Device Sync...", systemImage: "icloud.and.arrow.up")
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down.square")
                                        .font(.title3.weight(.semibold))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("CSV Import and Export")
                            }

                            // 统计项与苹果风 [明 / 自动 / 暗] 外观调节按钮
                            HStack(alignment: .center) {
                                Text("\(items.count) items · \(categories.count) categories")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                AppleAppearanceSegmentedControl()
                            }

                            if SampleDataManager.hasSampleItems(in: items) {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isChineseLanguage ? "当前为功能演示示例数据 (共 6 件)" : "Currently Viewing Sample Data (6 items)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(isChineseLanguage ? "涵盖收藏、在用、防饿死补电预警、喜欢与愿望单。体验完毕后可随时一键清空。" : "Covers collection, in-use, battery maintenance, favorites & wishlist. Clear anytime to start your museum.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        showingClearSampleAlert = true
                                    } label: {
                                        Text(isChineseLanguage ? "快速清空示例" : "Clear Sample")
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.red.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            } else if items.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .font(.title3)
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isChineseLanguage ? "还没有录入设备？" : "No Devices Added Yet?")
                                            .font(.subheadline.weight(.semibold))
                                        Text(isChineseLanguage ? "一键载入功能演示示例数据，快速体验全部功能。" : "Load demonstration sample devices to explore all features.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        NotificationCenter.default.post(name: .loadSampleDevices, object: nil)
                                    } label: {
                                        Text(isChineseLanguage ? "载入示例" : "Load Sample")
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.accentColor, in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Favorites · Owned").font(.title2.bold())
                                Spacer()
                                if !likedOwnedItems.isEmpty || !likedOwnedCatalogDevices.isEmpty {
                                    Text("\(likedOwnedItems.count + likedOwnedCatalogDevices.count) items")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if likedOwnedItems.isEmpty && likedOwnedCatalogDevices.isEmpty {
                                Label("Tap the heart on an owned item or catalog entry to feature it here.", systemImage: "heart")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
                            } else {
                                FavoriteDeviceCarousel(
                                    items: dashboard.likedOwnedItems,
                                    devices: dashboard.likedOwnedCatalogDevices,
                                    onOpenItem: { navigationPath.append(.ownedItem($0.id)) },
                                    onOpenDevice: { navigationPath.append(.catalogDevice($0.id)) }
                                )
                            }
                        }

                        // MARK: - 常用设备与补电日记快捷入口（在“喜欢与已有”与“藏品分类”之间）
                        HStack(spacing: 12) {
                            // 1. 常用设备标签入口（无外露轮播，直接进入全平铺常用页）
                            NavigationLink(value: HomeNavigationRoute.dailyDrivers) {
                                InUseQuickAccessCard(count: dashboard.inUseCount)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)

                            // 2. 补电日记入口（季度防饿死维护日历）
                            NavigationLink(value: HomeNavigationRoute.batteryMaintenance) {
                                let summary = dashboard.batterySummary
                                BatteryLogQuickAccessCard(
                                    totalCount: summary.total,
                                    overdueCount: summary.overdue,
                                    dueSoonCount: summary.dueSoon
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("My Collection").font(.title2.bold())
                                Text(appLocalized("Grouped by owned devices"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                showingReorderSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text(appLocalized("Reorder"))
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        MagneticCategoryGridView(
                            categories: dashboard.categories,
                            isEncyclopedia: false,
                            categoryCount: { dashboard.categoryCounts[$0] ?? 0 },
                            fallbackArtwork: { dashboard.categoryFallbacks[$0] },
                            onSelect: { category in
                                navigationPath.append(HomeNavigationRoute.category(category))
                            }
                        )
                    }
                    .padding()
                }
                .dismissKeyboardOnScroll()
            }
            .navigationTitle("My Collection")
            .platformInlineTitleMode()
            .navigationDestination(for: HomeNavigationRoute.self) { route in
                switch route {
                case .category(let category):
                    OwnedCatalogCategoryView(category: category, items: items, favoriteIDs: favoriteIDs, onSave: onUpdate, onDelete: onDelete)
                case .branch(let category, let branch):
                    OwnedCatalogCategoryView(category: category, items: items, favoriteIDs: favoriteIDs, onSave: onUpdate, onDelete: onDelete, macBranch: branch)
                case .family(let category, let macBranch, let family):
                    OwnedCatalogCategoryView(category: category, items: items, favoriteIDs: favoriteIDs, onSave: onUpdate, onDelete: onDelete, macBranch: macBranch, family: family)
                case .ownedItem(let itemID):
                    if let item = items.first(where: { $0.id == itemID }) {
                        CollectionDetailView(item: item, favoriteIDs: favoriteIDs, onSave: onUpdate, onDelete: onDelete)
                    } else {
                        ContentUnavailableView("Item not found", systemImage: "shippingbox")
                    }
                case .catalogDevice(let deviceID):
                    if let device = likedOwnedCatalogDevices.first(where: { $0.id == deviceID }) {
                        DeviceDetailView(device: device, ownedIDs: ownedIDs, wantedIDs: wantedIDs, favoriteIDs: favoriteIDs, onAddOwned: { onUpdate($0) }, onRemoveOwned: { onDelete($0) })
                    } else {
                        ContentUnavailableView("Device not found", systemImage: "shippingbox")
                    }
                case .dailyDrivers:
                    InUseDevicesView(items: items, onUpdate: onUpdate, onBatchUpdate: onBatchUpdate, onDelete: onDelete, favoriteIDs: favoriteIDs)
                case .batteryMaintenance:
                    BatteryMaintenanceView(items: items, onUpdate: onUpdate, onBatchUpdate: onBatchUpdate, onDelete: onDelete)
                }
            }
            .sheet(isPresented: $showingReorderSheet) {
                ReorderCategoriesSheet(isEncyclopedia: false, defaultCategories: dashboard.defaultCategories)
            }
            .sheet(isPresented: $showingAddDevice) {
                AddDeviceCatalogView(onAdd: onUpdate)
            }
            .sheet(isPresented: $showingCloudSync) {
                CloudSyncSettingsSheet()
            }
            .sheet(isPresented: $showingMuseumTitleEditor) {
                NavigationStack {
                    Form {
                        TextField("Museum Name", text: $museumTitleDraft)
                    }
                    .navigationTitle("Customize Museum Name")
                    .platformInlineTitleMode()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingMuseumTitleEditor = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                museumTitle = museumTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                showingMuseumTitleEditor = false
                            }
                        }
                    }
                }
                .frame(minWidth: 320, minHeight: 180)
            }
            .fileExporter(
                isPresented: $exportingCSV,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: csvFilename
            ) { result in
                if case .failure(let error) = result {
                    csvAlertMessage = String(format: appLocalized("CSV export failed: %@"), error.localizedDescription)
                }
            }
            .fileImporter(isPresented: $importingCSV, allowedContentTypes: [.commaSeparatedText, .text, .plainText]) { result in
                do {
                    let url = try result.get()
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    
                    var fileData: Data?
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
                    try? FileManager.default.removeItem(at: tempURL)
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        fileData = try? Data(contentsOf: tempURL)
                        try? FileManager.default.removeItem(at: tempURL)
                    } catch {
                        var coordError: NSError?
                        let coordinator = NSFileCoordinator()
                        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { readURL in
                            fileData = try? Data(contentsOf: readURL)
                        }
                    }
                    if fileData == nil {
                        fileData = try? Data(contentsOf: url)
                    }
                    guard let data = fileData, !data.isEmpty else {
                        csvAlertMessage = String(format: appLocalized("Error: Selected file is empty or could not be read (%@)."), url.lastPathComponent)
                        return
                    }
                    
                    let imported = try MuseumCSV.importing(data, filename: url.lastPathComponent)
                    if let onBatchUpdate {
                        onBatchUpdate(imported.items)
                    } else {
                        imported.items.forEach(onUpdate)
                    }
                    if imported.items.isEmpty {
                        csvAlertMessage = imported.diagnosticMessage ?? appLocalized("CSV import complete: 0 records.")
                    } else {
                        var message = String(format: appLocalized("CSV import complete: %lld records."), imported.items.count)
                        message += "\n" + String(format: appLocalized("Matched to the encyclopedia: %lld · Unmatched: %lld"),
                                                  imported.matchedCount, imported.unmatchedNames.count)
                        if !imported.unmatchedNames.isEmpty {
                            let shown = imported.unmatchedNames.prefix(10).joined(separator: ", ")
                            message += "\n" + shown + (imported.unmatchedNames.count > 10 ? " …" : "")
                        }
                        csvAlertMessage = message
                    }
                } catch {
                    csvAlertMessage = String(format: appLocalized("CSV import failed: %@"), error.localizedDescription)
                }
            }
            .alert("CSV", isPresented: Binding(
                get: { csvAlertMessage != nil },
                set: { if !$0 { csvAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { csvAlertMessage = nil }
            } message: {
                Text(csvAlertMessage ?? "")
            }
            .alert(isChineseLanguage ? "清空演示示例数据" : "Clear Sample Devices", isPresented: $showingClearSampleAlert) {
                Button(isChineseLanguage ? "取消" : "Cancel", role: .cancel) { }
                Button(isChineseLanguage ? "确认清空" : "Clear", role: .destructive) {
                    NotificationCenter.default.post(name: .clearSampleDevices, object: nil)
                }
            } message: {
                Text(isChineseLanguage ? "确定要清空全部 6 件功能演示示例设备吗？清空后将恢复空白博物馆，您可以开始自由录入自己的真实设备。" : "Are you sure you want to remove all 6 sample demonstration devices? You can start adding your own hardware.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openBatteryMaintenance)) { _ in
                if !navigationPath.contains(where: {
                    if case .batteryMaintenance = $0 { return true }
                    return false
                }) {
                    navigationPath.append(.batteryMaintenance)
                }
            }
        }
    }

    private func ownedCategoryCount(_ category: String) -> Int {
        dashboardData.categoryCounts[category] ?? 0
    }
}

// MARK: - 藏品卡片展示 (Collection Item Card)
struct CollectionItemCard: View {
    let item: CollectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            DeviceArtwork(item: item, compact: true)
            HStack(spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if SpatialMuseumStore.shared.hasModel(for: item.catalogID ?? item.id, name: item.name) {
                    Image(systemName: "cube.transparent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if BatteryMaintenanceManager.isAirTag(item) {
                HStack(spacing: 4) {
                    if let engraving = BatteryMaintenanceManager.airTagEngravingDescription(item) {
                        Text(engraving)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    if BatteryMaintenanceManager.isAirTagInsulated(item) {
                        Text("Insulated")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    } else if item.isDailyDriver {
                        Text("In Use")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
            }
            Text([item.model, item.releaseYear].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 从图鉴搜索并添加藏品视图 (Add Device Catalog View)
// 先从完整离线型号库中找到产品，再填写这台实体设备自己的信息。
struct AddDeviceCatalogView: View {
    let onAdd: (CollectionItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    private let records = loadSearchCatalog()

    private var results: [CatalogDisplayProduct] {
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let matched = records.filter { record in
            terms.allSatisfy { record.searchText.localizedCaseInsensitiveContains($0) }
        }
        return groupedCatalogProducts(matched)
            .sorted { left, right in
                let leftExact = left.name.localizedCaseInsensitiveCompare(searchText) == .orderedSame
                let rightExact = right.name.localizedCaseInsensitiveCompare(searchText) == .orderedSame
                if leftExact != rightExact { return leftExact }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            .prefix(100)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PinnedSearchField(text: $searchText, prompt: "Name, A-number, product number, or CPU")
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Search Apple products", systemImage: "magnifyingglass", description: Text("Search by product name, model number, identifier, or processor."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { product in
                        NavigationLink {
                            AddCollectionDetailsView(product: product, onAdd: onAdd)
                        } label: {
                            HStack(spacing: 12) {
                                CatalogDisplayArtwork(product: product)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(product.name).font(.headline)
                                    Text([categoryTitle(product.category), product.model, product.identifiers, product.year]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if !product.processor.isEmpty {
                                        Text(product.processor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .dismissKeyboardOnScroll()
                }
            }
            .navigationTitle("Add Device")
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 添加具体藏品配置与购买信息表单 (Add Collection Details View)
// 目录描述的是产品型号；本页记录的是用户手上这一件实物的购买与保管信息。
struct AddCollectionDetailsView: View {
    let product: CatalogDisplayProduct
    let initialColor: String?
    let onAdd: (CollectionItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customName = ""
    @State private var serialNumber = ""
    @State private var regionVersion = ""
    @State private var color: String
    @State private var memory = ""
    @State private var storage = ""
    @State private var purchaseDate = ""
    @State private var purchaseSource = ""
    @State private var warrantyStatus = ""
    @State private var price = ""
    @State private var notes = ""

    init(product: CatalogDisplayProduct, initialColor: String? = nil, onAdd: @escaping (CollectionItem) -> Void) {
        self.product = product
        self.initialColor = initialColor
        self.onAdd = onAdd
        let available = deviceColors(for: product.catalogDevice.id)
        let resolved = initialColor ?? available?.first ?? ""
        _color = State(initialValue: resolved)
    }

    var body: some View {
        Form {
            Section("Product Model") {
                LabeledContent("Name", value: product.name)
                if !product.model.isEmpty { LabeledContent("Model Number", value: product.model) }
                if !product.identifiers.isEmpty { LabeledContent("Product Identifier", value: product.identifiers) }
                if !product.year.isEmpty { LabeledContent("Release Year", value: product.year) }
                if !product.processor.isEmpty { LabeledContent("CPU", value: product.processor) }
            }
            Section("My Device") {
                TextField("Custom Name (Optional)", text: $customName)
                TextField("Serial Number (Optional)", text: $serialNumber)

                let availableColors = deviceColors(for: product.catalogDevice.id)
                if let availableColors, !availableColors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Color").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            if !color.isEmpty {
                                Text(deviceColorLabel(color))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        DeviceColorSelector(colors: availableColors, selection: color) { selected in
                            color = selected
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    TextField("Color (Optional)", text: $color)
                }

                TextField("Region Variant (e.g. CH/A, LL/A)", text: $regionVersion)
                TextField("Purchase Date (e.g. 2024-06)", text: $purchaseDate)
                TextField("Purchase Location / Source", text: $purchaseSource)
                TextField("Warranty (e.g. Covered until 2027-06)", text: $warrantyStatus)
                TextField("Memory", text: $memory)
                TextField("Storage Capacity", text: $storage)
                TextField("Price", text: $price)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle("Add Collection Details")
        .platformInlineTitleMode()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add to Collection") { addToCollection() }
            }
        }
    }

    private func addToCollection() {
        // 个人信息按“单件藏品”保存；相同型号可重复添加多台
        let item = CollectionItem(
            id: UUID().uuidString,
            name: product.name,
            category: product.category,
            productName: product.name,
            customName: optionalText(customName),
            model: optionalText(product.model),
            catalogID: product.catalogDevice.id,
            serialNumber: optionalText(serialNumber),
            modelVersion: nil,
            regionVersion: optionalText(regionVersion),
            productIdentifier: optionalText(product.identifiers),
            battery: nil,
            lastCharged: nil,
            screenSize: nil,
            processor: optionalText(product.processor),
            memory: optionalText(memory),
            storage: optionalText(storage),
            graphics: nil,
            color: optionalText(color),
            system: nil,
            osVersion: nil,
            jailbreak: nil,
            account: nil,
            releaseYear: optionalText(product.year),
            repairs: nil,
            purchaseDate: optionalText(purchaseDate),
            purchaseSource: optionalText(purchaseSource),
            warrantyStatus: optionalText(warrantyStatus),
            price: optionalText(price),
            notes: optionalText(notes)
        )
        onAdd(item)
        dismiss()
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 藏品详情字段与标签页枚举
struct DetailField: Identifiable {
    let id: String
    let title: String
    let value: String
}

enum DetailTab: Hashable {
    case info, specs
}

// MARK: - 藏品详情视图 (Collection Detail View)
struct CollectionDetailView: View {
    @State private var item: CollectionItem
    @State private var selectedTab: DetailTab = .info
    @State private var isSerialNumberHidden = false
    @Binding var favoriteIDs: Set<String>
    let onSave: (CollectionItem) -> Void
    let onDelete: (String) -> Void
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false
    @State private var showingSpatialGallery = false
    @State private var showingCustomChargeSheet = false
    @State private var coverToastMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    init(item: CollectionItem, favoriteIDs: Binding<Set<String>>, onSave: @escaping (CollectionItem) -> Void, onDelete: @escaping (String) -> Void) {
        _item = State(initialValue: item)
        _favoriteIDs = favoriteIDs
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Device Details", selection: $selectedTab) {
                Text("Device Info").tag(DetailTab.info)
                Text("Specs").tag(DetailTab.specs)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ZStack(alignment: .bottomTrailing) {
                        DeviceArtwork(item: item, compact: false)

                        // 快速切换 Daily Driver 状态按钮（位于设备图右下角）
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                item.isDailyDriver.toggle()
                                onSave(item)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.isDailyDriver ? "sparkles" : "plus")
                                Text(item.isDailyDriver ? "Daily Driver" : "Set Daily")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(item.isDailyDriver ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                item.isDailyDriver
                                    ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(Color.primary.opacity(item.isDailyDriver ? 0.2 : 0.1), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(14)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(item.displayName).font(.largeTitle.bold())

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    item.isDailyDriver.toggle()
                                    onSave(item)
                                }
                            } label: {
                                Image(systemName: item.isDailyDriver ? "sparkles" : "sparkle")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(item.isDailyDriver ? .blue : .secondary.opacity(0.6))
                                    .padding(6)
                                    .background(item.isDailyDriver ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.1), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help(item.isDailyDriver ? "In Daily Rotation" : "Set as Daily Driver")

                            Spacer()
                        }
                        Label(categoryTitle(item.category), systemImage: categorySymbol(item.category))
                            .foregroundStyle(.secondary)
                        if let model = item.model, !model.isEmpty {
                            Text(model).font(.title3.monospaced()).foregroundStyle(.secondary)
                        }

                        // 常用在用 / 补电维护状态指示条
                        HStack(spacing: 8) {
                            if item.batteryTrackingIgnored {
                                HStack(spacing: 5) {
                                    Image(systemName: "bolt.slash.fill")
                                    Text("Untracked · Decommissioned")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.12), in: Capsule())

                                Spacer()

                                Button {
                                    withAnimation {
                                        BatteryMaintenanceManager.toggleBatteryTracking(for: item) { updated in
                                            item = updated
                                            onSave(updated)
                                        }
                                    }
                                } label: {
                                    Text("Resume Tracking")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                            } else if BatteryMaintenanceManager.isAirTag(item) {
                                let isInsulated = BatteryMaintenanceManager.isAirTagInsulated(item)
                                if isInsulated {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark.shield.fill")
                                        Text("Insulated · Zero Drain")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.green.opacity(0.12), in: Capsule())

                                    Spacer()

                                    Button {
                                        withAnimation {
                                            BatteryMaintenanceManager.toggleAirTagInsulationTab(for: item) { updated in
                                                item = updated
                                                onSave(updated)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "power")
                                            Text("Pull Tab to Activate")
                                        }
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor, in: Capsule())
                                        .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    let status = BatteryMaintenanceManager.maintenanceStatus(for: item) ?? .healthy
                                    HStack(spacing: 5) {
                                        Image(systemName: "battery.100")
                                        Text("In Use · CR2032 Powering")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.green.opacity(0.12), in: Capsule())

                                    if let rem = BatteryMaintenanceManager.daysRemainingUntilDue(item) {
                                        Text(rem < 0 ? "Overdue by \(-rem)d (Replace CR2032)" : "Due in \(rem)d (365d Cycle)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(rem < 0 ? .red : .secondary)
                                    }

                                    Spacer()

                                    Button {
                                        withAnimation {
                                            BatteryMaintenanceManager.logAirTagBatteryReplaced(for: item) { updated in
                                                item = updated
                                                onSave(updated)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "battery.100.bolt")
                                            Text("Replace Battery")
                                        }
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(status == .overdue ? Color.red : Color.accentColor, in: Capsule())
                                        .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else if item.isDailyDriver {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                    Text("Daily Driver · Exempt")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                            } else if BatteryMaintenanceManager.deviceHasRechargeableBattery(item) {
                                let status = BatteryMaintenanceManager.maintenanceStatus(for: item) ?? .untracked
                                HStack(spacing: 5) {
                                    Image(systemName: status.iconName)
                                    Text(status.title)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(status.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(status.color.opacity(0.12), in: Capsule())

                                if let rem = BatteryMaintenanceManager.daysRemainingUntilDue(item) {
                                    Text(rem < 0 ? "Overdue by \(-rem)d" : "\(rem)d left")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(status.color)
                                }

                                Spacer()

                                Button {
                                    withAnimation {
                                        BatteryMaintenanceManager.logCharge(for: item) { updated in
                                            item = updated
                                            onSave(updated)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bolt.fill")
                                        Text("Charged Today")
                                    }
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(status == .overdue ? Color.red : Color.accentColor, in: Capsule())
                                    .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }

                    if let spatialModel = SpatialMuseumStore.shared.model(for: item.catalogID ?? item.id, name: item.name, color: item.color) {
                        Button {
                            #if os(visionOS)
                            SpatialMuseumStore.shared.spawn(model: spatialModel)
                            #endif
                            showingSpatialGallery = true
                        } label: {
                            HStack(spacing: 12) {
                                #if os(visionOS)
                                Image(systemName: "visionpro")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                #elseif os(iOS)
                                Image(systemName: "arkit")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                #else
                                Image(systemName: "cube.transparent")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                #endif
                                VStack(alignment: .leading, spacing: 2) {
                                    #if os(visionOS)
                                    Text(appLocalized("View in Space"))
                                        .font(.headline)
                                    #elseif os(iOS)
                                    Text("View in 3D & AR")
                                        .font(.headline)
                                    #else
                                    Text("View in 3D")
                                        .font(.headline)
                                    #endif
                                    Text("1:1 Scale\(spatialModel.colorLabel != nil ? " · " + (spatialModel.colorLabel!) : "")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingSpatialGallery) {
                            #if os(visionOS)
                            NavigationStack {
                                SpatialMuseumView()
                            }
                            #else
                            Device3DInspectorSheet(item: spatialModel)
                            #endif
                        }
                    }

                    if selectedTab == .info {
                        personalInformation
                    } else {
                        configurationInformation
                    }

                    Button {
                        isEditing = true
                    } label: {
                        HStack {
                            Spacer()
                            Label(appLocalized("Edit Device Details"), systemImage: "pencil")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label(appLocalized("Delete Device"), systemImage: "trash")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(item.displayName)
        .platformInlineTitleMode()
        .platformHideTabBar()
        .toolbar {
            ToolbarItemGroup(placement: .appTopBarTrailing) {
                ShareLink(item: collectionShareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(appLocalized("Share Device"))

                Button {
                    toggleMembership(item.favoriteKey, in: $favoriteIDs)
                } label: {
                    Image(systemName: favoriteIDs.contains(item.favoriteKey) ? "heart.fill" : "heart")
                        .foregroundStyle(favoriteIDs.contains(item.favoriteKey) ? .pink : .primary)
                }
                .accessibilityLabel(appLocalized(favoriteIDs.contains(item.favoriteKey) ? "Remove from Favorites" : "Add to Favorites"))

                Button(appLocalized("Edit")) { isEditing = true }

                Menu {
                    Button {
                        isEditing = true
                    } label: {
                        Label(appLocalized("Edit Device Details"), systemImage: "pencil")
                    }

                    Button {
                        showingShareSheet = true
                    } label: {
                        Label(appLocalized("Share Device"), systemImage: "square.and.arrow.up")
                    }

                    let tiers = categoryHierarchyTiers(name: item.name, category: item.category)
                    CategoryCoverMenuContent(artworkAssetName: item.artworkAssetName, tiers: tiers) { updatedTitle in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            coverToastMessage = String(format: appLocalized("Cover updated for %@"), updatedTitle)
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            withAnimation { coverToastMessage = nil }
                        }
                    }

                    Divider()

                    Button {
                        withAnimation {
                            BatteryMaintenanceManager.toggleDailyDriver(for: item) { updated in
                                item = updated
                                onSave(updated)
                            }
                        }
                    } label: {
                        Label(
                            item.isDailyDriver ? appLocalized("Remove from Daily Drivers") : appLocalized("Set as Daily Driver"),
                            systemImage: item.isDailyDriver ? "sparkles.slash" : "sparkles"
                        )
                    }

                    if BatteryMaintenanceManager.deviceHasRechargeableBattery(item) {
                        Button {
                            showingCustomChargeSheet = true
                        } label: {
                            Label(appLocalized("Custom Battery Charge..."), systemImage: "bolt.fill")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(appLocalized("Delete Device"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(appLocalized("More Actions"))
            }
        }
        .sheet(isPresented: $isEditing) {
            EditCollectionItemView(item: item) { updated in
                item = updated
                onSave(updated)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(activityItems: [collectionShareText])
        }
        .sheet(isPresented: $showingCustomChargeSheet) {
            CustomChargeLogSheet(item: item) { updated in
                item = updated
                onSave(updated)
            }
        }
        .overlay(alignment: .top) {
            if let msg = coverToastMessage {
                Text(msg)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.85), in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert(appLocalized("Delete Device"), isPresented: $showingDeleteConfirmation) {
            Button(appLocalized("Cancel"), role: .cancel) { }
            Button(appLocalized("Delete"), role: .destructive) {
                onDelete(item.id)
                dismiss()
            }
        } message: {
            Text(String(format: appLocalized("Are you sure you want to remove \"%@\" from your collection? This action cannot be undone."), item.displayName))
        }
        .sheet(isPresented: $isEditing) {
            EditCollectionItemView(item: item) { updatedItem in
                item = updatedItem
                onSave(updatedItem)
            }
        }
    }

    private var collectionShareText: String {
        [
            item.displayName,
            "\(appLocalized("Device Name")): \(item.resolvedProductName)",
            item.model.map { "\(appLocalized("Model")): \($0)" },
            item.releaseYear.map { "\(appLocalized("Release Year")): \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    @ViewBuilder
    private var personalInformation: some View {
        let colorKey = item.colorLookupKey
        if let colors = deviceColors(for: colorKey) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Device Color").font(.headline)
                    Spacer()
                    if let cur = item.color, !cur.isEmpty {
                        Text(deviceColorLabel(cur))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                DeviceColorSelector(colors: colors, selection: item.color) { color in
                    var updatedItem = item
                    updatedItem.color = color
                    item = updatedItem
                    onSave(updatedItem)
                }
            }
        }
        detailSection("Device Profile", symbol: "number", fields: [
            field("Device Name", item.resolvedProductName),
            field("Model", item.model), field("Model Identifier", item.productIdentifier),
            field("Internal Model", item.modelVersion),
            field("Region Variant", item.regionVersion ?? inferredRegionVersion(item.modelVersion) ?? String(localized: "Not recorded")),
            field("Release Year", item.releaseYear), field("Color", item.color.map { deviceColorLabel($0) }),
            field("Serial Number", item.serialNumber ?? String(localized: "Not recorded"))
        ])
        detailSection("Purchase & Warranty", symbol: "shippingbox", fields: [
            field("Purchase Date", item.purchaseDate ?? String(localized: "Not recorded")),
            field("Purchase Source", item.purchaseSource ?? String(localized: "Not recorded")),
            field("Warranty Status", item.warrantyStatus ?? String(localized: "Not recorded")),
            field("Price", item.price), field("Notes", item.notes)
        ])
    }

    private var configurationInformation: some View {
        Group {
            detailSection("Hardware", symbol: "cpu", fields: [
                field("Display", item.screenSize),
                field("CPU", item.processor ?? catalogProcessor(for: item) ?? String(localized: "Not recorded")),
                field("Memory", item.memory ?? String(localized: "Not recorded")),
                field("Storage", item.storage ?? String(localized: "Not recorded")),
                field("Graphics", item.graphics), field("Battery", item.battery),
                field("Last Charged", item.lastCharged)
            ])
            detailSection("System & Maintenance", symbol: "gearshape.2", fields: [
                field("System", item.system), field("Version", item.osVersion),
                field("Jailbreak Status", item.jailbreak), field("Account Status", item.account),
                field("Repairs & Upgrades", item.repairs)
            ])
        }
    }

    private func field(_ title: String, _ value: String?) -> DetailField? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return DetailField(id: title, title: title, value: value == "Not recorded" ? appLocalized(value) : value)
    }

    @ViewBuilder
    private func detailSection(_ title: String, symbol: String, fields: [DetailField?]) -> some View {
        let fields = fields.compactMap { $0 }
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(appLocalized(title), systemImage: symbol)
                    .font(.headline)
                VStack(spacing: 0) {
                    ForEach(fields) { field in
                        HStack(alignment: .top, spacing: 16) {
                            Text(appLocalized(field.title))
                                .foregroundStyle(.secondary)
                                .frame(width: 92, alignment: .leading)
                            if field.title == "Serial Number", field.value != appLocalized("Not recorded") {
                                HStack(spacing: 8) {
                                    Text(isSerialNumberHidden ? String(repeating: "•", count: max(8, field.value.count)) : field.value)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button {
                                        isSerialNumberHidden.toggle()
                                    } label: {
                                        Image(systemName: isSerialNumberHidden ? "eye" : "eye.slash")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(appLocalized(isSerialNumberHidden ? "Show Serial Number" : "Hide Serial Number"))
                                }
                            } else {
                                Text(field.value)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        if field.id != fields.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

// MARK: - 编辑藏品表单 (Edit Collection Item View)
struct EditCollectionItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CollectionItem
    let onSave: (CollectionItem) -> Void

    init(item: CollectionItem, onSave: @escaping (CollectionItem) -> Void) {
        _draft = State(initialValue: item)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(appLocalized("Collection Item")) {
                    TextField(appLocalized("Custom Name"), text: binding(\.customName))
                    TextField(appLocalized("Device Name"), text: Binding(
                        get: { draft.productName ?? draft.name },
                        set: { draft.productName = $0.isEmpty ? nil : $0 }
                    ))
                    LabeledContent(appLocalized("Category"), value: categoryTitle(draft.category))
                }
                Section(appLocalized("Device Profile")) {
                    TextField(appLocalized("Model"), text: binding(\.model))
                    TextField(appLocalized("Model Identifier"), text: binding(\.productIdentifier))
                    TextField(appLocalized("Internal Model"), text: binding(\.modelVersion))
                    TextField(appLocalized("Region Variant (e.g. CH/A, LL/A)"), text: binding(\.regionVersion))
                    TextField(appLocalized("Release Year"), text: binding(\.releaseYear))
                    TextField(appLocalized("Serial Number"), text: binding(\.serialNumber))

                    let availableColors = officialColorOptions(for: draft)
                    if !availableColors.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(appLocalized("Color")).font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                if let cur = draft.color, !cur.isEmpty {
                                    Text(deviceColorLabel(cur))
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            DeviceColorSelector(colors: availableColors, selection: draft.color) { selected in
                                draft.color = selected
                            }
                            TextField(appLocalized("Custom / Special Edition Color"), text: binding(\.color))
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    } else {
                        TextField(appLocalized("Color"), text: binding(\.color))
                    }
                }
                Section(appLocalized("Hardware")) {
                    TextField(appLocalized("Display Size"), text: binding(\.screenSize))
                    TextField(appLocalized("CPU"), text: binding(\.processor))
                    TextField(appLocalized("Memory"), text: binding(\.memory))
                    TextField(appLocalized("Storage"), text: binding(\.storage))
                    TextField(appLocalized("Graphics"), text: binding(\.graphics))
                    TextField(appLocalized("Battery"), text: binding(\.battery))
                }
                Section(appLocalized("System & Maintenance")) {
                    Toggle(appLocalized("Daily Driver (In Daily Rotation · Exempt)"), isOn: $draft.isDailyDriver)
                    if BatteryMaintenanceManager.deviceHasRechargeableBattery(draft) {
                        Toggle(appLocalized("Stop Tracking Battery (Broken / Dead Unit)"), isOn: $draft.batteryTrackingIgnored)
                    }
                    TextField(appLocalized("System"), text: binding(\.system))
                    TextField(appLocalized("OS Version"), text: binding(\.osVersion))
                    TextField(appLocalized("Jailbreak Status"), text: binding(\.jailbreak))
                    TextField(appLocalized("Account Status"), text: binding(\.account))
                    TextField(appLocalized("Repairs & Upgrades"), text: binding(\.repairs))
                    TextField(appLocalized("Last Charged (yyyy.MM.dd)"), text: binding(\.lastCharged))
                }
                Section(appLocalized("Purchase & Notes")) {
                    TextField(appLocalized("Purchase Date"), text: binding(\.purchaseDate))
                    TextField(appLocalized("Purchase Source"), text: binding(\.purchaseSource))
                    TextField(appLocalized("Warranty (e.g. Covered until 2027-06)"), text: binding(\.warrantyStatus))
                    TextField(appLocalized("Price"), text: binding(\.price))
                    TextField(appLocalized("Notes"), text: binding(\.notes), axis: .vertical)
                }
            }
            .navigationTitle(appLocalized("Edit Device Details"))
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLocalized("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appLocalized("Save")) {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CollectionItem, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - 已拥有藏品分类多级视图 (Owned Catalog Category View)
// 首页的分类只整理真实藏品，最终一层进入具体那台设备的档案。
struct OwnedCatalogCategoryView: View {
    let category: String
    let items: [CollectionItem]
    @Binding var favoriteIDs: Set<String>
    let onSave: (CollectionItem) -> Void
    let onDelete: (String) -> Void
    let macBranch: String?
    let family: String?
    @State private var showingAddDevice = false

    init(category: String, items: [CollectionItem], favoriteIDs: Binding<Set<String>>, onSave: @escaping (CollectionItem) -> Void, onDelete: @escaping (String) -> Void, macBranch: String? = nil, family: String? = nil) {
        self.category = category
        self.items = items
        self._favoriteIDs = favoriteIDs
        self.onSave = onSave
        self.onDelete = onDelete
        self.macBranch = macBranch
        self.family = family
    }

    private var categoryItems: [CollectionItem] {
        items.filter { itemRootCategory($0) == category }
    }

    private var groups: [OwnedCollectionGroup] {
        if (category == "配件" || category == "Accessories"), macBranch == "Cases & Storage" {
            let caseItems = categoryItems.filter { itemFamilyName($0, root: category) == "Cases & Storage" }
            let grouped = Dictionary(grouping: caseItems) {
                caseSubfamily(name: $0.resolvedProductName, category: $0.category)
            }
            return ["MagSafe Cases", "Battery Cases", "Cases", "Other Cases & Storage"].compactMap { title in
                guard let items = grouped[title], !items.isEmpty else { return nil }
                return OwnedCollectionGroup(title: title, items: items)
            }
        }
        if (category == "配件" || category == "Accessories"), macBranch == "Power & Charging" {
            let powerItems = categoryItems.filter { itemFamilyName($0, root: category) == "Power & Charging" }
            let grouped = Dictionary(grouping: powerItems) {
                powerSubfamily(name: $0.resolvedProductName, category: $0.category)
            }
            return ["Adapters", "Cables", "MagSafe", "Other"].compactMap { title in
                guard let items = grouped[title], !items.isEmpty else { return nil }
                return OwnedCollectionGroup(title: title, items: items)
            }
        }
        if (category == "Home" || category == "家庭"), macBranch == "HomePod" {
            let hpItems = categoryItems.filter { itemFamilyName($0, root: category) == "HomePod" }
            let grouped = Dictionary(grouping: hpItems) {
                homepodSubfamily(name: $0.resolvedProductName, category: $0.category)
            }
            return ["HomePod Standard", "HomePod mini"].compactMap { title in
                guard let items = grouped[title], !items.isEmpty else { return nil }
                return OwnedCollectionGroup(title: title, items: items)
            }
        }
        if category == "Mac", macBranch == nil {
            return ["MacBook", "Mac 台式机"].compactMap { branch in
                let branchItems = categoryItems.filter { ownedMacBranch($0) == branch }
                return branchItems.isEmpty ? nil : OwnedCollectionGroup(title: branch, items: branchItems)
            }
        }
        let branchItems = categoryItems.filter { item in
            macBranch == nil || ownedMacBranch(item) == macBranch
        }
        let grouped = Dictionary(grouping: branchItems) {
            itemFamilyName($0, root: category)
        }
        return grouped.map { OwnedCollectionGroup(title: $0.key, items: $0.value) }
            .sorted { catalogFamilyOrder($0.title, root: category) < catalogFamilyOrder($1.title, root: category) }
    }

    private var selectedItems: [CollectionItem] {
        if (category == "配件" || category == "Accessories"), macBranch == "Cases & Storage", let family {
            return categoryItems.filter {
                itemFamilyName($0, root: category) == "Cases & Storage" &&
                caseSubfamily(name: $0.resolvedProductName, category: $0.category) == family
            }
        }
        if (category == "配件" || category == "Accessories"), macBranch == "Power & Charging", let family {
            return categoryItems.filter {
                itemFamilyName($0, root: category) == "Power & Charging" &&
                powerSubfamily(name: $0.resolvedProductName, category: $0.category) == family
            }
        }
        if (category == "Home" || category == "家庭"), macBranch == "HomePod", let family {
            return categoryItems.filter {
                itemFamilyName($0, root: category) == "HomePod" &&
                homepodSubfamily(name: $0.resolvedProductName, category: $0.category) == family
            }
        }
        guard let family else { return categoryItems }
        return groups.first(where: { $0.title == family })?.items ?? []
    }

    var body: some View {
        Group {
            if family != nil || category == "Vision Pro" || category == "Apple Vision Pro" || (groups.count == 1 && (groups[0].title == categoryTitle(category) || groups[0].title == category || groups[0].title == "Vision Pro" || groups[0].title == "Apple Vision Pro" || groups[0].title == "Headset")) {
                OwnedCollectionItemsView(items: selectedItems, favoriteIDs: $favoriteIDs, onSave: onSave, onDelete: onDelete)
            } else {
                ScrollView {
                    LazyVGrid(columns: appCategoryGridColumns, spacing: 14) {
                        ForEach(groups) { group in
                            NavigationLink(value: ((category == "配件" || category == "Accessories") && (group.title == "Cases & Storage" || group.title == "Power & Charging") && macBranch == nil)
                                           || ((category == "Home" || category == "家庭") && group.title == "HomePod" && macBranch == nil)
                                           || (category == "Mac" && macBranch == nil)
                                           ? HomeNavigationRoute.branch(category, group.title)
                                           : HomeNavigationRoute.family(category, macBranch, group.title)) {
                                CategoryCard(
                                    title: group.title,
                                    count: group.items.count,
                                    symbol: categorySymbol(group.title),
                                    categoryKey: group.title,
                                    fallbackArtwork: group.items.first?.artworkAssetName
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .dismissKeyboardOnScroll()
            }
        }
        .navigationTitle(appLocalized(family ?? macBranch ?? categoryTitle(category)))
        .platformInlineTitleMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddDevice = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(appLocalized("Add Device"))
            }
        }
        .sheet(isPresented: $showingAddDevice) {
            AddDeviceCatalogView(onAdd: onSave)
        }
    }
}

// MARK: - 真实藏品列表视图 (Owned Collection Items View)
struct OwnedCollectionItemsView: View {
    let items: [CollectionItem]
    @Binding var favoriteIDs: Set<String>
    let onSave: (CollectionItem) -> Void
    let onDelete: (String) -> Void
    @State private var itemToDelete: CollectionItem?
    @State private var itemToEdit: CollectionItem?
    @State private var showingDeleteAlert = false

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: HomeNavigationRoute.ownedItem(item.id)) {
                    HStack(spacing: 12) {
                        SearchCatalogArtwork(assetName: item.artworkAssetName, category: item.category)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(item.displayName).font(.headline)
                                if SpatialMuseumStore.shared.hasModel(for: item.catalogID ?? item.id, name: item.name) {
                                    Image(systemName: "cube.transparent")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                if favoriteIDs.contains(item.favoriteKey) {
                                    Image(systemName: "heart.fill")
                                        .font(.caption)
                                        .foregroundStyle(.pink)
                                }
                            }
                            Text([item.model, item.releaseYear]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.automatic)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        itemToDelete = item
                        showingDeleteAlert = true
                    } label: {
                        Label(appLocalized("Delete"), systemImage: "trash")
                    }

                    Button {
                        itemToEdit = item
                    } label: {
                        Label(appLocalized("Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        toggleMembership(item.favoriteKey, in: $favoriteIDs)
                    } label: {
                        Label(
                            appLocalized(favoriteIDs.contains(item.favoriteKey) ? "Unfavorite" : "Favorite"),
                            systemImage: favoriteIDs.contains(item.favoriteKey) ? "heart.slash" : "heart.fill"
                        )
                    }
                    .tint(favoriteIDs.contains(item.favoriteKey) ? .gray : .pink)
                }
                .contextMenu {
                    Button {
                        itemToEdit = item
                    } label: {
                        Label(appLocalized("Edit Device"), systemImage: "pencil")
                    }

                    Button {
                        toggleMembership(item.favoriteKey, in: $favoriteIDs)
                    } label: {
                        Label(
                            appLocalized(favoriteIDs.contains(item.favoriteKey) ? "Remove from Favorites" : "Add to Favorites"),
                            systemImage: favoriteIDs.contains(item.favoriteKey) ? "heart.slash" : "heart"
                        )
                    }
                    Divider()
                    Button {
                        withAnimation {
                            BatteryMaintenanceManager.toggleDailyDriver(for: item, onUpdate: onSave)
                        }
                    } label: {
                        Label(
                            item.isDailyDriver ? appLocalized("Remove from Daily Drivers") : appLocalized("Set as Daily Driver"),
                            systemImage: item.isDailyDriver ? "sparkles.slash" : "sparkles"
                        )
                    }

                    if BatteryMaintenanceManager.deviceHasRechargeableBattery(item) {
                        if !item.isDailyDriver && !item.batteryTrackingIgnored {
                            Button {
                                withAnimation {
                                    BatteryMaintenanceManager.logCharge(for: item, onUpdate: onSave)
                                }
                            } label: {
                                Label(appLocalized("Charged Today"), systemImage: "bolt.fill")
                            }
                        }

                        Button {
                            withAnimation {
                                BatteryMaintenanceManager.toggleBatteryTracking(for: item, onUpdate: onSave)
                            }
                        } label: {
                            Label(
                                item.batteryTrackingIgnored ? appLocalized("Resume Battery Tracking") : appLocalized("Stop Tracking Battery"),
                                systemImage: item.batteryTrackingIgnored ? "bolt.circle" : "bolt.slash"
                            )
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        itemToDelete = item
                        showingDeleteAlert = true
                    } label: {
                        Label(appLocalized("Delete Device"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .sheet(item: $itemToEdit) { item in
            EditCollectionItemView(item: item, onSave: onSave)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No Devices Yet", systemImage: "shippingbox", description: Text("Mark a device as Owned in the Apple Catalog to add it to your collection."))
            }
        }
        .alert(
            appLocalized("Delete Device"),
            isPresented: $showingDeleteAlert,
            presenting: itemToDelete
        ) { item in
            Button(appLocalized("Cancel"), role: .cancel) { itemToDelete = nil }
            Button(appLocalized("Delete"), role: .destructive) {
                onDelete(item.id)
                itemToDelete = nil
            }
        } message: { item in
            Text(String(format: appLocalized("Are you sure you want to remove \"%@\" from your collection? This action cannot be undone."), item.displayName))
        }
    }
}

// MARK: - 常用设备首页快捷入口卡片 (Daily Drivers Quick Access Card)
struct InUseQuickAccessCard: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.blue)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.blue.opacity(0.12), in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(appLocalized("Daily Drivers"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - 补电日记首页快捷入口卡片 (Battery Maintenance Quick Access Card)
struct BatteryLogQuickAccessCard: View {
    let totalCount: Int
    let overdueCount: Int
    let dueSoonCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill((overdueCount > 0 ? Color.red : Color.green).opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: overdueCount > 0 ? "battery.25" : "battery.100.bolt")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(overdueCount > 0 ? Color.red : Color.green)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    if overdueCount > 0 {
                        Text("\(overdueCount) Due")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    } else {
                        Text("\(totalCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(appLocalized("Battery Log"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke((overdueCount > 0 ? Color.red : Color.primary).opacity(0.08), lineWidth: 1)
        )
    }
}
