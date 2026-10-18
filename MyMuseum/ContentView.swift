//
//  ContentView.swift
//  Pomme
//
//  主视图容器 (Root Container View)
//  管理全 App 藏品核心数据流、Tab 导航栏路由以及与 Apple Watch 数据快照同步。
//

import SwiftUI

// MARK: - 主界面视图 (Root ContentView)
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var collectionItems = loadCollection()
    @AppStorage("ownedDeviceIDs") private var ownedIDsData = Data()
    @AppStorage("wantedDeviceIDs") private var wantedIDsData = Data()
    @AppStorage("favoriteDeviceIDs") private var favoriteIDsData = Data()
    @AppStorage("appAppearanceMode") private var appearanceMode: String = AppAppearanceMode.auto.rawValue
    @State private var isShowingLaunchSplash: Bool = true
    @State private var selectedTab: Int = 0

    private var isMac: Bool {
#if os(macOS)
        return true
#elseif targetEnvironment(macCatalyst)
        return true
#else
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        }
        return false
#endif
    }

    var body: some View {
        Group {
            if isMac {
                MacCuratorWorkbenchView(
                    collectionItems: $collectionItems,
                    ownedIDsData: $ownedIDsData,
                    wantedIDsData: $wantedIDsData,
                    favoriteIDsData: $favoriteIDsData,
                    onUpdate: saveCollectionItem,
                    onBatchUpdate: saveCollectionItems,
                    onDelete: deleteCollectionItem
                )
            } else {
                ZStack {
                    TabView(selection: $selectedTab) {
                        CollectionView(items: collectionItems, onUpdate: saveCollectionItem, onBatchUpdate: saveCollectionItems, onDelete: deleteCollectionItem)
                            .tabItem { Label("My Collection", systemImage: "square.grid.2x2.fill") }
                            .tag(0)
                        CatalogView(collectionItems: collectionItems, onAddOwned: saveCollectionItem, onRemoveOwned: removeOwnedCatalogDevice)
                            .tabItem { Label("Encyclopedia", systemImage: "books.vertical.fill") }
                            .tag(1)
                        WishlistView(onAddOwned: saveCollectionItem, onRemoveOwned: removeOwnedCatalogDevice)
                            .tabItem { Label("Wishlist", systemImage: "dollarsign.circle.fill") }
                            .tag(2)
                        RumorView()
                            .tabItem { Label("Rumors", systemImage: "newspaper.fill") }
                            .tag(3)
                        NavigationStack {
                            SpatialMuseumView(isActive: selectedTab == 4)
                        }
                        .tabItem {
                            #if os(visionOS)
                            Label("Spatial Gallery", systemImage: "visionpro")
                            #elseif os(iOS)
                            Label("AR Museum", systemImage: "arkit")
                            #else
                            Label("3D Museum", systemImage: "cube.transparent")
                            #endif
                        }
                        .tag(4)
                    }

                    if isShowingLaunchSplash {
                        LaunchSplashScreenView(isPresented: $isShowingLaunchSplash)
                            .transition(.opacity)
                            .zIndex(999)
                    }
                }
            }
        }
        .preferredColorScheme(AppAppearanceMode(rawValue: appearanceMode)?.colorScheme)
        .onAppear {
            checkAndLoadInitialSampleData()
            syncOwnedCatalogIDs()
            publishWatchSnapshot(collectionItems)
            if UserDefaults.standard.object(forKey: "batteryQuarterlyRemindersEnabled") == nil ||
               UserDefaults.standard.bool(forKey: "batteryQuarterlyRemindersEnabled") {
                BatteryMaintenanceManager.scheduleDailyBatteryReminders(for: collectionItems)
            }
            CloudVaultSyncManager.shared.triggerForegroundSync()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                CloudVaultSyncManager.shared.triggerForegroundSync()
            }
        }
        .onChange(of: wantedIDsData) { _ in
            publishWatchSnapshot(collectionItems)
            CloudVaultSyncManager.shared.scheduleAutoSync()
        }
        .onChange(of: favoriteIDsData) { _ in
            CloudVaultSyncManager.shared.scheduleAutoSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearSampleDevices)) { _ in
            clearSampleDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadSampleDevices)) { _ in
            reloadSampleDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBatteryMaintenance)) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncDidComplete)) { notification in
            if let newItems = notification.userInfo?["items"] as? [CollectionItem] {
                self.collectionItems = newItems
            } else {
                self.collectionItems = loadCollection()
            }
            self.syncOwnedCatalogIDs()
            self.wantedIDsData = UserDefaults.standard.data(forKey: "wantedDeviceIDs") ?? Data()
            self.favoriteIDsData = UserDefaults.standard.data(forKey: "favoriteDeviceIDs") ?? Data()
            RootCategoryOrderStore.shared.reload()
            LaunchDropManager.shared.loadPreferences()
            NewsBookmarkManager.shared.loadAndPrune()
            if UserDefaults.standard.object(forKey: "batteryQuarterlyRemindersEnabled") == nil ||
               UserDefaults.standard.bool(forKey: "batteryQuarterlyRemindersEnabled") {
                BatteryMaintenanceManager.scheduleDailyBatteryReminders(for: collectionItems)
            }
        }
    }

    /// 同步藏品已有状态到百科图鉴已拥有集合
    private func syncOwnedCatalogIDs() {
        var ownedIDs = decodeIDs(from: ownedIDsData)
        ownedIDs.formUnion(collectionItems.map { $0.catalogID ?? $0.id })
        // 旧版导入时 AirPods Pro 一代没写 catalogID，沿用名称关联，不改动原藏品与收藏标记
        if collectionItems.contains(where: {
            $0.name.localizedCaseInsensitiveContains("airpods pro 1") ||
                $0.name.localizedCaseInsensitiveContains("airpods pro 一代")
        }) {
            ownedIDs.insert("Airpods-4")
        }
        ownedIDsData = encodeIDs(ownedIDs)

        // 迁移：如果收藏夹中有旧版按 catalogID 存储的喜欢标记，将其转换为具体物理藏品的唯一 ID（多台时取第一台），
        // 彻底解决多台相同设备（如2台HomePod）同时被标记喜欢、重复轮播的问题
        var favoriteIDs = decodeIDs(from: favoriteIDsData)
        var favoriteMigrated = false
        for item in collectionItems {
            if let catID = item.catalogID, favoriteIDs.contains(catID) {
                let duplicates = collectionItems.filter { $0.catalogID == catID }
                if duplicates.count > 1, let first = duplicates.first {
                    favoriteIDs.remove(catID)
                    favoriteIDs.insert(first.id)
                    favoriteMigrated = true
                } else if duplicates.count == 1 {
                    favoriteIDs.insert(item.id)
                    favoriteMigrated = true
                }
            }
        }
        if favoriteMigrated {
            favoriteIDsData = encodeIDs(favoriteIDs)
        }
    }

    /// 保存或更新单个藏品并持久化
    private func saveCollectionItem(_ updatedItem: CollectionItem) {
        var itemWithTimestamp = updatedItem
        itemWithTimestamp.updatedAt = Date()
        if let index = collectionItems.firstIndex(where: { $0.id == itemWithTimestamp.id }) {
            collectionItems[index] = itemWithTimestamp
        } else {
            collectionItems.insert(itemWithTimestamp, at: 0)
        }
        saveCollection(collectionItems)
        var ownedIDs = decodeIDs(from: ownedIDsData)
        ownedIDs.insert(itemWithTimestamp.catalogID ?? itemWithTimestamp.id)
        ownedIDsData = encodeIDs(ownedIDs)
        if UserDefaults.standard.object(forKey: "batteryQuarterlyRemindersEnabled") == nil ||
           UserDefaults.standard.bool(forKey: "batteryQuarterlyRemindersEnabled") {
            BatteryMaintenanceManager.scheduleDailyBatteryReminders(for: collectionItems)
        }
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    /// 批量保存或更新藏品，只进行一次持久化与一次手表快照传输（P0-4 / P0-5 优化）
    private func saveCollectionItems(_ newItems: [CollectionItem]) {
        guard !newItems.isEmpty else { return }
        
        // 如果当前仅有演示示例数据，导入真实数据时自动清空示例设备
        var current = collectionItems
        let allSamples = current.allSatisfy { SampleDataManager.isSampleItem($0) }
        if allSamples && !current.isEmpty {
            UserDefaults.standard.set(true, forKey: SampleDataManager.sampleClearedKey)
            current.removeAll()
        }
        
        var ownedIDs = decodeIDs(from: ownedIDsData)
        if allSamples {
            ownedIDs.removeAll()
        }
        
        let now = Date()
        for rawItem in newItems {
            var item = rawItem
            item.updatedAt = now
            // P0-5 去重逻辑：
            if let index = current.firstIndex(where: { $0.id == item.id }) {
                current[index] = item
            } else if let serial = item.serialNumber, !serial.isEmpty,
                      let index = current.firstIndex(where: { $0.serialNumber == serial && $0.name == item.name }) {
                current[index] = item
            } else if (item.model == "A1296" || item.name.contains("Magic Mouse")),
                      (item.price == "18" || item.notes?.contains("坏") == true || item.notes?.contains("维修") == true),
                      let index = current.firstIndex(where: {
                          ($0.model == "A1296" || $0.name.contains("Magic Mouse")) &&
                          ($0.price == "18" || $0.notes?.contains("坏") == true || $0.notes?.contains("维修") == true || $0.serialNumber == nil)
                      }) {
                current[index] = item
            } else {
                current.insert(item, at: 0)
            }
            ownedIDs.insert(item.catalogID ?? item.id)
        }
        
        // 单次更新 @State，杜绝主线程大数组循环刷屏卡死
        collectionItems = current
        saveCollection(collectionItems)
        ownedIDsData = encodeIDs(ownedIDs)
        if UserDefaults.standard.object(forKey: "batteryQuarterlyRemindersEnabled") == nil ||
           UserDefaults.standard.bool(forKey: "batteryQuarterlyRemindersEnabled") {
            BatteryMaintenanceManager.scheduleDailyBatteryReminders(for: collectionItems)
        }
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    /// 删除指定 ID 的藏品，并清理已拥有与喜欢关联状态
    private func deleteCollectionItem(id: String) {
        guard let index = collectionItems.firstIndex(where: { $0.id == id }) else { return }
        let removed = collectionItems.remove(at: index)
        saveCollection(collectionItems)
        CloudVaultSyncManager.shared.recordDeletion(itemId: id)

        let catalogKey = removed.catalogID ?? removed.id
        let hasOtherItemWithCatalogKey = collectionItems.contains { ($0.catalogID ?? $0.id) == catalogKey }
        if !hasOtherItemWithCatalogKey {
            var ownedIDs = decodeIDs(from: ownedIDsData)
            ownedIDs.remove(catalogKey)
            if let catID = removed.catalogID { ownedIDs.remove(catID) }
            ownedIDs.remove(removed.id)
            ownedIDsData = encodeIDs(ownedIDs)
        }

        let favKey = removed.favoriteKey
        let hasOtherItemWithFavKey = collectionItems.contains { $0.favoriteKey == favKey }
        if !hasOtherItemWithFavKey {
            var favoriteIDs = decodeIDs(from: favoriteIDsData)
            favoriteIDs.remove(favKey)
            favoriteIDsData = encodeIDs(favoriteIDs)
        }

        publishWatchSnapshot(collectionItems)
    }

    /// 从百科详情中移除已拥有设备（同时移除相关联藏品）
    private func removeOwnedCatalogDevice(catalogID: String) {
        let removedItems = collectionItems.filter { ($0.catalogID ?? $0.id) == catalogID || $0.id == catalogID }
        for item in removedItems {
            CloudVaultSyncManager.shared.recordDeletion(itemId: item.id)
        }
        collectionItems.removeAll { ($0.catalogID ?? $0.id) == catalogID || $0.id == catalogID }
        saveCollection(collectionItems)
        var ownedIDs = decodeIDs(from: ownedIDsData)
        ownedIDs.remove(catalogID)
        ownedIDsData = encodeIDs(ownedIDs)

        var favIDs = decodeIDs(from: favoriteIDsData)
        favIDs.remove(catalogID)
        favoriteIDsData = encodeIDs(favIDs)

        publishWatchSnapshot(collectionItems)
    }

    /// 首次无数据时自动注入全套功能演示设备（若用户未主动清空过）
    private func checkAndLoadInitialSampleData() {
        if collectionItems.isEmpty && !UserDefaults.standard.bool(forKey: SampleDataManager.sampleClearedKey) {
            reloadSampleDevices()
        }
    }

    /// 极速清空演示示例数据
    private func clearSampleDevices() {
        var ownedIDs = decodeIDs(from: ownedIDsData)
        var favoriteIDs = decodeIDs(from: favoriteIDsData)
        var wantedIDs = decodeIDs(from: wantedIDsData)
        collectionItems = SampleDataManager.removeSampleData(
            currentItems: collectionItems,
            ownedIDs: &ownedIDs,
            favoriteIDs: &favoriteIDs,
            wantedIDs: &wantedIDs
        )
        saveCollection(collectionItems)
        ownedIDsData = encodeIDs(ownedIDs)
        favoriteIDsData = encodeIDs(favoriteIDs)
        wantedIDsData = encodeIDs(wantedIDs)
        publishWatchSnapshot(collectionItems)
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    /// 载入功能演示示例数据
    private func reloadSampleDevices() {
        var ownedIDs = decodeIDs(from: ownedIDsData)
        var favoriteIDs = decodeIDs(from: favoriteIDsData)
        var wantedIDs = decodeIDs(from: wantedIDsData)
        collectionItems = SampleDataManager.loadSampleData(
            currentItems: collectionItems,
            ownedIDs: &ownedIDs,
            favoriteIDs: &favoriteIDs,
            wantedIDs: &wantedIDs
        )
        saveCollection(collectionItems)
        ownedIDsData = encodeIDs(ownedIDs)
        favoriteIDsData = encodeIDs(favoriteIDs)
        wantedIDsData = encodeIDs(wantedIDs)
        publishWatchSnapshot(collectionItems)
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }
}

extension Notification.Name {
    static let clearSampleDevices = Notification.Name("clearSampleDevices")
    static let loadSampleDevices = Notification.Name("loadSampleDevices")
}

#Preview {
    ContentView()
}
