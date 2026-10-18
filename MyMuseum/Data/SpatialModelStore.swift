//
//  SpatialModelStore.swift
//  Pomme
//
//  空间 AR 设备模型仓库与摆放状态管理 (Spatial AR Model Store & Scene Manager)
//  支持 Vision Pro 原生空间摆放、品类与颜色标签归并、RealityKit 交互、真机尺寸比例与资产索引。
//

import SwiftUI
import RealityKit
import simd

// MARK: - AR 设备单文件模型数据定义
struct ARDeviceItem: Identifiable, Hashable, Codable {
    var id: String { fileName }
    let fileName: String
    let relativePath: String
    let category: String
    let fileSizeMB: Double
    let source: String
    let matchedCatalogID: String?
    let matchedProductName: String?
    let color: String?
    let year: String?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case relativePath = "relative_path"
        case category
        case fileSizeMB = "file_size_mb"
        case source
        case matchedCatalogID = "matched_catalog_id"
        case matchedProductName = "matched_product_name"
        case color
        case year
        case confidence
    }

    /// 显示名称
    var displayName: String {
        if let name = matchedProductName, !name.isEmpty {
            return name
        }
        let raw = (fileName as NSString).deletingPathExtension
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// 显示分类
    var displayCategory: String {
        if category == "Home" || category == "HomePod" { return "Home" }
        if category == "Vision" { return "Vision Pro" }
        return category.isEmpty ? "Other" : category
    }

    /// 规范化颜色标签（英文，如 Silver, Midnight, Sierra Blue 等）
    var colorLabel: String? {
        guard let color, !color.isEmpty else { return nil }
        return deviceColorLabel(color)
    }

    /// 解析本地可加载的模型文件 URL
    var resolvedURL: URL? {
        let baseName = (fileName as NSString).deletingPathExtension
        
        // 1. App Bundle 根目录 (Xcode 同步文件夹产物)
        if let bundleURL = Bundle.main.url(forResource: baseName, withExtension: "usdz") {
            return bundleURL
        }
        if let fullSubURL = Bundle.main.url(forResource: fileName, withExtension: nil) {
            return fullSubURL
        }
        
        // 2. App Bundle ARModels 子目录
        if let subURL = Bundle.main.url(forResource: baseName, withExtension: "usdz", subdirectory: "ARModels") {
            return subURL
        }
        if let fullSubURL = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "ARModels") {
            return fullSubURL
        }
        
        // 3. 检查 Bundle 绝对路径拼接
        let directBundlePath = Bundle.main.bundleURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: directBundlePath.path) {
            return directBundlePath
        }
        let directSubBundlePath = Bundle.main.bundleURL.appendingPathComponent("ARModels").appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: directSubBundlePath.path) {
            return directSubBundlePath
        }

        // 4. 沙盒 Application Support 与 Documents 目录兜底（支持未来模型按需动态下载与离线缓存）
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ARModels").appendingPathComponent(fileName)
        if let appSupportURL, FileManager.default.fileExists(atPath: appSupportURL.path) {
            return appSupportURL
        }

        let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ARModels").appendingPathComponent(fileName)
        if let docURL, FileManager.default.fileExists(atPath: docURL.path) {
            return docURL
        }

        #if DEBUG
        if let envBase = ProcessInfo.processInfo.environment["AR_MODELS_PATH"] {
            let envURL = URL(fileURLWithPath: envBase).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: envURL.path) {
                return envURL
            }
        }
        #endif

        return nil
    }

    /// 当前环境是否可加载该模型
    var isAvailable: Bool {
        resolvedURL != nil
    }
}

// MARK: - AR 产品聚合实体（将同款设备的不同颜色收拢归类为一个产品卡片，附带颜色标签列表）
struct ARProductGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let category: String
    let year: String?
    let catalogID: String?
    var variants: [ARDeviceItem]

    /// 默认显示的变体
    var defaultVariant: ARDeviceItem {
        variants.first(where: { $0.isAvailable }) ?? variants.first!
    }

    /// 该产品所有可用的颜色标签列表（按规范颜色去重）
    var availableColors: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for v in variants {
            let col = v.colorLabel ?? (v.color?.isEmpty == false ? v.color! : "Standard")
            if !seen.contains(col) {
                seen.insert(col)
                result.append(col)
            }
        }
        return result
    }

    /// 根据颜色标签获取对应的 3D 模型
    func variant(forColor color: String) -> ARDeviceItem? {
        variants.first { v in
            let col = v.colorLabel ?? (v.color?.isEmpty == false ? v.color! : "Standard")
            return col == color || deviceColorToken(col) == deviceColorToken(color)
        } ?? variants.first
    }
}

