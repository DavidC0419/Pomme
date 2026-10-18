import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 数据存储与图鉴全局索引管理 (Catalog Data Store & Global Indexes)

/// 从本地应用包加载 devices.json
func loadDevices() -> [Device] {
    guard let url = Bundle.main.url(forResource: "devices", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let devices = try? JSONDecoder().decode([Device].self, from: data) else { return [] }
    return devices
}

/// 离线搜索目录和展示用图鉴分开：它更大，但不需要给每个型号都准备图片。
func loadSearchCatalog() -> [SearchCatalogRecord] {
    guard let url = Bundle.main.url(forResource: "search-catalog", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let records = try? JSONDecoder().decode([SearchCatalogRecord].self, from: data) else {
        return []
    }
    // SDK、模拟器和虚拟机是软件/运行环境，不作为可收藏的实体设备展示。
    return records.filter {
        !["SDK", "Simulator", "Virtual Machine", "iBridge", "Beddit"].contains($0.category)
    }
}

/// 获取个人藏品持久化存储路径
/// 放在 App Group 共享容器中，以便主 App、手表端与 Siri 意图共享同一份数据
func collectionFileURL() -> URL {
    let groupURL = PommeStore.containerURL.appendingPathComponent("collection.json")
    let legacyURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("collection.json")
    let fileManager = FileManager.default
    if groupURL != legacyURL, !fileManager.fileExists(atPath: groupURL.path), fileManager.fileExists(atPath: legacyURL.path) {
        if (try? fileManager.copyItem(at: legacyURL, to: groupURL)) == nil { return legacyURL }
    }
    return groupURL
}

/// 读取用户拥有的所有实体藏品
func loadCollection() -> [CollectionItem] {
    let localURL = collectionFileURL()
    if let data = try? Data(contentsOf: localURL),
       var items = try? JSONDecoder().decode([CollectionItem].self, from: data) {
        // 若当前本地仅有演示示例数据，且应用 Bundle 内置了个人完整藏品数据，则优先恢复个人真实藏品
        let isOnlySample = !items.isEmpty && items.count <= 6 && items.allSatisfy { SampleDataManager.isSampleItem($0) }
        if isOnlySample,
           let bundledPersonalURL = Bundle.main.url(forResource: "MyMuseum-PersonalCollection", withExtension: "json"),
           let pData = try? Data(contentsOf: bundledPersonalURL),
           let personalItems = try? JSONDecoder().decode([CollectionItem].self, from: pData),
           !personalItems.isEmpty {
            saveCollection(personalItems)
            return personalItems
        }

        let didMigrate = items.contains { item in
            item.productName == nil || (item.name == "Lightning to 3.5 mm Headphone Jack Adapter" &&
                (item.catalogID != item.name || item.model != "A1749" || item.category != "Adapters")) ||
                (item.catalogID == "AppleTV-3" && item.model == "A1842") ||
                item.isInUse == nil ||
                (item.model == "A1657" && item.isInUse != true) ||
                (item.model == "A1296" && (item.name != "Magic Mouse (1st generation)" || item.productName != "Magic Mouse (1st generation)")) ||
                item.name == "iphone 3G" || item.name == "iphone 3GS" ||
                (item.model == "A1241" && item.name != "iPhone 3G") ||
                ((item.model == "A1303" || item.model == "A1325") && item.name != "iPhone 3GS") ||
                (item.model == "A1241" && item.serialNumber != nil) ||
                (item.model == "A1325" && item.serialNumber != nil) ||
                (item.category == "Adapter" && (item.releaseYear == "白色" || item.releaseYear == "透明" || item.releaseYear == "夜光" || item.releaseYear == "未拆封" || item.releaseYear == "有底座" || item.releaseYear == "双面胶" || item.releaseYear == "蓝色" || item.releaseYear == nil || item.releaseYear?.isEmpty == true)) ||
                (item.model == "A1258" && (item.productName != "Apple Composite AV Cable" || item.releaseYear != "2007" || item.catalogID != "Composite AV Cable"))
        } || items.filter { $0.category == "AirTag" || $0.name.contains("AirTag") }.count > 6 ||
           items.filter { $0.model == "A1258" || $0.catalogID == "Composite AV Cable" || $0.name.localizedCaseInsensitiveContains("Composite AV Cable") }.count > 1
        let migratedItems = migrateCollectionItems(items)
        let countChanged = items.count != migratedItems.count
        items = migratedItems
        if didMigrate || countChanged { saveCollection(items) }
        return items
    }
    // 本地无存储记录时，优先尝试从 Bundle 中内置的个人藏品数据加载（Xcode自用版）
    if let bundledPersonalURL = Bundle.main.url(forResource: "MyMuseum-PersonalCollection", withExtension: "json"),
       let pData = try? Data(contentsOf: bundledPersonalURL),
       let personalItems = try? JSONDecoder().decode([CollectionItem].self, from: pData),
       !personalItems.isEmpty {
        saveCollection(personalItems)
        return personalItems
    }
    return []
}

/// 旧数据兼容与升级迁移逻辑（补充历史补电日期与常用设备初始标识，并自动消除物理硬件重复）
func migrateCollectionItems(_ items: [CollectionItem]) -> [CollectionItem] {
    let knownChargeRecords: [String: (date: String, battery: String?)] = [:]
    let defaultInUseSerials: Set<String> = []

    let transformed = items.map { item -> CollectionItem in
        var migrated = item
        migrated.calibrateAdapterMetadata()
        if migrated.name == "Lightning to 3.5 mm Headphone Jack Adapter" {
            migrated.category = "Adapters"
            migrated.productName = migrated.name
            migrated.catalogID = migrated.name
            migrated.model = "A1749"
            migrated.releaseYear = "2016"
            migrated.processor = nil
            migrated.storage = nil
        } else if migrated.catalogID == "AppleTV-3" && migrated.model == "A1842" {
            migrated.catalogID = "AppleTV6,2"
            migrated.productName = "Apple TV 4K (1st generation)"
            migrated.category = "Apple TV"
        } else if migrated.model == "A1136" &&
                    (migrated.name.localizedCaseInsensitiveContains("u2") ||
                     migrated.notes?.localizedCaseInsensitiveContains("u2") == true ||
                     migrated.customName?.localizedCaseInsensitiveContains("u2") == true ||
                     migrated.modelVersion?.localizedCaseInsensitiveContains("MA664") == true ||
                     migrated.modelVersion?.localizedCaseInsensitiveContains("MA452") == true) {
            migrated.catalogID = "iPod with video-lateu2"
            migrated.productName = "iPod with video (Late 2006) U2 Edition"
            if migrated.color == nil || migrated.color?.isEmpty == true {
                migrated.color = "Black"
            }
        } else if (migrated.model == "A1307" || migrated.catalogID == "Airpods-1") &&
                    (migrated.modelVersion?.localizedCaseInsensitiveContains("MA850") == true ||
                     migrated.notes?.localizedCaseInsensitiveContains("发黏") == true ||
                     migrated.notes?.localizedCaseInsensitiveContains("露线") == true ||
                     migrated.name.localizedCaseInsensitiveContains("displayport") ||
                     migrated.name.localizedCaseInsensitiveContains("vga") ||
                     migrated.catalogID == "Airpods-1") {
            migrated.catalogID = "In-Ear Earphones with Remote and Mic"
            migrated.productName = "In-Ear Headphones with Remote and Mic"
            migrated.name = "In-Ear Headphones with Remote and Mic"
            migrated.category = "Audio Accessories"
        } else if migrated.model == "A3057" || migrated.name.localizedCaseInsensitiveContains("AirPods 4") {
            migrated.category = "AirPods"
            migrated.catalogID = "Airpods-8"
            if migrated.productName == nil || migrated.productName?.isEmpty == true || migrated.productName?.localizedCaseInsensitiveContains("EarPods") == true {
                migrated.productName = "AirPods 4 with Active Noise Cancellation"
            }
        } else if migrated.model == "A1112" && (migrated.category == "iPod" || migrated.name.contains("shuffle")) {
            migrated.catalogID = "iPod-6"
            migrated.model = "A1112"
            migrated.category = "iPod"
            migrated.name = "iPod shuffle (512 MB)"
            migrated.productName = "iPod shuffle (512 MB)"
        } else if migrated.model == "A1204" {
            migrated.catalogID = "iPod-11"
            migrated.model = "A1204"
            migrated.category = "iPod"
            migrated.name = "iPod shuffle (2nd generation) Avon Edition"
            migrated.productName = "iPod shuffle (2nd generation) Avon Edition"
        } else if migrated.model == "A1271" {
            migrated.catalogID = "iPod-15"
            migrated.model = "A1271"
            migrated.category = "iPod"
            migrated.name = "iPod shuffle (3rd generation)"
            migrated.productName = "iPod shuffle (3rd generation)"
        } else if migrated.model == "A1373" {
            migrated.catalogID = "iPod-22"
            migrated.model = "A1373"
            migrated.category = "iPod"
            migrated.name = "iPod shuffle (4th generation)"
            migrated.productName = "iPod shuffle (4th generation)"
        } else if migrated.model == "A1796" && (migrated.category == "Beats" || migrated.name.contains("Solo")) {
            migrated.catalogID = "BeatsSolo3,1"
            migrated.model = "A1796"
            migrated.category = "Beats"
            migrated.name = "Beats Solo³ Wireless"
            migrated.productName = "Beats Solo³ Wireless"
            migrated.releaseYear = "2016"
        } else if migrated.name.contains("Balmain") || migrated.catalogID == "PowerBeats3,1-balmain" || migrated.catalogID == "Beats-11" || (migrated.model == "A1747" && migrated.category.contains("Beats")) {
            // Powerbeats³ 严密校准（防止误归入 Balmain 特别版）
            let isExplicitBalmain = (migrated.customName?.lowercased().contains("balmain") == true) || (migrated.notes?.lowercased().contains("balmain") == true)
            if !isExplicitBalmain {
                migrated.name = "Powerbeats³ Wireless"
                migrated.productName = "Powerbeats³ Wireless"
                migrated.catalogID = "PowerBeats3,1"
                migrated.model = "A1747"
                migrated.category = "Beats"
                if migrated.releaseYear == nil || migrated.releaseYear?.isEmpty == true {
                    migrated.releaseYear = "2016"
                }
            }
        } else if migrated.model == "A2096" || (migrated.name == "AirPods Max" && migrated.model != "A3454" && migrated.model != "A3184" && !migrated.name.contains("2") && !migrated.name.contains("USB-C")) {
            // AirPods Max 1代（Lightning 口）：确保匹配标准 1代图鉴与老图
            migrated.catalogID = "AirPodsMax1,1"
            migrated.model = "A2096"
            migrated.productName = "AirPods Max"
            migrated.category = "AirPods"
            if migrated.releaseYear == nil || migrated.releaseYear?.isEmpty == true {
                migrated.releaseYear = "2020"
            }
        } else if migrated.model == "A3454" || migrated.model == "A3184" || migrated.name.contains("Max 2") || migrated.catalogID == "Airpods-10" || migrated.catalogID == "AirPodsMax1,2" {
            // AirPods Max 2代 / USB-C 款
            migrated.catalogID = "AirPodsMax1,2"
            migrated.model = migrated.model ?? "A3454"
            migrated.productName = "AirPods Max 2"
            migrated.category = "AirPods"
        } else if migrated.model == "A1258" || migrated.catalogID == "Composite AV Cable" || migrated.name.localizedCaseInsensitiveContains("Composite AV Cable") {
            migrated.catalogID = "Composite AV Cable"
            migrated.model = "A1258"
            migrated.name = "Apple Composite AV Cable"
            migrated.productName = "Apple Composite AV Cable"
            migrated.category = "Adapters"
            migrated.releaseYear = "2007"
            if migrated.notes == nil || migrated.notes?.isEmpty == true {
                migrated.notes = "MB129LL/A"
            }
        } else if migrated.model == "A1259" || migrated.catalogID == "Component AV Cable" || migrated.name.localizedCaseInsensitiveContains("Component AV Cable") {
            migrated.catalogID = "Component AV Cable"
            migrated.model = "A1259"
            migrated.name = "Apple Component AV Cable"
            migrated.productName = "Apple Component AV Cable"
            migrated.category = "Adapters"
            migrated.releaseYear = "2007"
            if migrated.notes == nil || migrated.notes?.isEmpty == true {
                migrated.notes = "MB128LL/A"
            }
        } else if migrated.model == "A1657" || migrated.catalogID == "鼠标-5" || migrated.catalogID == "Magic Mouse 2" || migrated.name == "Magic Mouse 2" {
            // Magic Mouse 2 (A1657)：两只2代日常均在用主力机
            migrated.catalogID = "Magic Mouse 2"
            migrated.model = "A1657"
            migrated.productName = "Magic Mouse 2"
            migrated.name = "Magic Mouse 2"
            migrated.category = "Input Devices"
            migrated.releaseYear = "2015"
            migrated.isInUse = true
        } else if migrated.model == "A1296" || migrated.catalogID == "鼠标-2" || migrated.catalogID == "Magic Mouse (1st generation)" || migrated.name == "Magic Mouse (1st generation)" || (migrated.name == "Magic Mouse" && migrated.model != "A1657" && migrated.model != "A3204") {
            // Magic Mouse 1代 (A1296)：1只好的（换了充电方案 · 闲鱼 63.4） + 1只坏的（闲鱼 18）
            migrated.catalogID = "Magic Mouse (1st generation)"
            migrated.model = "A1296"
            migrated.productName = "Magic Mouse (1st generation)"
            migrated.name = "Magic Mouse (1st generation)"
            migrated.category = "Input Devices"
            migrated.releaseYear = "2009"
            let isGoodModded = migrated.notes?.contains("充电") == true ||
                               migrated.notes?.contains("升级") == true
            if isGoodModded {
                migrated.notes = "升级充电模组 · 改装充电方案"
                migrated.battery = "可充锂电池 (改装充电方案)"
                migrated.isInUse = false
            } else {
                migrated.notes = "备用"
                migrated.isInUse = false
            }
        } else if migrated.model == "A1152" || migrated.name.contains("Mighty Mouse") || migrated.catalogID == "鼠标-1" {
            migrated.catalogID = "Mighty Mouse"
            migrated.model = "A1152"
            migrated.productName = "Mighty Mouse"
            migrated.name = "Mighty Mouse"
            migrated.category = "Input Devices"
            migrated.releaseYear = "2005"
            migrated.isInUse = false
        } else if migrated.model == "A1535" || migrated.name.contains("Magic Trackpad 2") || migrated.catalogID == "鼠标-4" {
            migrated.catalogID = "Magic Trackpad 2"
            migrated.model = "A1535"
            migrated.productName = "Magic Trackpad 2"
            migrated.name = "Magic Trackpad 2"
            migrated.category = "Input Devices"
            migrated.releaseYear = "2015"
        } else if migrated.model == "A1156" {
            // A1156 遥控器（白色）：不常用设备，免放常用列表，统一纳入 365 天 CR2032 换电池维护
            migrated.category = "Remote"
            migrated.model = "A1156"
            migrated.isInUse = false
            migrated.customCycleDays = 365
            if migrated.battery == nil || migrated.battery?.isEmpty == true {
                migrated.battery = "CR2032 纽扣电池"
            }
        } else if migrated.model == "A1241" || migrated.catalogID == "iPhone1,2" || migrated.name.lowercased() == "iphone 3g" {
            // iPhone 3G
            migrated.catalogID = "iPhone1,2"
            migrated.model = "A1241"
            migrated.productName = "iPhone 3G"
            migrated.name = "iPhone 3G"
            migrated.category = "iPhone"
            migrated.releaseYear = "2008"
            migrated.serialNumber = nil
            migrated.regionVersion = nil
            migrated.isInUse = false
        } else if migrated.model == "A1303" || migrated.model == "A1325" || migrated.catalogID == "iPhone2,1" || migrated.catalogID == "iPhone-2" || migrated.catalogID == "iPhone-3" || migrated.name.lowercased() == "iphone 3gs" {
            // iPhone 3GS
            migrated.catalogID = "iPhone2,1"
            migrated.productName = "iPhone 3GS"
            migrated.name = "iPhone 3GS"
            migrated.category = "iPhone"
            migrated.releaseYear = "2009"
            let isGood = migrated.notes?.contains("坏") != true
            if isGood {
                migrated.model = "A1303"
                migrated.regionVersion = "MC637CH/A"
                if migrated.color == nil || migrated.color?.isEmpty == true { migrated.color = "黑色" }
                migrated.isInUse = false
            } else {
                migrated.model = "A1325"
                migrated.serialNumber = nil
                migrated.regionVersion = nil
                if migrated.color == nil || migrated.color?.isEmpty == true { migrated.color = "白色" }
                migrated.isInUse = false
                migrated.isBatteryUntracked = true
            }
        } else if migrated.productName == nil {
            migrated.productName = migrated.resolvedProductName
        }

        // AirTag 专属元数据与使用状态规范化
        if migrated.category.lowercased() == "airtag" || migrated.name.lowercased().contains("airtag") || migrated.model == "A2187" || migrated.model == "A2937" {
            migrated.category = "AirTag"
            migrated.customCycleDays = 365
            if migrated.model == "A2937" || migrated.name.contains("2") {
                migrated.catalogID = "afw2,4"
                migrated.model = "A2937"
                migrated.productName = "AirTag (2nd generation)"
                if migrated.customName == nil || migrated.customName?.isEmpty == true {
                    migrated.customName = "AirTag 2 (带篆刻 · 绝缘片)"
                }
                migrated.isInUse = false
                if migrated.battery == nil || migrated.battery?.isEmpty == true { migrated.battery = "CR2032 (已插绝缘片)" }
                if migrated.notes == nil || migrated.notes?.isEmpty == true { migrated.notes = "已插绝缘片 · 零耗电免维护 · 2代带篆刻 · 官网订购" }
            } else {
                migrated.catalogID = "AirTag-1"
                migrated.model = "A2187"
                migrated.productName = "AirTag"
                if migrated.screenSize == "DC" || migrated.customName?.contains("DC") == true || migrated.notes?.contains("DC") == true || migrated.id == "sheet-158" || migrated.id == "DBE8A0E1-99FC-4F50-AEAF-14D6B75ABFE7" {
                    migrated.customName = "AirTag (篆刻: DC)"
                    migrated.screenSize = "DC"
                    migrated.isInUse = true
                    migrated.battery = "CR2032 纽扣电池"
                    if migrated.lastCharged == nil || migrated.lastCharged?.isEmpty == true { migrated.lastCharged = "2026.04.15" }
                    if migrated.notes == nil || migrated.notes?.isEmpty == true { migrated.notes = "日常在用 · 钥匙扣 · 篆刻: DC · 官网4件装 · CR2032 供电中" }
                } else if migrated.screenSize == "DW" || migrated.customName?.contains("DW") == true || migrated.notes?.contains("DW") == true || migrated.id == "sheet-159" || migrated.id == "BC77774D-6FCA-47A7-9FB1-F3496DB219B7" {
                    migrated.customName = "AirTag (篆刻: DW)"
                    migrated.screenSize = "DW"
                    migrated.isInUse = true
                    migrated.battery = "CR2032 纽扣电池"
                    if migrated.lastCharged == nil || migrated.lastCharged?.isEmpty == true { migrated.lastCharged = "2026.05.20" }
                    if migrated.notes == nil || migrated.notes?.isEmpty == true { migrated.notes = "日常在用 · 遥控器 · 篆刻: DW · 官网4件装 · CR2032 供电中" }
                } else if migrated.price == "59" || migrated.notes?.contains("便宜") == true || migrated.customName?.contains("无篆刻") == true || migrated.id == "sheet-162" || migrated.id == "3F225F0A-ABC7-460C-8893-57537A5CA3FE" {
                    migrated.customName = "AirTag (无篆刻 · 便宜买入)"
                    migrated.screenSize = "无篆刻"
                    migrated.price = "59"
                    migrated.isInUse = true
                    migrated.battery = "CR2032 纽扣电池"
                    if migrated.lastCharged == nil || migrated.lastCharged?.isEmpty == true { migrated.lastCharged = "2026.06.01" }
                    if migrated.notes == nil || migrated.notes?.isEmpty == true { migrated.notes = "日常在用 · 无篆刻 · 59元特价买入 · CR2032 供电中" }
                } else {
                    if migrated.customName == nil || migrated.customName?.isEmpty == true {
                        migrated.customName = "AirTag (带篆刻 · 绝缘片)"
                    }
                    migrated.isInUse = false
                    if migrated.battery == nil || migrated.battery?.isEmpty == true { migrated.battery = "CR2032 (已插绝缘片)" }
                    if migrated.notes == nil || migrated.notes?.isEmpty == true { migrated.notes = "已插绝缘片 · 零耗电免维护 · 官网4件装 · 独立篆刻" }
                }
            }
        }

        // 补全历史补电时间与电量健康
        if let sn = migrated.serialNumber, let record = knownChargeRecords[sn] {
            if migrated.lastCharged == nil || migrated.lastCharged?.isEmpty == true {
                migrated.lastCharged = record.date
            }
            if (migrated.battery == nil || migrated.battery?.isEmpty == true), let b = record.battery {
                migrated.battery = b
            }
        }

        // 初始常用设备标识
        if migrated.isInUse == nil {
            if let sn = migrated.serialNumber, defaultInUseSerials.contains(sn) {
                migrated.isInUse = true
            } else {
                migrated.isInUse = false
            }
        }
        return migrated
    }

    // 防御性单体硬件去重与 AirTag 严密校准（确保：3 枚在用 + 3 枚未启用绝缘片）
    var deduped: [CollectionItem] = []
    var seenSerials: [String: Int] = [:]
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

    for item in transformed {
        let isAirTag = item.category == "AirTag" || item.name.contains("AirTag")
        if isAirTag {
            var airtag = item
            let isDC = airtag.screenSize == "DC" || airtag.customName?.contains("DC") == true || airtag.notes?.contains("DC") == true || airtag.id == "sheet-158" || airtag.id == "DBE8A0E1-99FC-4F50-AEAF-14D6B75ABFE7"
            let isDW = airtag.screenSize == "DW" || airtag.customName?.contains("DW") == true || airtag.notes?.contains("DW") == true || airtag.id == "sheet-159" || airtag.id == "BC77774D-6FCA-47A7-9FB1-F3496DB219B7"
            let is59 = airtag.price == "59" || airtag.notes?.contains("59元") == true || airtag.customName?.contains("无篆刻") == true || airtag.screenSize == "无篆刻" || airtag.id == "sheet-162" || airtag.id == "3F225F0A-ABC7-460C-8893-57537A5CA3FE"
            let isGen2 = airtag.model == "A2937" || airtag.name.contains("2nd") || airtag.customName?.contains("2") == true

            if isDC {
                if seenDCAirTag {
                    continue
                }
                seenDCAirTag = true
            } else if isDW {
                if seenDWAirTag {
                    continue
                }
                seenDWAirTag = true
            } else if is59 {
                if seen59AirTag {
                    continue
                }
                seen59AirTag = true
            } else if isGen2 {
                if seenAirTag2 {
                    continue
                }
                seenAirTag2 = true
            } else {
                // 官网4件装中未启用的带篆刻绝缘片款（4件装包含 DC + DW + 恰好2枚绝缘片）
                if seenInsulatedAirTag1Count >= 2 {
                    continue
                }
                seenInsulatedAirTag1Count += 1
            }
            deduped.append(airtag)
            continue
        }

        // Magic Mouse 1代严格去重（确保只有 1 只改装充电方案的好鼠标 + 1 只坏鼠标）
        let isMM1 = item.model == "A1296" || item.catalogID == "Magic Mouse (1st generation)" || item.name == "Magic Mouse (1st generation)" || item.name == "Magic Mouse"
        if isMM1 {
            let isGood = item.serialNumber == "CC228117CGDFFGAC" || item.price == "63.4" || item.price == "63" || item.notes?.contains("充电") == true || item.notes?.contains("升级") == true
            if isGood {
                if seenMagicMouse1Good {
                    continue
                }
                seenMagicMouse1Good = true
            } else {
                if seenMagicMouse1Broken {
                    continue
                }
                seenMagicMouse1Broken = true
            }
            deduped.append(item)
            continue
        }

        // iPhone 3G 严格去重（确保只有 1 台坏机，无序列号）
        let is3G = item.model == "A1241" || item.catalogID == "iPhone1,2" || item.name.lowercased() == "iphone 3g"
        if is3G {
            if seenIPhone3GBroken {
                continue
            }
            seenIPhone3GBroken = true
            deduped.append(item)
            continue
        }

        // iPhone 3GS 严格去重（确保只有 1 台好机 + 1 台坏机）
        let is3GS = item.model == "A1303" || item.model == "A1325" || item.catalogID == "iPhone2,1" || item.catalogID == "iPhone-2" || item.catalogID == "iPhone-3" || item.name.lowercased() == "iphone 3gs"
        if is3GS {
            let isGood = item.serialNumber == "88150PV0EDG"
            if isGood {
                if seenIPhone3GSGood {
                    continue
                }
                seenIPhone3GSGood = true
            } else {
                if seenIPhone3GSBroken {
                    continue
                }
                seenIPhone3GSBroken = true
            }
            deduped.append(item)
            continue
        }

        // Apple Composite AV Cable (A1258) 严格去重（确保只有 1 条官方线缆，多端融合）
        let isComposite = item.model == "A1258" || item.catalogID == "Composite AV Cable" || item.name.localizedCaseInsensitiveContains("Composite AV Cable")
        if isComposite {
            if seenCompositeAVCable {
                if let existingIdx = deduped.firstIndex(where: { $0.model == "A1258" || $0.catalogID == "Composite AV Cable" || $0.name.localizedCaseInsensitiveContains("Composite AV Cable") }) {
                    var winner = deduped[existingIdx]
                    if winner.notes == nil || winner.notes?.isEmpty == true { winner.notes = item.notes }
                    if winner.price == nil || winner.price?.isEmpty == true { winner.price = item.price }
                    if winner.purchaseDate == nil || winner.purchaseDate?.isEmpty == true { winner.purchaseDate = item.purchaseDate }
                    if winner.purchaseSource == nil || winner.purchaseSource?.isEmpty == true { winner.purchaseSource = item.purchaseSource }
                    deduped[existingIdx] = winner
                }
                continue
            }
            seenCompositeAVCable = true
            deduped.append(item)
            continue
        }

        // Apple Component AV Cable (A1259) 严格去重
        let isComponent = item.model == "A1259" || item.catalogID == "Component AV Cable" || item.name.localizedCaseInsensitiveContains("Component AV Cable")
        if isComponent {
            if seenComponentAVCable {
                if let existingIdx = deduped.firstIndex(where: { $0.model == "A1259" || $0.catalogID == "Component AV Cable" || $0.name.localizedCaseInsensitiveContains("Component AV Cable") }) {
                    var winner = deduped[existingIdx]
                    if winner.notes == nil || winner.notes?.isEmpty == true { winner.notes = item.notes }
                    if winner.price == nil || winner.price?.isEmpty == true { winner.price = item.price }
                    if winner.purchaseDate == nil || winner.purchaseDate?.isEmpty == true { winner.purchaseDate = item.purchaseDate }
                    if winner.purchaseSource == nil || winner.purchaseSource?.isEmpty == true { winner.purchaseSource = item.purchaseSource }
                    deduped[existingIdx] = winner
                }
                continue
            }
            seenComponentAVCable = true
            deduped.append(item)
            continue
        }

        if let sn = item.serialNumber, isUniqueHardwareSerial(sn) {
            if let existingIdx = seenSerials[sn] {
                var winner = deduped[existingIdx]
                if winner.customName == nil || winner.customName?.isEmpty == true { winner.customName = item.customName }
                if winner.lastCharged == nil || winner.lastCharged?.isEmpty == true { winner.lastCharged = item.lastCharged }
                if winner.battery == nil || winner.battery?.isEmpty == true { winner.battery = item.battery }
                if winner.color == nil || winner.color?.isEmpty == true { winner.color = item.color }
                if winner.notes == nil || winner.notes?.isEmpty == true { winner.notes = item.notes }
                deduped[existingIdx] = winner
                continue
            }
            seenSerials[sn] = deduped.count
        } else {
            // 对无序列号的配件与转接头（如 Lightning to 3.5mm A1749、USB-C to 3.5mm A2049 等）
            // 按 (catalogID ?? model ?? name) 深度去重，融合有效字段，杜绝历史多端同步产生的重复项
            let rootCat = itemRootCategory(item)
            let isAccessoryOrAdapter = rootCat == "配件" || rootCat == "Accessories" || item.category == "Adapters" || item.category == "Adapter" || item.category == "配件"
            if isAccessoryOrAdapter {
                let key = (item.catalogID ?? item.model ?? item.name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty {
                    if let existingIdx = seenNonSerialAccessories[key] {
                        var winner = deduped[existingIdx]
                        if winner.customName == nil || winner.customName?.isEmpty == true { winner.customName = item.customName }
                        if winner.lastCharged == nil || winner.lastCharged?.isEmpty == true { winner.lastCharged = item.lastCharged }
                        if winner.battery == nil || winner.battery?.isEmpty == true { winner.battery = item.battery }
                        if winner.color == nil || winner.color?.isEmpty == true { winner.color = item.color }
                        if winner.notes == nil || winner.notes?.isEmpty == true { winner.notes = item.notes }
                        if winner.price == nil || winner.price?.isEmpty == true { winner.price = item.price }
                        deduped[existingIdx] = winner
                        continue
                    }
                    seenNonSerialAccessories[key] = deduped.count
                }
            }
        }
        deduped.append(item)
    }

    // 严密保证未启用 AirTag 数量：总共 3 枚未启用（两枚 1 代带篆刻绝缘片 + 一枚 2 代带篆刻绝缘片）
    let unactivatedAirTags1stGen = deduped.filter {
        ($0.category == "AirTag" || $0.name.contains("AirTag")) &&
        $0.model == "A2187" &&
        ($0.isInUse == false || $0.battery?.contains("绝缘片") == true)
    }
    if unactivatedAirTags1stGen.count < 2 {
        let countNeeded = 2 - unactivatedAirTags1stGen.count
        for i in 1...countNeeded {
            let label = (unactivatedAirTags1stGen.count + i == 1) ? "01" : "02"
            let missing1stGen = CollectionItem(
                id: UUID().uuidString,
                name: "AirTag",
                category: "AirTag",
                productName: "AirTag",
                customName: "AirTag (带篆刻 · 绝缘片 \(label))",
                model: "A2187",
                catalogID: "AirTag-1",
                serialNumber: "HGFFM9ZEP0GV",
                battery: "CR2032 (已插绝缘片)",
                releaseYear: "2021",
                notes: "已插绝缘片 · 零耗电免维护 · 官网4件装 · 独立篆刻",
                isInUse: false,
                customCycleDays: 365
            )
            deduped.append(missing1stGen)
        }
    }

    let hasUnactivated2ndGen = deduped.contains {
        ($0.category == "AirTag" || $0.name.contains("AirTag")) &&
        $0.model == "A2937"
    }
    if !hasUnactivated2ndGen {
        let missing2ndGen = CollectionItem(
            id: UUID().uuidString,
            name: "AirTag (2nd generation)",
            category: "AirTag",
            productName: "AirTag (2nd generation)",
            customName: "AirTag 2 (带篆刻 · 绝缘片)",
            model: "A2937",
            catalogID: "afw2,4",
            serialNumber: "MG34DR213P",
            battery: "CR2032 (已插绝缘片)",
            releaseYear: "2026",
            notes: "已插绝缘片 · 零耗电免维护 · 2代带篆刻 · 官网订购",
            isInUse: false,
            customCycleDays: 365
        )
        deduped.append(missing2ndGen)
    }

    return deduped
}

/// 保存藏品列表到本地并向 Apple Watch 发布同步快照
func saveCollection(_ items: [CollectionItem]) {
    let localURL = collectionFileURL()
    guard let data = try? JSONEncoder().encode(items) else { return }
    try? data.write(to: localURL, options: .atomic)
    publishWatchSnapshot(items)
}

/// 线程安全的手表缩略图二进制缓存（杜绝每次保存或补电打卡时在主线程重复压缩 192+ 张图）
final class WatchThumbnailCache: @unchecked Sendable {
    static let shared = WatchThumbnailCache()
    private let cache = NSCache<NSString, NSData>()

    init() {
        cache.countLimit = 500
    }

    func get(_ key: String) -> Data? {
        cache.object(forKey: key as NSString) as Data?
    }

    func set(_ data: Data, for key: String) {
        cache.setObject(data as NSData, forKey: key as NSString)
    }
}

private let watchPublishQueue = DispatchQueue(label: "com.pomme.watchPublishQueue", qos: .utility)
private var watchPublishWorkItem: DispatchWorkItem?
private let watchPublishLock = NSLock()

/// 给 Apple Watch 和 Siri 生成精简快照（异步后台调度 + 0.35s 防抖 + 内存缩略图缓存，杜绝主线程阻塞与频繁通信）
func publishWatchSnapshot(_ items: [CollectionItem]) {
    watchPublishLock.lock()
    watchPublishWorkItem?.cancel()
    let workItem = DispatchWorkItem {
        let wishlistCount = decodeIDs(from: UserDefaults.standard.data(forKey: "wantedDeviceIDs") ?? Data()).count
        let watchItems = items.map { item in
            WatchItem(id: item.id, name: item.displayName, category: categoryTitle(itemRootCategory(item)),
                      year: item.releaseYear, color: item.color.map(appLocalized), serial: item.serialNumber,
                      model: item.model, processor: item.processor ?? catalogProcessor(for: item), storage: item.storage,
                      thumbnail: watchThumbnail(for: item))
        }
        let snapshot = PommeSnapshot(items: watchItems, wishlistCount: wishlistCount, generatedAt: Date())
        Task { @MainActor in
            PommeWatchBridge.shared.publish(snapshot)
        }
    }
    watchPublishWorkItem = workItem
    watchPublishLock.unlock()
    watchPublishQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
}

/// 解析藏品对应的清晰手表缩略图（多级候选回溯，保证硬件设备 100% 具备有效图片）
func watchThumbnail(for item: CollectionItem) -> Data? {
#if os(iOS)
    let cacheKey = "\(item.id)_\(item.colorLookupKey)_\(item.color ?? "")"
    if let cached = WatchThumbnailCache.shared.get(cacheKey) {
        return cached
    }

    let candidateNames: [String] = [
        item.artworkAssetName,
        deviceArtworkAssetName(item.colorLookupKey, color: item.color),
        deviceArtworkAssetName(item.colorLookupKey, color: nil),
        deviceArtworkAssetName(item.id, color: item.color),
        SearchCatalogArtworkIndex.names[item.colorLookupKey] ?? "",
        SearchCatalogArtworkIndex.namesByLegacyID[item.colorLookupKey] ?? ""
    ].filter { !$0.isEmpty }

    var resolvedImage: UIImage?
    for name in candidateNames {
        if let img = UIImage(named: name) {
            resolvedImage = img
            break
        }
    }

    // 若按 ID 未查到，从图鉴标准产品名称模糊匹配
    if resolvedImage == nil {
        let pName = item.resolvedProductName.lowercased()
        if let record = SearchCatalogArtworkIndex.records.first(where: {
            $0.name.lowercased() == pName || $0.searchText.lowercased().contains(pName)
        }), let img = UIImage(named: record.imageAssetName) {
            resolvedImage = img
        }
    }

    // 若仍未查到，从品类精选封面图兜底（确保真实硬件设备 100% 有图可显）
    if resolvedImage == nil {
        let rootCat = itemRootCategory(item)
        if let fallbackName = CatalogCategoryIndex.fallbackArtworkByCategory[rootCat],
           let img = UIImage(named: fallbackName) {
            resolvedImage = img
        }
    }

    guard let image = resolvedImage else { return nil }
    let side: CGFloat = 88 // 适合 Watch 屏幕（36~76pt）的轻巧高清比例
    let scale = min(side / image.size.width, side / image.size.height)
    let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let thumb = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
    // 压缩为约 2~3KB 的轻巧高质量 JPEG，便于立即随 WCSession 极速传输给手表
    let result = thumb.jpegData(compressionQuality: 0.72) ?? thumb.pngData()
    if let result {
        WatchThumbnailCache.shared.set(result, for: cacheKey)
    }
    return result
#else
    return nil
#endif
}

/// 兼容旧版单一参数调用
func watchThumbnail(_ assetName: String) -> Data? {
#if os(iOS)
    let cacheKey = "asset_\(assetName)"
    if let cached = WatchThumbnailCache.shared.get(cacheKey) {
        return cached
    }
    guard let image = UIImage(named: assetName) else { return nil }
    let side: CGFloat = 88
    let scale = min(side / image.size.width, side / image.size.height)
    let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let thumb = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    let result = thumb.jpegData(compressionQuality: 0.72) ?? thumb.pngData()
    if let result {
        WatchThumbnailCache.shared.set(result, for: cacheKey)
    }
    return result
#else
    return nil
#endif
}

/// 将图鉴中的原始记录聚合成展示产品（如 AirPods 多条左右耳及充电盒记录合并为一套）
func groupedCatalogProducts(_ records: [SearchCatalogRecord]) -> [CatalogDisplayProduct] {
    var groups: [String: [SearchCatalogRecord]] = [:]
    for record in records {
        let baseID = airPodsSetBaseID(record.id)
        groups[baseID.map { "airpods-set-\($0)" } ?? "single-\(record.id)", default: []].append(record)
    }

    return groups.values.map { group in
        let ordered = group.sorted { airPodsPartOrder($0.id) < airPodsPartOrder($1.id) }
        let first = ordered[0]
        let isSet = group.count > 1 && group.contains { $0.id.hasSuffix("-left") }
        let models = Array(Set(group.flatMap { $0.model.components(separatedBy: ", ") }.filter { !$0.isEmpty })).sorted()
        let title = isSet ? airPodsSetTitle(from: first.name) : first.name
        let images: [String]
        if isSet, let caseRecord = ordered.first(where: { $0.id.hasSuffix("-case") || $0.id.hasSuffix("-magsafe-case") }) {
            images = [caseRecord.imageAssetName]
        } else {
            images = Array(NSOrderedSet(array: group.map(\.imageAssetName))) as? [String] ?? [first.imageAssetName]
        }
        return CatalogDisplayProduct(
            id: first.id,
            name: title,
            category: isSet ? (first.category.contains("Beats") ? first.category : "AirPods") : first.category,
            model: models.joined(separator: " / "),
            year: first.year,
            records: ordered,
            artworkNames: images
        )
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// 快速图片资源查找索引
enum SearchCatalogArtworkIndex {
    static let records = loadSearchCatalog()

    static let names: [String: String] = {
        var dict = Dictionary(records.map { ($0.id, $0.imageAssetName) }, uniquingKeysWith: { first, _ in first })
        for record in records where !record.name.isEmpty && !record.imageAssetName.isEmpty {
            if dict[record.name] == nil {
                dict[record.name] = record.imageAssetName
            }
        }
        return dict
    }()

    static let namesByLegacyID: [String: String] = {
        let pairs = records.filter { !$0.legacyCatalogID.isEmpty }.map { ($0.legacyCatalogID, $0.imageAssetName) }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }()

    static let namesByModel: [String: String] = {
        var dict: [String: String] = [:]
        for record in records where !record.model.isEmpty && !record.imageAssetName.isEmpty {
            let models = record.model.components(separatedBy: CharacterSet(charactersIn: ",/ ")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for m in models {
                if dict[m] == nil {
                    dict[m] = record.imageAssetName
                }
            }
        }
        return dict
    }()

    static let colorsByLegacyID: [String: [String]] = {
        let grouped = Dictionary(grouping: records.filter { !$0.legacyCatalogID.isEmpty }, by: \.legacyCatalogID)
        return grouped.mapValues { matchingRecords in
            var colors: [String] = []
            for value in matchingRecords.flatMap({ $0.colors.components(separatedBy: ", ") }) where !value.isEmpty {
                if !colors.contains(value) { colors.append(value) }
            }
            return colors
        }
    }()
}

/// 快速产品与记录索引
enum SearchCatalogProductIndex {
    static let records = SearchCatalogArtworkIndex.records
    static let products = groupedCatalogProducts(records)
}

/// 百科分类快速统计与缓存索引（解决切换百科主线程卡顿问题）
enum CatalogCategoryIndex {
    static let defaultCategories: [String] = {
        Set(SearchCatalogProductIndex.records.map { catalogRootCategory($0.category, name: $0.name) })
            .filter { !$0.isEmpty }
            .sorted { categoryTitle($0).localizedStandardCompare(categoryTitle($1)) == .orderedAscending }
    }()

    static let recordsByCategory: [String: [SearchCatalogRecord]] = {
        Dictionary(grouping: SearchCatalogProductIndex.records, by: { catalogRootCategory($0.category, name: $0.name) })
    }()

    static let productsByCategory: [String: [CatalogDisplayProduct]] = {
        Dictionary(grouping: SearchCatalogProductIndex.products, by: { catalogRootCategory($0.category, name: $0.name) })
    }()

    static let productCountByCategory: [String: Int] = {
        productsByCategory.mapValues { $0.count }
    }()

    static let fallbackArtworkByCategory: [String: String] = {
        productsByCategory.compactMapValues { $0.first?.artworkNames.first }
    }()
}

/// CSV 导入匹配引擎索引
enum CatalogImportMatcher {
    static let productsByID: [String: CatalogDisplayProduct] = Dictionary(
        SearchCatalogProductIndex.products.map { ($0.catalogDevice.id, $0) }, uniquingKeysWith: { first, _ in first })

    static let shared: CSVCatalogMatcher = {
        let deviceNames = Dictionary(grouping: loadDevices(), by: \.id).mapValues { $0.map(\.name) }
        var aliases: [String: String] = [:]
        let candidates = SearchCatalogProductIndex.products.map { product -> CatalogMatchCandidate in
            let catalogID = product.catalogDevice.id
            aliases[product.id] = catalogID
            for record in product.records {
                aliases[record.id] = catalogID
                if !record.legacyCatalogID.isEmpty { aliases[record.legacyCatalogID] = catalogID }
            }
            return CatalogMatchCandidate(
                catalogID: catalogID,
                name: product.name,
                category: product.category,
                year: product.year,
                models: product.records.flatMap { CSVCatalogMatcher.aNumbers($0.model) },
                identifiers: product.records.flatMap { CSVCatalogMatcher.splitIdentifiers($0.identifiers) },
                aliases: deviceNames[catalogID] ?? []
            )
        }
        return CSVCatalogMatcher(candidates: candidates, extraIDAliases: aliases)
    }()
}

/// 产品型号标准名称查询缓存
enum CatalogProductNameIndex {
    static let names: [String: String] = {
        var names: [String: String] = [:]
        for product in SearchCatalogProductIndex.products {
            names[product.id] = product.name
            names[product.catalogDevice.id] = product.name
            for record in product.records where !record.legacyCatalogID.isEmpty {
                names[record.legacyCatalogID] = product.name
            }
        }
        return names
    }()
}

/// 处理器规格快速查询缓存
enum CatalogProcessorIndex {
    static let values: [String: String] = {
        var values: [String: String] = [:]
        for record in loadSearchCatalog() where !record.processor.isEmpty {
            values[record.id] = record.processor
            if !record.legacyCatalogID.isEmpty { values[record.legacyCatalogID] = record.processor }
        }
        return values
    }()
}

func catalogProcessor(for item: CollectionItem) -> String? {
    guard let catalogID = item.catalogID else { return nil }
    return CatalogProcessorIndex.values[catalogID]
}

func inferredRegionVersion(_ modelVersion: String?) -> String? {
    guard let modelVersion else { return nil }
    let suffix = String(modelVersion.suffix(4))
    return suffix.range(of: "^[A-Z]{2}/A$", options: .regularExpression) == nil ? nil : suffix
}
