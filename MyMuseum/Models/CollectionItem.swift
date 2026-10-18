import Foundation

// MARK: - 用户个人实体藏品模型 (User Collection Item Model)

/// 对应用户拥有的真实实体藏品对象
/// `id` 标识这件实体藏品的独立身份证号（每次添加生成新 UUID）
/// `catalogID` 指向产品图鉴库中的对应型号
struct CollectionItem: Codable, Identifiable {
    var id: String
    var name: String
    var category: String
    var productName: String? = nil
    var customName: String?
    var model: String?
    var catalogID: String?
    var serialNumber: String?
    var modelVersion: String?
    var regionVersion: String? = nil
    var productIdentifier: String?
    var battery: String?
    var lastCharged: String?
    var screenSize: String?
    var processor: String?
    var memory: String?
    var storage: String?
    var graphics: String?
    var color: String?
    var system: String?
    var osVersion: String?
    var jailbreak: String?
    var account: String?
    var releaseYear: String?
    var repairs: String?
    var purchaseDate: String?
    var purchaseSource: String?
    var warrantyStatus: String? = nil
    var price: String?
    var notes: String?
    /// 是否为日常高频使用的“常用 / 在用”设备（天天使用，免受季度补电防饿死管理）
    var isInUse: Bool? = false
    /// 是否停止跟踪电池健康（适用于已损坏、不开机、仅保留尸体的硬件，可随时取消反悔）
    var isBatteryUntracked: Bool? = false
    /// 动态自适应调整的补电周期天数（动态管理：基于实际剩余电量智能增减；nil 表示沿用品类基准周期）
    var customCycleDays: Int? = nil
    /// 最后修改时间戳（用于多端自动同步与增量冲突决策）
    var updatedAt: Date? = nil

    /// 常用设备便捷读写计算属性
    var isDailyDriver: Bool {
        get { isInUse ?? false }
        set { isInUse = newValue }
    }

    /// 是否停止电池跟踪计算属性
    var batteryTrackingIgnored: Bool {
        get { isBatteryUntracked ?? false }
        set { isBatteryUntracked = newValue }
    }

    /// 解析后的产品标准全名（优先使用自定义指定全名，否则从图鉴索引查名称）
    var resolvedProductName: String {
        if let productName, !productName.isEmpty { return productName }
        return CatalogProductNameIndex.names[catalogID ?? ""] ?? name
    }

    /// 在列表中展示的标题（优先显示用户的自定义昵称，如“我的主力机”、“老乔黑苹果”）
    var displayName: String {
        if let customName {
            let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { return trimmedName }
        }
        return name
    }

    /// 收藏标识键（每件藏品使用专属独立 ID，避免同型号多台设备联动）
    var favoriteKey: String {
        id
    }

    /// 统一用于配色、图片回溯的型号查找键（依次降级：catalogID -> model -> name）
    var colorLookupKey: String {
        if let catalogID, !catalogID.isEmpty { return catalogID }
        if let model, !model.isEmpty { return model }
        return name
    }

    /// 外观渲染图资源名
    var artworkAssetName: String {
        let lookupID = colorLookupKey
        // 如果藏品指定了颜色且存在专属官方配色图，最高优先级展示配色图（支持官方配色图、限定版定制图等）
        if let color, !color.isEmpty {
            let colorAsset = deviceArtworkAssetName(lookupID, color: color)
            if imageAssetExists(colorAsset) && (colorAsset.contains("_color_") || colorAsset != deviceArtworkAssetName(lookupID, color: nil)) {
                return colorAsset
            }
        }
        // EarPods 有线耳机明确直达，避免误入 AirPods 充电盒逻辑
        if lookupID == "Airpods-x" || lookupID == "A3046" || resolvedProductName.lowercased().contains("earpod") {
            return deviceArtworkAssetName(lookupID, color: color)
        }
        // AirPods 与 Beats 耳机系列全系优先使用其专属充电盒外观渲染图
        if let airPodsCase = airPodsCaseArtwork(for: lookupID, name: resolvedProductName) {
            return airPodsCase
        }
        if let beatsCase = beatsCaseArtwork(for: lookupID, name: resolvedProductName) {
            return beatsCase
        }
        let directAsset = deviceArtworkAssetName(lookupID, color: color)
        if imageAssetExists(directAsset) {
            return directAsset
        }
        if let m = model, !m.isEmpty {
            let modelAsset = deviceArtworkAssetName(m, color: color)
            if imageAssetExists(modelAsset) { return modelAsset }
        }
        let prodAsset = deviceArtworkAssetName(resolvedProductName, color: color)
        if imageAssetExists(prodAsset) { return prodAsset }
        let nameAsset = deviceArtworkAssetName(name, color: color)
        if imageAssetExists(nameAsset) { return nameAsset }
        return directAsset
    }
}

// MARK: - Adapter 规格与年份智能校准 (修复历史表格列错位及颜色误作年份问题)
extension CollectionItem {
    static let adapterKnownReleaseYears: [String: String] = [
        "A1070": "2003", "A1184": "2006", "A1258": "2007", "A1259": "2007", "A1265": "2008", "A1357": "2010",
        "A1360": "2010", "A1401": "2012", "A1402": "2012", "A1436": "2012",
        "A1443": "2012", "A1540": "2015", "A1717": "2015", "A1718": "2016",
        "A1719": "2016", "A1720": "2018", "A1731": "2016", "A1882": "2018",
        "A2164": "2020", "A2166": "2019", "A2244": "2020", "A2452": "2021",
        "A2518": "2021", "A2571": "2022", "A2676": "2022", "A2743": "2023"
    ]

    mutating func calibrateAdapterMetadata() {
        let isAdapter = category == "Adapter" || category == "Adapters" ||
            (catalogID?.hasPrefix("Adapter-") == true) ||
            (model != nil && Self.adapterKnownReleaseYears[model!] != nil) ||
            name.contains("Adapter") || name.contains("Power Adapter") || name.contains("Lightning Dock")
        guard isAdapter else { return }

        let misplacedTags: Set<String> = ["白色", "透明", "夜光", "黑色", "蓝色", "未拆封", "有底座", "双面胶"]
        if let year = releaseYear, misplacedTags.contains(year) {
            if ["白色", "透明", "黑色", "蓝色"].contains(year) {
                if color == nil || color?.isEmpty == true {
                    color = (year == "黑色") ? "黑色" : "白色"
                }
            }
            if ["未拆封", "有底座", "双面胶", "夜光", "透明", "蓝色"].contains(year) {
                let noteTag = year == "透明" ? "透明外壳" : (year == "夜光" ? "夜光外壳" : (year == "蓝色" ? "蓝色保护套" : year))
                if let currentNotes = notes, !currentNotes.contains(year) && !currentNotes.contains(noteTag) {
                    notes = (currentNotes + " · " + noteTag).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if notes == nil || notes?.isEmpty == true {
                    notes = noteTag
                }
            }
        }

        if let m = model, let correctYear = Self.adapterKnownReleaseYears[m] {
            releaseYear = correctYear
        } else if releaseYear == nil || releaseYear?.isEmpty == true || !releaseYear!.allSatisfy({ $0.isNumber }) {
            if name.contains("World Travel") || catalogID == "Adapter-39" {
                releaseYear = "2003"
            } else {
                releaseYear = "2015"
            }
        }

        if color == nil || color?.isEmpty == true {
            color = (model == "A1731") ? "黑色" : (model == "A1717" ? (color ?? "香槟金") : "白色")
        }
    }
}