// MARK: - 空间中已摆放的设备状态
@Observable
final class PlacedSpatialDevice: Identifiable {
    let id: UUID
    let modelItem: ARDeviceItem
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var scale: Float
    var isSelected: Bool
    var showInfoBadge: Bool
    var showPedestal: Bool
    var isCollapsed: Bool
    var boundingHeight: Float
    var isLocked: Bool
    var isYAxisLocked: Bool

    init(
        id: UUID = UUID(),
        modelItem: ARDeviceItem,
        position: SIMD3<Float> = SIMD3<Float>(0, 1.05, -0.8),
        rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
        scale: Float = 1.0,
        isSelected: Bool = false,
        showInfoBadge: Bool = true,
        showPedestal: Bool = true,
        isCollapsed: Bool = false,
        boundingHeight: Float = 0.22,
        isLocked: Bool = false,
        isYAxisLocked: Bool = false
    ) {
        self.id = id
        self.modelItem = modelItem
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.isSelected = isSelected
        self.showInfoBadge = showInfoBadge
        self.showPedestal = showPedestal
        self.isCollapsed = isCollapsed
        self.boundingHeight = boundingHeight
        self.isLocked = isLocked
        self.isYAxisLocked = isYAxisLocked
    }

    /// 切换单台设备的完全手势锁定状态（完全冻结，防止任何手势误操作、位移或扭动）
    func toggleLock() {
        isLocked.toggle()
    }

    /// 切换单台设备的 Y 轴防漂移锁定
    func toggleYAxisLock() {
        isYAxisLocked.toggle()
    }

