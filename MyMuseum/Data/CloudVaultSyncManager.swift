//
//  CloudVaultSyncManager.swift
//  Pomme
//
//  基于 iCloud Drive / 安全作用域文件夹的多端自动同步引擎 (Cloud Vault Sync Manager)
//  方案2：无需 $99/年 开发者证书与 CloudKit 容器，采用用户自选 iCloud Drive 文件夹
//  通过 Security-Scoped Bookmarks 实现持久化读写授权，支持增量双向合并、墓碑删除追踪与 Apple Watch 自动协同。
//

import Foundation
import SwiftUI
import Combine

#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 同步金库数据载荷 (Sync Vault Payload)
struct PommeSyncVault: Codable {
    var schemaVersion: Int = 1
    var vaultId: String
    var lastModified: Date
    var sourceDeviceId: String
    var sourceDeviceName: String
    var collectionItems: [CollectionItem]
    var wantedDeviceIDs: [String]
    var wantedUpdatedAt: Date?
    var favoriteDeviceIDs: [String]
    var favoriteUpdatedAt: Date?
    var inUseDeviceIDs: [String]?
    var interestedDropIDs: [String]?
    var dismissedDropIDs: [String]?
    var readLaterStories: [ReadLaterStoryItem]?
    var savedStories: [SavedStoryItem]?
    var tombstones: [String: Date] // itemId -> deletionTimestamp
    var rootCategoryOrders: RootCategoryOrdersBackup?
    var museumTitle: String?
}

struct RootCategoryOrdersBackup: Codable {
    var encyclopedia: [String]?
    var collection: [String]?
    var battery: [String]?
    var updatedAt: Date?
}

// MARK: - 同步结果与状态
enum CloudSyncState: Equatable {
    case notConfigured
    case idle
    case syncing
    case success(Date, String)
    case failure(String)

    var description: String {
        switch self {
        case .notConfigured:
            return appLocalized("Not Configured")
        case .idle:
            return appLocalized("Ready")
        case .syncing:
            return appLocalized("Syncing...")
        case .success(_, let message):
            return message
        case .failure(let error):
            return String(format: appLocalized("Sync Failed: %@"), error)
        }
    }
}

extension Notification.Name {
    static let cloudSyncDidComplete = Notification.Name("cloudSyncDidComplete")
}

// MARK: - 多端同步管理器 (Cloud Vault Sync Manager)
@MainActor
final class CloudVaultSyncManager: ObservableObject {
    static let shared = CloudVaultSyncManager()

