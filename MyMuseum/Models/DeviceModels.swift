import Foundation

// MARK: - 设备与图鉴核心数据模型 (Device & Catalog Models)

/// 基础图鉴设备信息（对应 devices.json 中的条目）
struct Device: Codable, Identifiable {
    let id: String       // 唯一标识符：如 Mac-1、iPhone-3、HomeView-1 等
    let name: String     // 设备官方名称
    let model: String    // 设备硬件编号（如 A1176、A1203、A3380 等）
    let category: String // 原始分类名称
    let year: String     // 发售年份
    let color: String    // 默认或主打配色
}

/// 离线搜索目录中的单条记录（对应 search-catalog.json）
/// 包含较完整的硬件规格信息，用于快速全文检索与智能匹配
struct SearchCatalogRecord: Codable, Identifiable {
    let id: String              // 记录唯一标识符
    let name: String            // 设备名称
    let category: String        // 设备分类
    let model: String           // A 编号
    let identifiers: String     // 机型标识符（如 MacBookPro18,3, HomeView1,1 等）
    let year: String            // 发布年份
    let colors: String          // 配色列表（逗号分隔）
    let processor: String       // 芯片/处理器（如 M4, A18, S10 等）
    let legacyCatalogID: String // 旧版图鉴关联 ID（可为空）
    let searchText: String      // 用于全文匹配的预分词文本
    let imageAssetName: String  // 本地图片资源名称

    /// 转换为精简版 `Device` 对象
    var catalogDevice: Device {
        Device(
            id: legacyCatalogID.isEmpty ? id : legacyCatalogID,
            name: name,
            model: model,
            category: category,
            year: year,
            color: colors.components(separatedBy: ", ").first ?? ""
        )
    }
}

/// 图鉴聚合展示产品
/// 解决 AppleDB 数据中将部分同类部件（如 AirPods 左右耳和充电盒）拆散的问题，
/// 在 UI 展示和收藏时将它们聚合为一套完整的独立产品
struct CatalogDisplayProduct: Identifiable {
    let id: String                        // 主记录 ID
    let name: String                      // 产品显示名称
    let category: String                  // 一级或子级分类
    let model: String                     // A 编号（多型号时以斜杠拼接）
    let year: String                      // 发售年份
    let records: [SearchCatalogRecord]    // 聚合的底层记录集
    let artworkNames: [String]            // 封面图片资源名称集

    /// 是否为 AirPods 耳机套装（左右耳及盒子合并项）
    var isAirPodsSet: Bool {
        records.count > 1 && records.contains { $0.id.hasSuffix("-left") }
    }

    /// 聚合机型标识符列表
    var identifiers: String {
        Array(Set(records.flatMap { $0.identifiers.components(separatedBy: ", ") }.filter { !$0.isEmpty }))
            .sorted().joined(separator: " / ")
    }

    /// 聚合芯片处理器规格
    var processor: String {
        records.first(where: { !$0.processor.isEmpty })?.processor ?? ""
    }

    /// 转换为图鉴对应的精简版 `Device`
    var catalogDevice: Device {
        let legacyID = records.first(where: { !$0.legacyCatalogID.isEmpty })?.legacyCatalogID
            ?? (records.contains(where: { $0.id.hasPrefix("AirPodsPro1,1") }) ? "Airpods-4" : nil)
        return Device(
            id: legacyID ?? id,
            name: name,
            model: model,
            category: category,
            year: year,
            color: ""
        )
    }
}

/// 百科产品分组（用于子系列列表显示）
struct CatalogProductGroup: Identifiable {
    var id: String { title }
    let title: String
    let products: [CatalogDisplayProduct]
}

/// 用户已拥有藏品分组
struct OwnedCollectionGroup: Identifiable {
    var id: String { title }
    let title: String
    let items: [CollectionItem]
}

/// 首页我的藏品导航路由枚举
enum HomeNavigationRoute: Hashable {
    case category(String)
    case branch(String, String)
    case family(String, String?, String)
    case ownedItem(String)
    case catalogDevice(String)
    case dailyDrivers
    case batteryMaintenance
}