    /// 切换单台设备的信息卡片折叠/展开状态
    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    /// 就地面对当前视点/VP位置快速回正（保持当前 3D 位置不变，消除所有倾斜与侧倾，正面水平旋转朝向用户）
    func faceUserInPlace() {
        let toUser = SIMD3<Float>(-position.x, 0, -position.z)
        let horizontalDist = sqrt(toUser.x * toUser.x + toUser.z * toUser.z)
        if horizontalDist > 0.001 {
            let angle = atan2(toUser.x, toUser.z)
            rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        } else {
            rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    /// 上下俯仰旋转（Pitch，绕本地 X 轴旋转指定角度，正数向上仰、负数向下俯）
    func tilt(degrees: Float) {
        let radians = degrees * .pi / 180.0
        let pitchRot = simd_quatf(angle: radians, axis: SIMD3<Float>(1, 0, 0))
        rotation = simd_mul(rotation, pitchRot)
    }

    /// 水平左右旋转（Yaw，绕本地 Y 轴旋转指定角度）
    func rotateYaw(degrees: Float) {
        let radians = degrees * .pi / 180.0
        let yawRot = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
        rotation = simd_mul(yawRot, rotation)
    }

    /// 重置方向与姿态（归正朝前）
    func resetOrientation() {
        rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    }

    /// 切换单台设备的微光展台底座
    func togglePedestal() {
        showPedestal.toggle()
    }
}

// MARK: - 空间展厅与模型全局状态管理器
@Observable
final class SpatialMuseumStore {
    static let shared = SpatialMuseumStore()

    var allModels: [ARDeviceItem] = []
    var selectedCategory: String = "All"
    var placedDevices: [PlacedSpatialDevice] = []
    var selectedDeviceID: UUID?
    var isImmersiveActive: Bool = false
    var showMuseumPedestals: Bool = true // 是否在每台设备下显示苹果微光展台底座
    var showAllBadges: Bool = true // 全局是否显示浮空控制菜单与标签
    var isAllLocked: Bool = false // 全局总锁：一键冻结所有模型的手势交互，防止误操作
    var isYAxisLocked: Bool = false // 初始不锁 Y 轴高度（允许自由 3D 拖动，用户可在控制栏或菜单自主锁定）

    // 当前选中的产品组 ID 与各产品的所选颜色映射
    var selectedProductID: String?
    var selectedColorForProduct: [String: String] = [:]

    var currentSelectedProduct: ARProductGroup? {
        if let id = selectedProductID, let matched = groupedProducts.first(where: { $0.id == id }) {
            return matched
        }
        // 优先默认选择核心旗舰设备，而非固定的 AirTag
        return groupedProducts.first(where: { $0.name.contains("iPhone") }) ?? groupedProducts.first
    }

    static let standardCategoryOrder = [
        "All", "iPhone", "Mac", "iPad", "Watch", "AirPods", "Home", "Display", "Vision Pro", "Accessories", "Apple Park"
    ]

    var categories: [String] {
        let existing = Set(allModels.map(\.displayCategory))
        var ordered: [String] = []
        for cat in Self.standardCategoryOrder {
            if cat == "All" || existing.contains(cat) {
                ordered.append(cat)
            }
        }
        for cat in existing.sorted() {
            if !ordered.contains(cat) {
                ordered.append(cat)
            }
        }
        return ordered
    }

    /// 将所有单文件模型按产品线（Product Group）归类整理
    var groupedProducts: [ARProductGroup] {
        let filtered = allModels.filter { item in
            selectedCategory == "All" || item.displayCategory == selectedCategory
        }

        var groups: [String: [ARDeviceItem]] = [:]
        var order: [String] = []

        for item in filtered {
            let key = item.matchedProductName ?? item.displayName
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(item)
        }

        return order.compactMap { key in
            guard let items = groups[key], !items.isEmpty else { return nil }
            // 对每款产品的颜色标签做规范化去重
            var uniqueVariants: [ARDeviceItem] = []
            var seenColors = Set<String>()
            for it in items {
                let col = it.colorLabel ?? "Standard"
                if !seenColors.contains(col) {
                    seenColors.insert(col)
                    uniqueVariants.append(it)
                }
            }
            let first = items[0]
            return ARProductGroup(
                name: key,
                category: first.displayCategory,
                year: first.year,
                catalogID: first.matchedCatalogID,
                variants: uniqueVariants
            )
        }
    }

    init() {
        loadMapping()
    }

    /// 获取某款产品当前选中的颜色变体
    func activeVariant(for product: ARProductGroup) -> ARDeviceItem {
        if let savedColor = selectedColorForProduct[product.name],
           let matched = product.variant(forColor: savedColor) {
            return matched
        }
        return product.defaultVariant
    }

    /// 为某款产品切换颜色
    func selectColor(_ color: String, for product: ARProductGroup) {
        selectedColorForProduct[product.name] = color
    }

    /// 从本地映射配置中加载所有 3D 模型元数据
    func loadMapping() {
        var data: Data?
        if let bundleURL = Bundle.main.url(forResource: "ar_model_catalog_mapping", withExtension: "json") {
            data = try? Data(contentsOf: bundleURL)
        }
        if data == nil,
           let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("ar_model_catalog_mapping.json"),
           FileManager.default.fileExists(atPath: appSupportURL.path) {
            data = try? Data(contentsOf: appSupportURL)
        }
        if data == nil,
           let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("ar_model_catalog_mapping.json"),
           FileManager.default.fileExists(atPath: docURL.path) {
            data = try? Data(contentsOf: docURL)
        }
        #if DEBUG
        if data == nil, let envPath = ProcessInfo.processInfo.environment["AR_MAPPING_PATH"], FileManager.default.fileExists(atPath: envPath) {
            data = try? Data(contentsOf: URL(fileURLWithPath: envPath))
        }
        #endif

        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mappedArray = json["mapped_models"] as? [[String: Any]] else {
            return
        }

        var loaded: [ARDeviceItem] = []
        for dict in mappedArray {
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
               let item = try? JSONDecoder().decode(ARDeviceItem.self, from: jsonData) {
                loaded.append(item)
            }
        }
        self.allModels = loaded
    }

    /// 检查指定设备是否拥有关联的 3D AR 模型
    func hasModel(for deviceID: String, name: String? = nil) -> Bool {
        model(for: deviceID, name: name, color: nil) != nil
    }

    /// 根据设备硬件标识符（如 RealityDevice14,1, iPhone14,2）、产品名称与颜色多级智能检索对应的 AR 模型
    func model(for deviceID: String, name: String? = nil, color: String? = nil) -> ARDeviceItem? {
        let cleanID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanColor = (color ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 排除保护壳、表带、挂绳等单纯配件对整机模型的误匹配（除非配件自身专属）
        let lowerName = cleanName.lowercased()
        let isAccessoryNoise = lowerName.contains("case with magsafe") ||
                               lowerName.contains("leather case") ||
                               lowerName.contains("silicone case") ||
                               lowerName.contains("clear case") ||
                               lowerName.contains("smart folio") ||
                               lowerName.contains("sport band") ||
                               lowerName.contains("sport loop") ||
                               lowerName.contains("milanese loop") ||
                               lowerName.contains("link bracelet") ||
                               lowerName.contains("polishing cloth") ||
                               lowerName.contains("power adapter")
        if isAccessoryNoise && !cleanID.lowercased().contains("case") {
            return nil
        }

        // 1. 优先按精确或前缀 Catalog ID 查找候选项
        var candidates: [ARDeviceItem] = []
        let lowerID = cleanID.lowercased()

        if !cleanID.isEmpty {
            candidates = allModels.filter { item in
                guard let catID = item.matchedCatalogID?.lowercased(), !catID.isEmpty else { return false }
                return catID == lowerID || lowerID.hasPrefix(catID) || catID.hasPrefix(lowerID)
            }
        }

        // 2. 若未找到，按品类/硬件家族模式匹配查找候选项
        if candidates.isEmpty {
            candidates = findCandidatesByFamily(id: cleanID, name: cleanName)
        }

        // 3. 若仍未找到，按产品名称或文件名模糊搜索
        if candidates.isEmpty && !cleanName.isEmpty {
            candidates = allModels.filter { item in
                if let pName = item.matchedProductName?.lowercased(), !pName.isEmpty {
                    if lowerName.contains(pName) || pName.contains(lowerName) {
                        return true
                    }
                }
                let cleanFileName = item.fileName.replacingOccurrences(of: "_", with: " ").lowercased()
                return cleanFileName.contains(lowerName) || lowerName.contains(cleanFileName)
            }
        }

        guard !candidates.isEmpty else { return nil }

        // 4. 若传入了颜色信息，在候选中挑选颜色最匹配的变体
        if !cleanColor.isEmpty {
            let targetLabel = deviceColorLabel(cleanColor).lowercased()
            let targetToken = (deviceColorToken(cleanColor) ?? "").lowercased()

            // 4a. 严格匹配 colorLabel
            if let matched = candidates.first(where: {
                if let l = $0.colorLabel?.lowercased(), !l.isEmpty {
                    return l == targetLabel || l.contains(targetLabel) || targetLabel.contains(l)
                }
                return false
            }) {
                return matched
            }

            // 4b. 匹配 item.color 原文或包含关系
            if let matched = candidates.first(where: {
                if let c = $0.color?.lowercased(), !c.isEmpty {
                    return c.contains(cleanColor.lowercased()) || cleanColor.lowercased().contains(c)
                }
                return false
            }) {
                return matched
            }

            // 4c. 匹配文件名中包含的颜色关键词
            if !targetToken.isEmpty, let matched = candidates.first(where: {
                $0.fileName.lowercased().contains(targetToken)
            }) {
                return matched
            }
        }

        // 默认返回候选变体中的第一个可用模型
        return candidates.first(where: { $0.isAvailable }) ?? candidates.first
    }

    /// 单参数快捷检索兜底（兼容旧调用）
    func model(for deviceIDOrName: String) -> ARDeviceItem? {
        model(for: deviceIDOrName, name: deviceIDOrName, color: nil)
    }

    private func findCandidatesByFamily(id: String, name: String) -> [ARDeviceItem] {
        let full = "\(id) \(name)".lowercased()

        // 1. Vision Pro / Headset
        if full.contains("realitydevice") || full.contains("vision pro") {
            return allModels.filter { $0.fileName.contains("vision_pro") || $0.matchedProductName == "Vision Pro" }
        }

        // 2. Apple Watch Families
        if full.contains("ultra") {
            return allModels.filter { $0.fileName.contains("watch_ultra") }
        }
        if full.contains("series 8") || ["watch6,14", "watch6,15", "watch6,16", "watch6,17"].contains(id.lowercased()) {
            return allModels.filter { $0.fileName.contains("watch_s8") }
        }
        if full.contains("series 7") || ["watch6,6", "watch6,7", "watch6,8", "watch6,9"].contains(id.lowercased()) {
            return allModels.filter { $0.fileName.contains("watch_s7") }
        }
        if full.contains("series 3") || id.lowercased().hasPrefix("watch3,") {
            return allModels.filter { $0.fileName.contains("apple-watch-series-3") }
        }
        if full.contains("watch se") || id.lowercased().hasPrefix("watch5,") || (id.lowercased().hasPrefix("watch6,1") && !["watch6,14","watch6,15","watch6,16","watch6,17","watch6,18"].contains(id.lowercased())) {
            return allModels.filter { $0.fileName.contains("watch_se") }
        }

        // 3. iPhone Families
        if full.contains("iphone duo") || full.contains("duo") || id.lowercased() == "iphone19,4" {
            return allModels.filter { $0.fileName.contains("iPhone_Duo") }
        }
        if full.contains("iphone air") || id.lowercased() == "iphone18,4" {
            return allModels.filter { $0.fileName.contains("iphone-air") }
        }
        if full.contains("iphone 17 pro") || full.contains("iphone 18") || id.lowercased().hasPrefix("iphone18,1") || id.lowercased().hasPrefix("iphone18,2") || id.lowercased() == "iphone-x-5" {
            return allModels.filter { $0.fileName.localizedCaseInsensitiveContains("17_pro_max") }
        }
        if full.contains("iphone 17") || id.lowercased() == "iphone18,3" {
            return allModels.filter { $0.fileName.contains("iphone-17") }
        }
        if full.contains("iphone 14 pro max") || id.lowercased() == "iphone15,3" {
            return allModels.filter { $0.fileName.contains("iphone_14_pro_max") }
        }
        if (full.contains("iphone 14 pro") && !full.contains("max")) || id.lowercased() == "iphone15,2" {
            return allModels.filter { $0.fileName.contains("iphone_14_pro_") }
        }
        if full.contains("iphone 14 plus") || id.lowercased() == "iphone14,8" {
            return allModels.filter { $0.fileName.contains("iphone_14_plus") }
        }
        if (full.contains("iphone 14") && !full.contains("pro") && !full.contains("plus")) || id.lowercased() == "iphone14,7" {
            return allModels.filter { $0.fileName.contains("iphone_14_") && !$0.fileName.contains("pro") && !$0.fileName.contains("plus") }
        }
        if full.contains("iphone 13 pro max") || id.lowercased() == "iphone14,3" {
            return allModels.filter { $0.fileName.contains("iphone_13_pro_max") }
        }
        if (full.contains("iphone 13 pro") && !full.contains("max")) || id.lowercased() == "iphone14,2" {
            return allModels.filter { $0.fileName.contains("iphone_13_pro_") }
        }
        if full.contains("iphone 13 mini") || id.lowercased() == "iphone14,4" {
            return allModels.filter { $0.fileName.contains("iphone_13_mini") }
        }
        if (full.contains("iphone 13") && !full.contains("pro") && !full.contains("mini")) || id.lowercased() == "iphone14,5" {
            return allModels.filter { $0.fileName.contains("iphone_13_") && !$0.fileName.contains("pro") && !$0.fileName.contains("mini") }
        }
        if full.contains("iphone 12 mini") || id.lowercased() == "iphone13,1" {
            return allModels.filter { $0.fileName.contains("iphone_12_mini") }
        }
        if full.contains("iphone 12") || id.lowercased() == "iphone13,2" {
            return allModels.filter { $0.fileName.contains("iphone_12") }
        }
        if full.contains("iphone se") || ["iphone14,6", "iphone12,8", "iphone8,4"].contains(id.lowercased()) {
            return allModels.filter { $0.fileName.contains("iphone_se") }
        }

        // 4. iPad Families
        if (full.contains("ipad pro") && (full.contains("m4") || full.contains("m5"))) || id.lowercased().hasPrefix("ipad16,") || id.lowercased().hasPrefix("ipad17,") {
            return allModels.filter { $0.fileName.contains("ipad_pro_m4") }
        }
        if full.contains("ipad pro 11") || id.lowercased().hasPrefix("ipad13,4") || id.lowercased().hasPrefix("ipad13,5") || id.lowercased().hasPrefix("ipad13,6") || id.lowercased().hasPrefix("ipad13,7") || id.lowercased().hasPrefix("ipad14,3") || id.lowercased().hasPrefix("ipad14,4") {
            return allModels.filter { $0.fileName.contains("ipad_pro_11in") }
        }
        if full.contains("ipad pro 12.9") || id.lowercased().hasPrefix("ipad13,8") || id.lowercased().hasPrefix("ipad13,9") || id.lowercased().hasPrefix("ipad13,10") || id.lowercased().hasPrefix("ipad13,11") || id.lowercased().hasPrefix("ipad14,5") || id.lowercased().hasPrefix("ipad14,6") {
            return allModels.filter { $0.fileName.contains("ipad_pro_12_9") }
        }
        if (full.contains("ipad air") && (full.contains("m2") || full.contains("m3") || full.contains("13-inch") || full.contains("11-inch"))) || id.lowercased().hasPrefix("ipad14,8") || id.lowercased().hasPrefix("ipad14,9") || id.lowercased().hasPrefix("ipad14,10") || id.lowercased().hasPrefix("ipad14,11") || id.lowercased().hasPrefix("ipad15,") {
            return allModels.filter { $0.fileName.contains("ipad_air_m2") }
        }
        if full.contains("ipad air") || id.lowercased().hasPrefix("ipad13,1") || id.lowercased().hasPrefix("ipad13,2") || id.lowercased().hasPrefix("ipad13,16") || id.lowercased().hasPrefix("ipad13,17") {
            return allModels.filter { $0.fileName.contains("ipad_air_purple") || $0.fileName.contains("ipad_air_ios13") }
        }
        if full.contains("ipad (10th") || id.lowercased().hasPrefix("ipad13,18") || id.lowercased().hasPrefix("ipad13,19") {
            return allModels.filter { $0.fileName.contains("ipad_10thgen") }
        }
        if full.contains("ipad (9th") || id.lowercased().hasPrefix("ipad12,1") || id.lowercased().hasPrefix("ipad12,2") {
            return allModels.filter { $0.fileName.contains("ipad_10.2") }
        }
        if full.contains("ipad mini") || id.lowercased().hasPrefix("ipad14,1") || id.lowercased().hasPrefix("ipad14,2") || id.lowercased().hasPrefix("ipad16,1") || id.lowercased().hasPrefix("ipad16,2") {
            return allModels.filter { $0.fileName.contains("ipad_mini") }
        }

        // 5. Mac Families
        if full.contains("macbook air 15") || full.contains("macbook air (15-inch") || id.lowercased() == "mac14,15" || id.lowercased() == "mac15,13" {
            return allModels.filter { $0.fileName.contains("macbook_air_15in") }
        }
        if (full.contains("macbook air") && (full.contains("m2") || full.contains("m3"))) || id.lowercased() == "mac14,2" || id.lowercased() == "mac15,12" {
            return allModels.filter { $0.fileName.contains("macbook_air_13in") }
        }
        if (full.contains("macbook air") && full.contains("m1")) || id.lowercased() == "macbookair10,1" {
            return allModels.filter { $0.fileName.contains("macbook_air_m1") }
        }
        if full.contains("macbook pro 14") || full.contains("macbook pro (14-inch") || id.lowercased().hasPrefix("macbookpro18,3") || id.lowercased().hasPrefix("macbookpro18,4") || id.lowercased() == "mac14,9" || id.lowercased() == "mac14,10" || id.lowercased().hasPrefix("mac15,3") || id.lowercased().hasPrefix("mac15,6") {
            return allModels.filter { $0.fileName.contains("macbook_pro_14") }
        }
        if full.contains("macbook pro 16") || full.contains("macbook pro (16-inch") || id.lowercased().hasPrefix("macbookpro18,1") || id.lowercased().hasPrefix("macbookpro18,2") || id.lowercased() == "mac14,5" || id.lowercased() == "mac14,6" {
            return allModels.filter { $0.fileName.contains("macbook_pro_16") }
        }
        if (full.contains("macbook pro 13") && full.contains("m1")) || full.contains("macbook pro (13-inch, m1") || id.lowercased() == "macbookpro17,1" {
            return allModels.filter { $0.fileName.contains("macbook_pro_13in") }
        }

        if full.contains("imac") && (full.contains("24-inch") || full.contains("24") || full.contains("m3") || full.contains("m4") || id.lowercased().hasPrefix("imac21,") || id.lowercased() == "mac15,4" || id.lowercased() == "mac15,5") {
            return allModels.filter { $0.fileName.contains("imac_m4") || $0.fileName.contains("imac_24in") || $0.fileName.contains("imac24_") }
        }
        if full.contains("mac studio") || id.lowercased().hasPrefix("mac13,") || id.lowercased() == "mac14,13" || id.lowercased() == "mac14,14" {
            return allModels.filter { $0.fileName.contains("mac_studio") && !$0.fileName.contains("display") }
        }
        if full.contains("mac mini") || id.lowercased().hasPrefix("macmini") || id.lowercased() == "mac14,3" || id.lowercased() == "mac14,12" {
            return allModels.filter { $0.fileName.contains("mac_mini") }
        }
        if full.contains("studio display") || id.lowercased() == "studiodisplay" {
            return allModels.filter { $0.fileName.contains("studio_display") }
        }
        if full.contains("pro display xdr") || id.lowercased() == "prodisplayxdr" {
            return allModels.filter { $0.fileName.contains("apple_pro_display_xdr") || $0.fileName.contains("mac_studio_display_xdr") }
        }
        if full.contains("mac pro") || id.lowercased().hasPrefix("macpro") || id.lowercased() == "mac14,8" || full.contains("a2786") || full.contains("a1991") || full.contains("a991") {
            return allModels.filter { $0.fileName.contains("mac_pro_tower") }
        }

        // 6. Audio & Accessories Families
        if full.contains("airpods max") || id.lowercased().hasPrefix("airpodsmax") {
            if full.contains("usb-c") || full.contains("max 2") || id.lowercased().contains("usbc") || id.lowercased() == "airpodsmax1,2" {
                return allModels.filter { $0.fileName.contains("airpods_max_") && $0.fileName.contains("usbc") }
            } else {
                return allModels.filter { $0.fileName.contains("airpods_max_") && !$0.fileName.contains("usbc") }
            }
        }
        if (full.contains("airpods pro") && (full.contains("2nd") || full.contains(" 2"))) || id.lowercased().hasPrefix("airpodspro1,2") {
            return allModels.filter { $0.fileName.contains("airpods_pro_2") }
        }
        if full.contains("airpods pro") || id.lowercased().hasPrefix("airpodspro1,1") {
            return allModels.filter { $0.fileName.contains("airpods_pro") && !$0.fileName.contains("airpods_pro_2") }
        }
        if full.contains("airpods 4") || id.lowercased().hasPrefix("airpods1,4") || id.lowercased().hasPrefix("airpods1,5") {
            return allModels.filter { $0.fileName.contains("airpods_4") }
        }
        if (full.contains("airpods") && (full.contains("3rd") || full.contains(" 3"))) || id.lowercased().hasPrefix("airpods1,3") {
            return allModels.filter { $0.fileName.contains("airpods_magsafe") || $0.fileName.contains("gen3") }
        }
        if full.contains("homepod (2nd") || full.contains("homepod 2") || id.lowercased() == "audioaccessory6,1" {
            return allModels.filter { $0.fileName.contains("homepod_2ndgen") }
        }
        if full.contains("homepod mini") || id.lowercased() == "audioaccessory5,1" || id.lowercased() == "homepod-mini-2" {
            return allModels.filter { $0.fileName.contains("homepod_mini") }
        }
        if full.contains("homeview") || id.lowercased().contains("homeview") {
            return allModels.filter { $0.fileName.contains("apple-homeview") || $0.fileName.contains("homeview") }
        }
        if full.contains("airtag") || id.lowercased() == "airtag1,1" || id.lowercased() == "afw2,4" {
            return allModels.filter { $0.fileName.contains("airtag") }
        }
        if full.contains("siri remote") || id.lowercased().hasPrefix("appletvremote") {
            return allModels.filter { $0.fileName.contains("siriremote") }
        }
        if full.contains("pencil") || id.lowercased().contains("pencil") {
            return allModels.filter { $0.fileName.contains("Apple_Pencil") || $0.fileName.contains("apple_pencil") }
        }
        if full.contains("apple park") || full.contains("spaceship") || id.lowercased().contains("park") {
            return allModels.filter { $0.fileName.contains("APPLE_PARK") || $0.fileName.contains("apple_park") }
        }

        return []
    }

    /// 在空间中摆放/生成一台新设备（置于视线前方约 62 厘米、真实桌面高度 Y=0.88m，触手可及且绝不被窗口遮挡）
    func spawn(model: ARDeviceItem, customPosition: SIMD3<Float>? = nil) {
        let count = placedDevices.count
        let defaultPos: SIMD3<Float>
        if let customPosition {
            defaultPos = customPosition
        } else {
            // 在眼前约 0.62 米桌面高度微弧扇形展开（左右交错排列）
            let sign: Float = (count % 2 == 1) ? -1.0 : 1.0
            let step = Float((count + 1) / 2) * 0.28
            let x: Float = (count == 0) ? 0.0 : sign * step
            let z: Float = -0.62 - abs(x) * 0.08 // 眼前 62 厘米，手伸出去即在掌握中
            let y: Float = 0.88 // 真实物理桌面视平线高度（0.85~0.90m）
            defaultPos = SIMD3<Float>(x, y, z)
        }

        let newDevice = PlacedSpatialDevice(
            modelItem: model,
            position: defaultPos,
            isSelected: true,
            isLocked: isAllLocked,
            isYAxisLocked: isYAxisLocked
        )
        // 取消其他设备的选中状态
        for dev in placedDevices { dev.isSelected = false }
        placedDevices.append(newDevice)
        selectedDeviceID = newDevice.id
    }

    /// 一键切换所有放置设备的全局完全锁定状态（总锁）
    func toggleAllLocked() {
        isAllLocked.toggle()
        for device in placedDevices {
            device.isLocked = isAllLocked
        }
    }

    /// 就地将设备面向用户视线快速回正（不改变当前物理位置坐标，消除倾斜）
    func reorientFacingUser(device: PlacedSpatialDevice) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            device.faceUserInPlace()
        }
    }

    /// 一键将空间中所有摆放的设备就地朝向当前用户视线快速回正
    func reorientAllFacingUser() {
        guard !placedDevices.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            for device in placedDevices {
                device.faceUserInPlace()
            }
        }
    }