    // MARK: - 公开状态
    @Published private(set) var syncState: CloudSyncState = .notConfigured
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var currentFolderName: String = ""
    @Published private(set) var isConfigured: Bool = false
    @Published var autoSyncEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: autoSyncKey)
        }
    }

    // MARK: - 存储键
    private let bookmarkKey = "PommeCloudVaultBookmarkData_v1"
    private let folderNameKey = "PommeCloudVaultFolderName_v1"
    private let lastSyncKey = "PommeCloudVaultLastSyncDate_v1"
    private let autoSyncKey = "PommeCloudVaultAutoSyncEnabled_v1"
    private let tombstonesKey = "PommeCloudVaultTombstones_v1"
    private let removedWantedKey = "PommeCloudVaultRemovedWantedIDs_v1"
    private let removedFavKey = "PommeCloudVaultRemovedFavoriteIDs_v1"
    private let deviceIdKey = "PommeCloudVaultDeviceId_v1"
    private let vaultFilename = "PommeSync_Vault.json"

    private var autoSyncTask: Task<Void, Never>? = nil

    // MARK: - 设备信息
    var deviceId: String {
        if let saved = UserDefaults.standard.string(forKey: deviceIdKey) {
            return saved
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }

    var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif os(visionOS)
        return "Apple Vision Pro"
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Apple Device"
        #endif
    }

    // MARK: - 初始化
    private init() {
        self.autoSyncEnabled = UserDefaults.standard.object(forKey: autoSyncKey) == nil ? true : UserDefaults.standard.bool(forKey: autoSyncKey)
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Double {
            self.lastSyncDate = Date(timeIntervalSince1970: timestamp)
        }
        self.currentFolderName = UserDefaults.standard.string(forKey: folderNameKey) ?? ""
        checkConfigurationStatus()
    }

    // MARK: - 状态检查
    func checkConfigurationStatus() {
        guard let _ = UserDefaults.standard.data(forKey: bookmarkKey) else {
            self.isConfigured = false
            self.syncState = .notConfigured
            return
        }
        self.isConfigured = true
        if case .notConfigured = syncState {
            if let lastDate = lastSyncDate {
                let msg = isChineseLanguage ? "已就绪 · 上次同步于 \(formattedDate(lastDate))" : "Ready · Last synced \(formattedDate(lastDate))"
                self.syncState = .success(lastDate, msg)
            } else {
                self.syncState = .idle
            }
        }
    }

    // MARK: - 文件夹安全作用域授权 (Security-Scoped Bookmark)
    /// 当用户从系统文档选择器选取 iCloud Drive 文件夹时调用
    func setSyncFolder(url: URL) throws {
        // 请求临时安全作用域访问
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif

        let bookmarkData = try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let folderName = url.lastPathComponent.isEmpty ? "iCloud Drive" : url.lastPathComponent
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        UserDefaults.standard.set(folderName, forKey: folderNameKey)

        self.currentFolderName = folderName
        self.isConfigured = true
        self.syncState = .idle

        // 立即执行初次握手同步
        Task {
            _ = await syncNow(trigger: "Initial Link")
        }
    }

    /// 断开与当前同步文件夹的关联
    func disconnectSyncFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderNameKey)
        self.currentFolderName = ""
        self.isConfigured = false
        self.syncState = .notConfigured
    }

    /// 在安全作用域下执行文件夹内部操作闭包
    private func withFolderAccess<T>(_ block: (URL) throws -> T) throws -> T {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw SyncError.notConfigured
        }

        var isStale = false
        #if os(macOS)
        let folderURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let folderURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif

        if isStale {
            #if os(macOS)
            let creationOpts: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let creationOpts: URL.BookmarkCreationOptions = []
            #endif
            if let refreshedData = try? folderURL.bookmarkData(options: creationOpts, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshedData, forKey: bookmarkKey)
            }
        }

        let didStart = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        return try block(folderURL)
    }

    // MARK: - 墓碑删除记录追踪 (Tombstones Management)
    /// 当用户在本地删除设备时，记入删除墓碑，防止后续从云端误复活
    func recordDeletion(itemId: String) {
        var tombstones = loadTombstones()
        tombstones[itemId] = Date()
        saveTombstones(tombstones)
        scheduleAutoSync(delay: 1.0)
    }

    private func loadTombstones() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: tombstonesKey),
              let dict = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func saveTombstones(_ dict: [String: Date]) {
        // 清理超过 30 天的历史墓碑
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let cleaned = dict.filter { $0.value > cutoff }
        if let data = try? JSONEncoder().encode(cleaned) {
            UserDefaults.standard.set(data, forKey: tombstonesKey)
        }
    }

    // MARK: - 心愿单与喜欢移除记录追踪 (Prevent Deleted IDs from Resurrecting)
    func loadRemovedWantedIDs() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: removedWantedKey) ?? []
        return Set(arr)
    }

    func saveRemovedWantedIDs(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: removedWantedKey)
    }

    func recordWantedRemoval(ids: Set<String>) {
        var removed = loadRemovedWantedIDs()
        removed.formUnion(ids)
        saveRemovedWantedIDs(removed)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "wantedUpdatedAt")
        scheduleAutoSync(delay: 1.0)
    }

    func recordWantedAddition(id: String) {
        var removed = loadRemovedWantedIDs()
        removed.remove(id)
        saveRemovedWantedIDs(removed)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "wantedUpdatedAt")
        scheduleAutoSync(delay: 1.0)
    }

    func loadRemovedFavoriteIDs() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: removedFavKey) ?? []
        return Set(arr)
    }

    func saveRemovedFavoriteIDs(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: removedFavKey)
    }

    func recordFavoriteRemoval(ids: Set<String>) {
        var removed = loadRemovedFavoriteIDs()
        removed.formUnion(ids)
        saveRemovedFavoriteIDs(removed)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "favoriteUpdatedAt")
        scheduleAutoSync(delay: 1.0)
    }

    func recordFavoriteAddition(id: String) {
        var removed = loadRemovedFavoriteIDs()
        removed.remove(id)
        saveRemovedFavoriteIDs(removed)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "favoriteUpdatedAt")
        scheduleAutoSync(delay: 1.0)
    }

    // MARK: - 核心双向增量同步引擎 (Bidirectional 3-Way Merge Engine)
    /// 触发同步（支持手动或自动后台）
    @discardableResult
    func syncNow(trigger: String = "Manual") async -> Bool {
        guard isConfigured else { return false }
        guard !isSyncing else { return false }

        self.isSyncing = true
        self.syncState = .syncing

        do {
            let (mergedItems, syncDate, summary) = try performVaultMerge()

            // 刷新主线程状态
            self.lastSyncDate = syncDate
            UserDefaults.standard.set(syncDate.timeIntervalSince1970, forKey: self.lastSyncKey)
            self.isSyncing = false
            let successMsg = isChineseLanguage ? "同步成功 · \(summary)" : "Synced · \(summary)"
            self.syncState = .success(syncDate, successMsg)

            // 通知全 App 视图与 Apple Watch
            NotificationCenter.default.post(
                name: .cloudSyncDidComplete,
                object: nil,
                userInfo: ["items": mergedItems]
            )

            return true
        } catch {
            self.isSyncing = false
            self.syncState = .failure(error.localizedDescription)
            return false
        }
    }

    /// 底层金库读取、三向合并与写回执行逻辑
    private func performVaultMerge() throws -> ([CollectionItem], Date, String) {
        return try withFolderAccess { folderURL in
            var targetVaultURL = folderURL.appendingPathComponent(vaultFilename)
            let fileManager = FileManager.default

            let localItems = loadCollection()
            let localWantedData = UserDefaults.standard.data(forKey: "wantedDeviceIDs") ?? Data()
            let localWantedIDs = decodeIDs(from: localWantedData)
            let localFavData = UserDefaults.standard.data(forKey: "favoriteDeviceIDs") ?? Data()
            let localFavIDs = decodeIDs(from: localFavData)
            let localDropIDs = Array(LaunchDropManager.shared.interestedDropIDs)
            let localDismissedDropIDs = Array(LaunchDropManager.shared.dismissedDropIDs)
            let localReadLater = NewsBookmarkManager.shared.readLaterItems
            let localSaved = NewsBookmarkManager.shared.savedItems
            let localTombstones = self.loadTombstones()
            let localTitle = UserDefaults.standard.string(forKey: "museumTitle") ?? ""

            // 如果默认 PommeSync_Vault.json 不存在，智能扫描当前文件夹下的 JSON 或 CSV 文件
            if !fileManager.fileExists(atPath: targetVaultURL.path) {
                if let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                    if let found = contents.first(where: { $0.lastPathComponent.localizedCaseInsensitiveContains("Vault") && $0.pathExtension == "json" }) {
                        targetVaultURL = found
                    } else if let foundJSON = contents.first(where: { $0.pathExtension.lowercased() == "json" && !$0.lastPathComponent.hasPrefix(".") }) {
                        targetVaultURL = foundJSON
                    } else if let foundCSV = contents.first(where: { $0.pathExtension.lowercased() == "csv" && !$0.lastPathComponent.hasPrefix(".") }) {
                        targetVaultURL = foundCSV
                    }
                }
            }

            // 如果云端金库文件尚不存在：直接上传本地数据为初代金库
            if !fileManager.fileExists(atPath: targetVaultURL.path) {
                let initialVault = PommeSyncVault(
                    schemaVersion: 1,
                    vaultId: UUID().uuidString,
                    lastModified: Date(),
                    sourceDeviceId: self.deviceId,
                    sourceDeviceName: self.deviceName,
                    collectionItems: localItems,
                    wantedDeviceIDs: Array(localWantedIDs),
                    wantedUpdatedAt: Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "wantedUpdatedAt")),
                    favoriteDeviceIDs: Array(localFavIDs),
                    favoriteUpdatedAt: Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "favoriteUpdatedAt")),
                    inUseDeviceIDs: localItems.filter { $0.isDailyDriver }.map(\.id),
                    interestedDropIDs: localDropIDs,
                    dismissedDropIDs: localDismissedDropIDs,
                    readLaterStories: localReadLater,
                    savedStories: localSaved,
                    tombstones: localTombstones,
                    rootCategoryOrders: RootCategoryOrdersBackup(
                        encyclopedia: RootCategoryOrderStore.shared.encyclopediaOrder,
                        collection: RootCategoryOrderStore.shared.collectionOrder,
                        battery: RootCategoryOrderStore.shared.batteryOrder,
                        updatedAt: RootCategoryOrderStore.shared.orderUpdatedAt ?? Date()
                    ),
                    museumTitle: localTitle
                )

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let vaultData = try encoder.encode(initialVault)
                try vaultData.write(to: targetVaultURL, options: .atomic)

                return (localItems, Date(), String(format: appLocalized("Vault created · %d items uploaded"), localItems.count))
            }

            // 读取并解析云端金库
            let remoteData = try Data(contentsOf: targetVaultURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteVault: PommeSyncVault
            do {
                remoteVault = try decoder.decode(PommeSyncVault.self, from: remoteData)
            } catch {
                if let rawItems = try? decoder.decode([CollectionItem].self, from: remoteData), !rawItems.isEmpty {
                    remoteVault = PommeSyncVault(
                        schemaVersion: 1,
                        vaultId: UUID().uuidString,
                        lastModified: Date(),
                        sourceDeviceId: "ImportedFile",
                        sourceDeviceName: targetVaultURL.lastPathComponent,
                        collectionItems: rawItems,
                        wantedDeviceIDs: [],
                        wantedUpdatedAt: nil,
                        favoriteDeviceIDs: [],
                        favoriteUpdatedAt: nil,
                        inUseDeviceIDs: rawItems.filter { $0.isDailyDriver }.map(\.id),
                        interestedDropIDs: nil,
                        dismissedDropIDs: nil,
                        readLaterStories: nil,
                        savedStories: nil,
                        tombstones: [:],
                        rootCategoryOrders: nil,
                        museumTitle: nil
                    )
                } else if let importedFromCSV = try? MuseumCSV.importing(remoteData, filename: targetVaultURL.lastPathComponent), !importedFromCSV.items.isEmpty {
                    remoteVault = PommeSyncVault(
                        schemaVersion: 1,
                        vaultId: UUID().uuidString,
                        lastModified: Date(),
                        sourceDeviceId: "ImportedCSV",
                        sourceDeviceName: targetVaultURL.lastPathComponent,
                        collectionItems: importedFromCSV.items,
                        wantedDeviceIDs: [],
                        wantedUpdatedAt: nil,
                        favoriteDeviceIDs: [],
                        favoriteUpdatedAt: nil,
                        inUseDeviceIDs: importedFromCSV.items.filter { $0.isDailyDriver }.map(\.id),
                        interestedDropIDs: nil,
                        dismissedDropIDs: nil,
                        readLaterStories: nil,
                        savedStories: nil,
                        tombstones: [:],
                        rootCategoryOrders: nil,
                        museumTitle: nil
                    )
                } else {
                    throw SyncError.corruptedRemoteVault(error.localizedDescription)
                }
            }

            // 1. 合并墓碑 (Tombstones)
            var mergedTombstones = localTombstones
            for (id, date) in remoteVault.tombstones {
                if let existing = mergedTombstones[id] {
                    mergedTombstones[id] = max(existing, date)
                } else {
                    mergedTombstones[id] = date
                }
            }
            // 剔除超过 30 天的墓碑
            let cutoff = Date().addingTimeInterval(-30 * 86400)
            mergedTombstones = mergedTombstones.filter { $0.value > cutoff }

            // 2. 藏品增量三向合并 (Item Matching & Conflict Resolution)
            var mergedItemsMap: [String: CollectionItem] = [:]

            // 辅助匹配函数：按 ID 优先匹配，降级按唯一硬件序列号匹配，再降级按配件型号匹配
            func findMatch(for item: CollectionItem, in list: [CollectionItem]) -> CollectionItem? {
                if let byId = list.first(where: { $0.id == item.id }) {
                    return byId
                }
                let isAirTag = item.category == "AirTag" || item.name.contains("AirTag")
                if let sn = item.serialNumber, isUniqueHardwareSerial(sn), !isAirTag,
                   let bySerial = list.first(where: {
                       $0.serialNumber == sn && $0.category != "AirTag" && !$0.name.contains("AirTag")
                   }) {
                    return bySerial
                }
                // 对无序列号的配件与转接头（如 Lightning to 3.5mm A1749、USB-C to 3.5mm A2049 等），按统一 key 跨设备匹配
                let rootCat = itemRootCategory(item)
                let isAccessoryOrAdapter = rootCat == "配件" || rootCat == "Accessories" || item.category == "Adapters" || item.category == "Adapter" || item.category == "配件"
                if isAccessoryOrAdapter && !isAirTag && (item.serialNumber == nil || !isUniqueHardwareSerial(item.serialNumber)) {
                    let key = (item.catalogID ?? item.model ?? item.name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !key.isEmpty,
                       let byKey = list.first(where: {
                           let otherRoot = itemRootCategory($0)
                           let isOtherAcc = otherRoot == "配件" || otherRoot == "Accessories" || $0.category == "Adapters" || $0.category == "Adapter" || $0.category == "配件"
                           let otherKey = ($0.catalogID ?? $0.model ?? $0.name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                           return isOtherAcc && otherKey == key && ($0.serialNumber == nil || !isUniqueHardwareSerial($0.serialNumber))
                       }) {
                        return byKey
                    }
                }

                // Magic Mouse 1代无序列号或跨端名称差异（Magic Mouse vs Magic Mouse (1st generation)）智能跨端匹配
                let isMM1 = item.model == "A1296" || item.catalogID == "鼠标-2" || item.catalogID == "Magic Mouse (1st generation)" || item.name.contains("Magic Mouse")
                if isMM1 {
                    let isGood = item.serialNumber == "CC228117CGDFFGAC" || item.price == "63.4" || item.price == "63" || item.notes?.contains("充电") == true || item.notes?.contains("升级") == true
                    if let byMM1 = list.first(where: { other in
                        let otherMM1 = other.model == "A1296" || other.catalogID == "鼠标-2" || other.catalogID == "Magic Mouse (1st generation)" || other.name.contains("Magic Mouse")
                        guard otherMM1 else { return false }
                        let otherGood = other.serialNumber == "CC228117CGDFFGAC" || other.price == "63.4" || other.price == "63" || other.notes?.contains("充电") == true || other.notes?.contains("升级") == true
                        return isGood ? otherGood : !otherGood
                    }) {
                        return byMM1
                    }
                }

                // iPhone 3G：仅有 1 台坏机（无序列号，A1241）智能匹配
                let is3G = item.model == "A1241" || item.catalogID == "iPhone1,2" || item.name.lowercased() == "iphone 3g"
                if is3G {
                    if let by3G = list.first(where: { other in
                        other.model == "A1241" || other.catalogID == "iPhone1,2" || other.name.lowercased() == "iphone 3g"
                    }) {
                        return by3G
                    }
                }

                // iPhone 3GS：共 2 台（1台好机 SN: 88150PV0EDG + 1台坏机 无SN）智能跨端匹配
                let is3GS = item.model == "A1303" || item.model == "A1325" || item.catalogID == "iPhone2,1" || item.catalogID == "iPhone-2" || item.catalogID == "iPhone-3" || item.name.lowercased() == "iphone 3gs"
                if is3GS {
                    let isGood = item.serialNumber == "88150PV0EDG"
                    if let by3GS = list.first(where: { other in
                        let other3GS = other.model == "A1303" || other.model == "A1325" || other.catalogID == "iPhone2,1" || other.catalogID == "iPhone-2" || other.catalogID == "iPhone-3" || other.name.lowercased() == "iphone 3gs"
                        guard other3GS else { return false }
                        let otherGood = other.serialNumber == "88150PV0EDG"
                        return isGood ? otherGood : !otherGood
                    }) {
                        return by3GS
                    }
                }

                // AirTag 专属智能跨端匹配（DC、DW、59元、2代）
                if isAirTag {
                    let isDC = item.screenSize == "DC" || item.customName?.contains("DC") == true || item.notes?.contains("DC") == true
                    let isDW = item.screenSize == "DW" || item.customName?.contains("DW") == true || item.notes?.contains("DW") == true
                    let is59 = item.price == "59" || item.customName?.contains("无篆刻") == true || item.notes?.contains("59") == true || item.screenSize == "无篆刻"
                    let isGen2 = item.model == "A2937" || item.name.contains("2nd") || item.customName?.contains("2") == true
                    if let match = list.first(where: { other in
                        let otherAirTag = other.category == "AirTag" || other.name.contains("AirTag")
                        guard otherAirTag else { return false }
                        let otherDC = other.screenSize == "DC" || other.customName?.contains("DC") == true || other.notes?.contains("DC") == true
                        let otherDW = other.screenSize == "DW" || other.customName?.contains("DW") == true || other.notes?.contains("DW") == true
                        let other59 = other.price == "59" || other.customName?.contains("无篆刻") == true || other.notes?.contains("59") == true || other.screenSize == "无篆刻"
                        let otherGen2 = other.model == "A2937" || other.name.contains("2nd") || other.customName?.contains("2") == true
                        if isDC { return otherDC }
                        if isDW { return otherDW }
                        if is59 { return other59 }
                        if isGen2 { return otherGen2 }
                        return !otherDC && !otherDW && !other59 && !otherGen2
                    }) {
                        return match
                    }
                }
                return nil
            }

            // 检查本地藏品是否仅为演示示例数据：如果是，且云端金库有真实设备，则不合并本地演示数据
            let localIsOnlySample = !localItems.isEmpty && localItems.count <= 6 && localItems.allSatisfy { SampleDataManager.isSampleItem($0) }
            let effectiveLocalItems = (localIsOnlySample && !remoteVault.collectionItems.isEmpty) ? [] : localItems

            // 处理所有本地藏品
            for localItem in effectiveLocalItems {
                // 如果本地藏品在墓碑中，检查是否在删除后再次被修改过
                if let deletedDate = mergedTombstones[localItem.id] {
                    if let updated = localItem.updatedAt, updated > deletedDate {
                        // 本地在被其他设备删除后又进行了有效修改 -> 复活保留
                    } else {
                        // 确认删除，跳过
                        continue
                    }
                }

                if let remoteMatch = findMatch(for: localItem, in: remoteVault.collectionItems) {
                    // 两端均存在同一硬件藏品：裁决较新的版本
                    let resolved = self.resolveItemConflict(local: localItem, remote: remoteMatch)
                    mergedItemsMap[resolved.id] = resolved
                } else {
                    // 仅本地拥有：保留（待上传同步至云端）
                    mergedItemsMap[localItem.id] = localItem
                }
            }

            // 处理仅在云端拥有的藏品
            for remoteItem in remoteVault.collectionItems {
                if mergedItemsMap[remoteItem.id] != nil { continue }
                let isAirTag = remoteItem.category == "AirTag" || remoteItem.name.contains("AirTag")
                if let sn = remoteItem.serialNumber, isUniqueHardwareSerial(sn), !isAirTag,
                   mergedItemsMap.values.contains(where: { $0.serialNumber == sn && $0.category != "AirTag" && !$0.name.contains("AirTag") }) {
                    continue
                }

                // 检查云端藏品是否已被本地标记删除
                if let deletedDate = mergedTombstones[remoteItem.id] {
                    if let updated = remoteItem.updatedAt, updated > deletedDate {
                        // 云端在此后被更新过 -> 保留
                        mergedItemsMap[remoteItem.id] = remoteItem
                    } else {
                        // 已被删除 -> 跳过
                        continue
                    }
                } else {
                    // 新设备从云端拉取下来
                    mergedItemsMap[remoteItem.id] = remoteItem
                }
            }

            // 全局硬件藏品彻底去重并规整（消除历史遗留多端同机重复）
            var finalItems: [CollectionItem] = []
            var seenHardwareSerials: [String: Int] = [:]
            var seenNonSerialAccessories: [String: Int] = [:]
            var seen59AirTag = false
            var seenDCAirTag = false
            var seenDWAirTag = false
            var seenAirTag2 = false
            var seenInsulatedAirTag1Count = 0
            var seenMagicMouse1Broken = false
            var seenMagicMouse1Good = false
            var seenIPhone3GBroken = false
            var seenIPhone3GSGood = false
            var seenIPhone3GSBroken = false
            var seenCompositeAVCable = false
            var seenComponentAVCable = false

            for item in Array(mergedItemsMap.values) {
                let isAirTag = item.category == "AirTag" || item.name.contains("AirTag")
                if isAirTag {
                    let isDC = item.screenSize == "DC" || item.customName?.contains("DC") == true || item.notes?.contains("DC") == true
                    let isDW = item.screenSize == "DW" || item.customName?.contains("DW") == true || item.notes?.contains("DW") == true
                    let is59 = item.price == "59" || item.customName?.contains("无篆刻") == true || item.notes?.contains("59") == true || item.screenSize == "无篆刻"
                    let isGen2 = item.model == "A2937" || item.name.contains("2nd") || item.customName?.contains("2") == true

                    if isDC {
                        if seenDCAirTag {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seenDCAirTag = true
                    } else if isDW {
                        if seenDWAirTag {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seenDWAirTag = true
                    } else if is59 {
                        if seen59AirTag {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seen59AirTag = true
                    } else if isGen2 {
                        if seenAirTag2 {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seenAirTag2 = true
                    } else {
                        // 官网4件装中未启用的带篆刻绝缘片款（恰好2枚绝缘片）
                        if seenInsulatedAirTag1Count >= 2 {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seenInsulatedAirTag1Count += 1
                    }
                    finalItems.append(item)
                    continue
                }

                // Magic Mouse 1代彻底去重与墓碑清理（确保只有 1 只改装好鼠标 + 1 只坏鼠标）
                let isMM1 = item.model == "A1296" || item.catalogID == "鼠标-2" || item.catalogID == "Magic Mouse (1st generation)" || item.name == "Magic Mouse (1st generation)" || item.name == "Magic Mouse"
                if isMM1 {
                    let isGood = item.serialNumber == "CC228117CGDFFGAC" || item.price == "63.4" || item.price == "63" || item.notes?.contains("充电") == true || item.notes?.contains("升级") == true
                    if isGood {
                        if seenMagicMouse1Good {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seenMagicMouse1Good = true
                        var calibrated = item
                        calibrated.name = "Magic Mouse (1st generation)"
                        calibrated.productName = "Magic Mouse (1st generation)"
                        calibrated.model = "A1296"
                        calibrated.catalogID = "Magic Mouse (1st generation)"
                        calibrated.category = "Input Devices"
                        calibrated.serialNumber = "CC228117CGDFFGAC"
                        calibrated.price = "63.4"
                        calibrated.purchaseSource = "闲鱼"
                        calibrated.notes = "升级充电模组 · 改装充电方案"
                        calibrated.battery = "可充锂电池 (改装充电方案)"
                        calibrated.isInUse = false
                        finalItems.append(calibrated)
                        continue
                    } else {
                        if seenMagicMouse1Broken {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seenMagicMouse1Broken = true
                        var calibrated = item
                        calibrated.name = "Magic Mouse (1st generation)"
                        calibrated.productName = "Magic Mouse (1st generation)"
                        calibrated.model = "A1296"
                        calibrated.catalogID = "Magic Mouse (1st generation)"
                        calibrated.category = "Input Devices"
                        calibrated.price = "18"
                        calibrated.purchaseSource = "闲鱼"
                        calibrated.notes = "坏的 · 维修失败"
                        calibrated.isInUse = false
                        finalItems.append(calibrated)
                        continue
                    }
                }

                // iPhone 3G 严格去重与墓碑清理（确保存档中仅 1 台坏机，无序列号，闲鱼 39元，不开机）
                let is3G = item.model == "A1241" || item.catalogID == "iPhone1,2" || item.name.lowercased() == "iphone 3g"
                if is3G {
                    if seenIPhone3GBroken {
                        mergedTombstones[item.id] = Date()
                        continue
                    }
                    seenIPhone3GBroken = true
                    var calibrated = item
                    calibrated.name = "iPhone 3G"
                    calibrated.productName = "iPhone 3G"
                    calibrated.model = "A1241"
                    calibrated.catalogID = "iPhone1,2"
                    calibrated.category = "iPhone"
                    calibrated.serialNumber = nil
                    calibrated.regionVersion = nil
                    if calibrated.price == nil || calibrated.price?.isEmpty == true { calibrated.price = "39" }
                    if calibrated.purchaseSource == nil || calibrated.purchaseSource?.isEmpty == true { calibrated.purchaseSource = "闲鱼" }
                    if calibrated.notes == nil || calibrated.notes?.isEmpty == true {
                        calibrated.notes = "坏的 · 不开机"
                    } else if !calibrated.notes!.contains("坏") {
                        calibrated.notes = "坏的 · " + calibrated.notes!
                    }
                    calibrated.isInUse = false
                    calibrated.isBatteryUntracked = true
                    calibrated.releaseYear = "2008"
                    finalItems.append(calibrated)
                    continue
                }

                // iPhone 3GS 严格去重与墓碑清理（确保存档中仅 2 台：1台好机 SN: 88150PV0EDG + 1台坏机 无SN）
                let is3GS = item.model == "A1303" || item.model == "A1325" || item.catalogID == "iPhone2,1" || item.catalogID == "iPhone-2" || item.catalogID == "iPhone-3" || item.name.lowercased() == "iphone 3gs"
                if is3GS {
                    let isGood = item.serialNumber == "88150PV0EDG"
                    if isGood {
                        if seenIPhone3GSGood {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seenIPhone3GSGood = true
                        var calibrated = item
                        calibrated.name = "iPhone 3GS"
                        calibrated.productName = "iPhone 3GS"
                        calibrated.model = "A1303"
                        calibrated.catalogID = "iPhone2,1"
                        calibrated.category = "iPhone"
                        calibrated.serialNumber = "88150PV0EDG"
                        calibrated.regionVersion = "MC637CH/A"
                        if calibrated.color == nil || calibrated.color?.isEmpty == true { calibrated.color = "黑色" }
                        if calibrated.price == nil || calibrated.price?.isEmpty == true { calibrated.price = "88" }
                        if calibrated.purchaseSource == nil || calibrated.purchaseSource?.isEmpty == true { calibrated.purchaseSource = "闲鱼" }
                        calibrated.isInUse = false
                        calibrated.releaseYear = "2009"
                        finalItems.append(calibrated)
                        continue
                    } else {
                        if seenIPhone3GSBroken {
                            mergedTombstones[item.id] = Date()
                            continue
                        }
                        seenIPhone3GSBroken = true
                        var calibrated = item
                        calibrated.name = "iPhone 3GS"
                        calibrated.productName = "iPhone 3GS"
                        calibrated.model = "A1325"
                        calibrated.catalogID = "iPhone2,1"
                        calibrated.category = "iPhone"
                        calibrated.serialNumber = nil
                        calibrated.regionVersion = nil
                        if calibrated.color == nil || calibrated.color?.isEmpty == true { calibrated.color = "白色" }
                        if calibrated.purchaseSource == nil || calibrated.purchaseSource?.isEmpty == true { calibrated.purchaseSource = "闲鱼" }
                        if calibrated.notes == nil || calibrated.notes?.isEmpty == true {
                            calibrated.notes = "坏的 · 不开机已拆未维修，电池问题，外壳碎裂"
                        } else if !calibrated.notes!.contains("坏") {
                            calibrated.notes = "坏的 · " + calibrated.notes!
                        }
                        calibrated.isInUse = false
                        calibrated.isBatteryUntracked = true
                        calibrated.releaseYear = "2009"
                        finalItems.append(calibrated)
                        continue
                    }
                }

                // Pointer Devices 规范化（两只2代均为在用主力机，统一英文品类 Input Devices）
                var processedItem = item
                processedItem.calibrateAdapterMetadata()
                if processedItem.model == "A1657" || processedItem.catalogID == "Magic Mouse 2" || processedItem.name == "Magic Mouse 2" {
                    processedItem.name = "Magic Mouse 2"
                    processedItem.productName = "Magic Mouse 2"
                    processedItem.model = "A1657"
                    processedItem.catalogID = "Magic Mouse 2"
                    processedItem.category = "Input Devices"
                    processedItem.isInUse = true
                } else if processedItem.model == "A1152" || processedItem.name.contains("Mighty Mouse") || processedItem.catalogID == "鼠标-1" {
                    processedItem.name = "Mighty Mouse"
                    processedItem.productName = "Mighty Mouse"
                    processedItem.model = "A1152"
                    processedItem.catalogID = "Mighty Mouse"
                    processedItem.category = "Input Devices"
                    processedItem.serialNumber = "8B83507S8YLTB"
                } else if processedItem.model == "A1535" || processedItem.name.contains("Magic Trackpad 2") || processedItem.catalogID == "鼠标-4" {
                    processedItem.name = "Magic Trackpad 2"
                    processedItem.productName = "Magic Trackpad 2"
                    processedItem.model = "A1535"
                    processedItem.catalogID = "Magic Trackpad 2"
                    processedItem.category = "Input Devices"
                    processedItem.serialNumber = "CC2002500VTJ2XVAR"
                } else if processedItem.model == "A1258" || processedItem.catalogID == "Composite AV Cable" || processedItem.name.localizedCaseInsensitiveContains("Composite AV Cable") {
                    processedItem.catalogID = "Composite AV Cable"
                    processedItem.model = "A1258"
                    processedItem.name = "Apple Composite AV Cable"
                    processedItem.productName = "Apple Composite AV Cable"
                    processedItem.category = "Adapters"
                    processedItem.releaseYear = "2007"
                    if processedItem.notes == nil || processedItem.notes?.isEmpty == true {
                        processedItem.notes = "MB129LL/A"
                    }
                } else if processedItem.model == "A1259" || processedItem.catalogID == "Component AV Cable" || processedItem.name.localizedCaseInsensitiveContains("Component AV Cable") {
                    processedItem.catalogID = "Component AV Cable"
                    processedItem.model = "A1259"
                    processedItem.name = "Apple Component AV Cable"
                    processedItem.productName = "Apple Component AV Cable"
                    processedItem.category = "Adapters"
                    processedItem.releaseYear = "2007"
                    if processedItem.notes == nil || processedItem.notes?.isEmpty == true {
                        processedItem.notes = "MB128LL/A"
                    }
                }

                let isComposite = processedItem.model == "A1258" || processedItem.catalogID == "Composite AV Cable" || processedItem.name.localizedCaseInsensitiveContains("Composite AV Cable")
                if isComposite {
                    if seenCompositeAVCable {
                        if let existingIdx = finalItems.firstIndex(where: { $0.model == "A1258" || $0.catalogID == "Composite AV Cable" || $0.name.localizedCaseInsensitiveContains("Composite AV Cable") }) {
                            var winner = finalItems[existingIdx]
                            self.fuseItemAttributes(&winner, fallback: processedItem)
                            finalItems[existingIdx] = winner
                            mergedTombstones[processedItem.id] = Date()
                        }
                        continue
                    }
                    seenCompositeAVCable = true
                    finalItems.append(processedItem)
                    continue
                }

                let isComponent = processedItem.model == "A1259" || processedItem.catalogID == "Component AV Cable" || processedItem.name.localizedCaseInsensitiveContains("Component AV Cable")
                if isComponent {
                    if seenComponentAVCable {
                        if let existingIdx = finalItems.firstIndex(where: { $0.model == "A1259" || $0.catalogID == "Component AV Cable" || $0.name.localizedCaseInsensitiveContains("Component AV Cable") }) {
                            var winner = finalItems[existingIdx]
                            self.fuseItemAttributes(&winner, fallback: processedItem)
                            finalItems[existingIdx] = winner
                            mergedTombstones[processedItem.id] = Date()
                        }
                        continue
                    }
                    seenComponentAVCable = true
                    finalItems.append(processedItem)
                    continue
                }

                if let sn = processedItem.serialNumber, isUniqueHardwareSerial(sn), !isAirTag {
                    if let existingIdx = seenHardwareSerials[sn] {
                        var winner = finalItems[existingIdx]
                        self.fuseItemAttributes(&winner, fallback: processedItem)
                        finalItems[existingIdx] = winner
                        // 将被合并剔除的幽灵条目记入墓碑，促使多端彻底删除
                        mergedTombstones[processedItem.id] = Date()
                        continue
                    } else {
                        seenHardwareSerials[sn] = finalItems.count
                        finalItems.append(processedItem)
                    }
                } else {
                    let rootCat = itemRootCategory(processedItem)
                    let isAccessoryOrAdapter = rootCat == "配件" || rootCat == "Accessories" || processedItem.category == "Adapters" || processedItem.category == "Adapter" || processedItem.category == "配件"
                    if isAccessoryOrAdapter && !isAirTag {
                        let key = (processedItem.catalogID ?? processedItem.model ?? processedItem.name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if !key.isEmpty {
                            if let existingIdx = seenNonSerialAccessories[key] {
                                var winner = finalItems[existingIdx]
                                self.fuseItemAttributes(&winner, fallback: processedItem)
                                finalItems[existingIdx] = winner
                                mergedTombstones[processedItem.id] = Date()
                                continue
                            }
                            seenNonSerialAccessories[key] = finalItems.count
                        }
                    }
                    finalItems.append(processedItem)
                }
            }

            let mergedItems = finalItems.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }

            // 3. 合并心愿单与喜欢 (Wanted & Favorites) - 严格防止已删除单品复活
            let localWantedUpdated = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "wantedUpdatedAt"))
            let remoteWantedUpdated = remoteVault.wantedUpdatedAt ?? remoteVault.lastModified
            let removedWanted = self.loadRemovedWantedIDs()

            var mergedWanted: Set<String>
            if localWantedUpdated > remoteWantedUpdated {
                // 本地心愿单变更更晚：以本地为准，严格剔除已标记删除的 ID
                mergedWanted = Set(localWantedIDs).subtracting(removedWanted)
            } else {
                // 远端包含变更：合并远端心愿单，但严格剔除本机已明确删除的 ID
                mergedWanted = Set(localWantedIDs).union(remoteVault.wantedDeviceIDs).subtracting(removedWanted)
            }

            let localFavUpdated = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "favoriteUpdatedAt"))
            let remoteFavUpdated = remoteVault.favoriteUpdatedAt ?? remoteVault.lastModified
            let removedFav = self.loadRemovedFavoriteIDs()

            var mergedFav: Set<String>
            if localFavUpdated > remoteFavUpdated {
                // 本地喜欢变更更晚：以本地为准，严格剔除已标记取消喜欢的 ID
                mergedFav = Set(localFavIDs).subtracting(removedFav)
            } else {
                // 合并远端喜欢，但严格剔除本机已取消喜欢的 ID
                mergedFav = Set(localFavIDs).union(remoteVault.favoriteDeviceIDs).subtracting(removedFav)
            }
            // 仅过滤已被删除且记录在墓碑中的自定义藏品喜欢，保留未拥有的百科设备喜欢标记
            mergedFav = mergedFav.filter { mergedTombstones[$0] == nil }

            // 3.5 合并在用设备清单 (In-Use / Daily Drivers)
            var remoteInUseSet = Set(remoteVault.inUseDeviceIDs ?? [])
            if remoteInUseSet.isEmpty {
                remoteInUseSet = Set(remoteVault.collectionItems.filter { $0.isDailyDriver }.map(\.id))
            }
            let remoteInUseSerials = Set(remoteVault.collectionItems.filter { $0.isDailyDriver }.compactMap(\.serialNumber))

            for idx in 0..<finalItems.count {
                let item = finalItems[idx]
                let matchInRemoteIDs = remoteInUseSet.contains(item.id)
                let matchInRemoteSerials = item.serialNumber.map { remoteInUseSerials.contains($0) } ?? false

                if matchInRemoteIDs || matchInRemoteSerials {
                    // 若远端明确是在用设备
                    if let localMatch = localItems.first(where: { $0.id == item.id || ($0.serialNumber != nil && $0.serialNumber == item.serialNumber) }),
                       let localUpdated = localMatch.updatedAt,
                       let remoteUpdated = remoteVault.collectionItems.first(where: { $0.id == item.id })?.updatedAt,
                       localUpdated > remoteUpdated {
                        // 本地更新更晚且本地移除了在用状态：以本地较新的移除为准
                        finalItems[idx].isInUse = localMatch.isInUse
                    } else {
                        finalItems[idx].isInUse = true
                    }
                }
            }
            let mergedInUseIDs = finalItems.filter { $0.isDailyDriver }.map(\.id)

            // 4. 合并抢购日程与发售通知 (Launch Drops)
            let restoredDrops = LaunchDropManager.shared.userRestoredDropIDs
            var mergedDismissedIDs = Set(localDismissedDropIDs).subtracting(restoredDrops)
            if let remoteDismissed = remoteVault.dismissedDropIDs {
                for rId in remoteDismissed {
                    // 绝不复活用户在本机已明确解除隐藏 (Unhide) 的单品！
                    if !restoredDrops.contains(rId) {
                        mergedDismissedIDs.insert(rId)
                    }
                }
            }

            let unstarred = LaunchDropManager.shared.userUnstarredDropIDs
            var mergedDropIDs = Set(localDropIDs)
            if let remoteDrops = remoteVault.interestedDropIDs {
                for rId in remoteDrops {
                    // 绝不复活用户在本机点灭小星星或已忽略的单品！
                    if !unstarred.contains(rId) && !mergedDismissedIDs.contains(rId) {
                        mergedDropIDs.insert(rId)
                    }
                }
            }
            LaunchDropManager.shared.updateInterestedIDsFromCloud(Array(mergedDropIDs), dismissedCloudIDs: Array(mergedDismissedIDs))

            // 5. 合并稍后阅读与永久收藏新闻 (Read Later & Saved Stories)
            NewsBookmarkManager.shared.updateFromCloud(
                readLater: remoteVault.readLaterStories ?? [],
                saved: remoteVault.savedStories ?? []
            )
            let mergedReadLater = NewsBookmarkManager.shared.readLaterItems
            let mergedSaved = NewsBookmarkManager.shared.savedItems

            // 6. 合并博物馆名称与大类排序偏好
            var resolvedTitle = localTitle
            if resolvedTitle.isEmpty && !(remoteVault.museumTitle ?? "").isEmpty {
                resolvedTitle = remoteVault.museumTitle ?? ""
            }

            if let backupOrders = remoteVault.rootCategoryOrders {
                let remoteUpdated = backupOrders.updatedAt ?? remoteVault.lastModified
                let localUpdated = RootCategoryOrderStore.shared.orderUpdatedAt ?? .distantPast
                if remoteUpdated >= localUpdated {
                    if let enc = backupOrders.encyclopedia, !enc.isEmpty {
                        RootCategoryOrderStore.shared.applyRemoteOrder(enc, isEncyclopedia: true, updatedAt: remoteUpdated)
                    }
                    if let col = backupOrders.collection, !col.isEmpty {
                        RootCategoryOrderStore.shared.applyRemoteOrder(col, isEncyclopedia: false, updatedAt: remoteUpdated)
                    }
                    if let bat = backupOrders.battery, !bat.isEmpty {
                        RootCategoryOrderStore.shared.applyRemoteBatteryOrder(bat, updatedAt: remoteUpdated)
                    }
                }
            }

            // 7. 保存本地存储与持久化
            saveCollection(mergedItems)
            self.saveTombstones(mergedTombstones)
            UserDefaults.standard.set(encodeIDs(mergedWanted), forKey: "wantedDeviceIDs")
            UserDefaults.standard.set(encodeIDs(mergedFav), forKey: "favoriteDeviceIDs")
            if !resolvedTitle.isEmpty && UserDefaults.standard.string(forKey: "museumTitle") != resolvedTitle {
                UserDefaults.standard.set(resolvedTitle, forKey: "museumTitle")
            }

            // 8. 构造更新后的云端金库并原子覆写
            let updatedVault = PommeSyncVault(
                schemaVersion: 1,
                vaultId: remoteVault.vaultId,
                lastModified: Date(),
                sourceDeviceId: self.deviceId,
                sourceDeviceName: self.deviceName,
                collectionItems: mergedItems,
                wantedDeviceIDs: Array(mergedWanted),
                wantedUpdatedAt: max(localWantedUpdated, remoteWantedUpdated),
                favoriteDeviceIDs: Array(mergedFav),
                favoriteUpdatedAt: max(localFavUpdated, remoteFavUpdated),
                inUseDeviceIDs: mergedInUseIDs,
                interestedDropIDs: Array(LaunchDropManager.shared.interestedDropIDs),
                dismissedDropIDs: Array(mergedDismissedIDs),
                readLaterStories: mergedReadLater,
                savedStories: mergedSaved,
                tombstones: mergedTombstones,
                rootCategoryOrders: RootCategoryOrdersBackup(
                    encyclopedia: RootCategoryOrderStore.shared.encyclopediaOrder,
                    collection: RootCategoryOrderStore.shared.collectionOrder,
                    battery: RootCategoryOrderStore.shared.batteryOrder,
                    updatedAt: RootCategoryOrderStore.shared.orderUpdatedAt ?? Date()
                ),
                museumTitle: resolvedTitle
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let updatedVaultData = try encoder.encode(updatedVault)
            try updatedVaultData.write(to: targetVaultURL, options: .atomic)

            let summary = String(format: appLocalized("%d items · %d in-use · %d wishlist"), mergedItems.count, mergedInUseIDs.count, mergedWanted.count)
            return (mergedItems, Date(), summary)
        }
    }

    /// 藏品冲突裁决算法：依据编辑时间戳、补电日期与字段完整度择优融合
    private func resolveItemConflict(local: CollectionItem, remote: CollectionItem) -> CollectionItem {
        // 规则 1：明确带有 updatedAt 修改时间戳的，以较新时间戳为准
        if let localUp = local.updatedAt, let remoteUp = remote.updatedAt {
            var winner = localUp >= remoteUp ? local : remote
            let loser = localUp >= remoteUp ? remote : local
            fuseItemAttributes(&winner, fallback: loser)
            return winner
        } else if local.updatedAt != nil {
            var winner = local
            fuseItemAttributes(&winner, fallback: remote)
            return winner
        } else if remote.updatedAt != nil {
            var winner = remote
            fuseItemAttributes(&winner, fallback: local)
            return winner
        }

        // 规则 2：若无时间戳，比对补电维护记录日期（较近维护的更可信）
        if let localCharge = BatteryMaintenanceManager.parseChargeDate(local.lastCharged),
           let remoteCharge = BatteryMaintenanceManager.parseChargeDate(remote.lastCharged) {
            var winner = localCharge >= remoteCharge ? local : remote
            let loser = localCharge >= remoteCharge ? remote : local
            fuseItemAttributes(&winner, fallback: loser)
            return winner
        }

        // 规则 3：默认偏好本地，同时吸收云端补充的自定义备注或动态周期
        var winner = local
        fuseItemAttributes(&winner, fallback: remote)
        return winner
    }

    /// 融合补充两端互补字段，防止字段遗失
    private func fuseItemAttributes(_ item: inout CollectionItem, fallback: CollectionItem) {
        if item.customName == nil || item.customName?.isEmpty == true { item.customName = fallback.customName }
        if item.serialNumber == nil || item.serialNumber?.isEmpty == true { item.serialNumber = fallback.serialNumber }
        if item.battery == nil || item.battery?.isEmpty == true { item.battery = fallback.battery }
        if item.lastCharged == nil || item.lastCharged?.isEmpty == true { item.lastCharged = fallback.lastCharged }
        if item.notes == nil || item.notes?.isEmpty == true { item.notes = fallback.notes }
        if item.color == nil || item.color?.isEmpty == true { item.color = fallback.color }
        if item.storage == nil || item.storage?.isEmpty == true { item.storage = fallback.storage }
        if item.customCycleDays == nil { item.customCycleDays = fallback.customCycleDays }
        if item.isBatteryUntracked == nil { item.isBatteryUntracked = fallback.isBatteryUntracked }
        if item.isInUse == nil { item.isInUse = fallback.isInUse }
    }

    // MARK: - 自动同步调度 (Debounced Auto-Sync)
    /// 当本地数据有增删改时，防抖 2 秒后自动向云端金库同步
    func scheduleAutoSync(delay: TimeInterval = 2.0) {
        guard isConfigured, autoSyncEnabled else { return }

        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.syncNow(trigger: "Auto Sync")
        }
    }

    /// 应用切到前台或启动时静默同步一次
    func triggerForegroundSync() {
        guard isConfigured, autoSyncEnabled else { return }
        Task {
            await self.syncNow(trigger: "Foreground Auto Sync")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 错误类型定义
enum SyncError: LocalizedError {
    case notConfigured
    case folderAccessDenied
    case corruptedRemoteVault(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return appLocalized("No iCloud Drive sync folder selected")
        case .folderAccessDenied:
            return appLocalized("Access denied to the specified folder. Please reselect.")
        case .corruptedRemoteVault(let reason):
            return String(format: appLocalized("Cloud vault file corrupted: %@"), reason)
        }
    }
}