    /// 一键将某台设备复位拉回到眼前桌面正中央（防止被甩远或误拖入天花板）
    func resetToDesk(device: PlacedSpatialDevice) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            device.position = SIMD3<Float>(0, 0.88, -0.62)
            device.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            device.scale = 1.0
        }
    }

    /// 移除单台设备
    func remove(id: UUID) {
        placedDevices.removeAll { $0.id == id }
        if selectedDeviceID == id {
            selectedDeviceID = placedDevices.last?.id
        }
    }

    /// 清空当前场景
    func clearAll() {
        placedDevices.removeAll()
        selectedDeviceID = nil
    }

    /// 自动排排坐：将当前空间中所有设备优雅对齐排列为一条博物馆陈列线（视线前 0.65 米桌面高度）
    func arrangeInShowcaseRow() {
        guard !placedDevices.isEmpty else { return }
        let total = placedDevices.count
        let spacing: Float = 0.32 // 32 厘米间距
        let startX: Float = -Float(total - 1) * spacing / 2.0

        for (index, dev) in placedDevices.enumerated() {
            let x = startX + Float(index) * spacing
            let z: Float = -0.65 + abs(x) * 0.06 // 桌面近处微内凹圆弧
            dev.position = SIMD3<Float>(x, 0.88, z)
            dev.rotation = simd_quatf(angle: -x * 0.22, axis: SIMD3<Float>(0, 1, 0))
            dev.scale = 1.0
        }
    }
}
