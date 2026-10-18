import SwiftUI
import Combine

// MARK: - 分类层级模型 (Category Hierarchy Tier)

struct CategoryHierarchyTier: Identifiable, Hashable {
    var id: String { key }
    let level: Int        // 1: 大类, 2: 二层菜单, 3: 三层菜单, 4: 四层菜单
    let key: String       // 规范化索引标识（如 "Home", "MacBook Pro", "MagSafe Cases"）
    let title: String     // 面向用户的分类名称
    
    init(level: Int, key: String, title: String) {
        self.level = level
        self.key = key
        self.title = title
    }
}

// MARK: - 设备所属分类层级计算 (Hierarchy Extractor)

func categoryHierarchyTiers(name: String, category: String, product: CatalogDisplayProduct? = nil) -> [CategoryHierarchyTier] {
    var tiers: [CategoryHierarchyTier] = []
    
    // 1. 大类 (Root Category / Tier 1)
    let root = catalogRootCategory(category, name: name)
    let canonicalRoot = normalizeCategoryCoverKey(root)
    tiers.append(CategoryHierarchyTier(level: 1, key: canonicalRoot, title: canonicalRoot))
    
    let text = "\(category) \(name)".lowercased()
    
    // 2. 二级与更深层级 (Subcategories / Tier 2+)
    switch canonicalRoot {
    case "Mac":
        let branch: String
        if let product {
            branch = macProductBranch(for: product)
        } else {
            branch = ["macbook", "ibook", "powerbook"].contains(where: text.contains) ? "MacBook" : "Mac 台式机"
        }
        tiers.append(CategoryHierarchyTier(level: 2, key: branch, title: branch))
        
        let family = catalogFamilyName(name: name, category: category, root: "Mac")
        if family != branch && family != "其他 Mac" {
            tiers.append(CategoryHierarchyTier(level: 3, key: family, title: family))
        }
        
    case "Home":
        let sub: String
        if text.contains("homepod") {
            sub = "HomePod"
            tiers.append(CategoryHierarchyTier(level: 2, key: sub, title: sub))
            let hpSub = homepodSubfamily(name: name, category: category)
            tiers.append(CategoryHierarchyTier(level: 3, key: hpSub, title: hpSub))
        } else if text.contains("apple tv") || text.contains("appletv") {
            sub = "Apple TV"
            tiers.append(CategoryHierarchyTier(level: 2, key: sub, title: sub))
        } else if text.contains("homeview") {
            sub = "Apple HomeView"
            tiers.append(CategoryHierarchyTier(level: 2, key: sub, title: sub))
        } else {
            sub = "Smart Home Accessories"
            tiers.append(CategoryHierarchyTier(level: 2, key: sub, title: sub))
        }
        
    case "Input Devices":
        let sub: String
        if text.contains("pencil") {
            sub = "Apple Pencil"
        } else if text.contains("trackpad") || text.contains("触控板") {
            sub = "Trackpads"
        } else if text.contains("mouse") || text.contains("mice") || text.contains("鼠标") {
            sub = "Mice"
        } else {
            sub = "Keyboards"
        }
        tiers.append(CategoryHierarchyTier(level: 2, key: sub, title: sub))
        
    case "Accessories":
        let family = catalogFamilyName(name: name, category: category, root: "Accessories")
        tiers.append(CategoryHierarchyTier(level: 2, key: family, title: family))
        if family == "Cases & Storage" {
            let casesSub = caseSubfamily(name: name, category: category)
            tiers.append(CategoryHierarchyTier(level: 3, key: casesSub, title: casesSub))
        } else if family == "Power & Charging" {
            let powerSub = powerSubfamily(name: name, category: category)
            tiers.append(CategoryHierarchyTier(level: 3, key: powerSub, title: powerSub))
        }
        
    case "Beats":
        let family = catalogFamilyName(name: name, category: category, root: "Beats")
        tiers.append(CategoryHierarchyTier(level: 2, key: family, title: family))
        
    case "AirPods":
        let family = catalogFamilyName(name: name, category: category, root: "AirPods")
        tiers.append(CategoryHierarchyTier(level: 2, key: family, title: family))
        
    case "iPhone":
        let family = catalogFamilyName(name: name, category: category, root: "iPhone")
        tiers.append(CategoryHierarchyTier(level: 2, key: family, title: family))
        
    case "iPad":
        let family = catalogFamilyName(name: name, category: category, root: "iPad")
        tiers.append(CategoryHierarchyTier(level: 2, key: family, title: family))
        
    case "Watch", "Apple Watch":
        let family = catalogFamilyName(name: name, category: category, root: "Watch")
        tiers.append(CategoryHierarchyTier(level: 2, key: family, title: family))
        
    case "iPod":
        let family = catalogFamilyName(name: name, category: category, root: "iPod")
        tiers.append(CategoryHierarchyTier(level: 2, key: family, title: family))
        
    case "Displays":
        let family = catalogFamilyName(name: name, category: category, root: "显示器")
        tiers.append(CategoryHierarchyTier(level: 2, key: family, title: family))
        
    default:
        break
    }
    
    return tiers
}

// MARK: - 规范化分类键名

func normalizeCategoryCoverKey(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    switch trimmed {
    case "配件", "Accessories": return "Accessories"
    case "家庭", "Home", "Home Accessories", "家庭配件": return "Home"
    case "输入设备", "Input Devices": return "Input Devices"
    case "保护与收纳", "Cases & Storage": return "Cases & Storage"
    case "电源与充电", "Power & Charging": return "Power & Charging"
    case "连接与扩展", "Connectivity & Expansion": return "Connectivity & Expansion"
    case "显示器", "Displays", "Display": return "Displays"
    case "键盘", "Keyboards": return "Keyboards"
    case "鼠标", "Mice": return "Mice"
    case "触控板", "Trackpads": return "Trackpads"
    case "入耳式耳机", "Earbuds", "Beats Earbuds": return "Earbuds"
    case "头戴式耳机", "Headphones", "Beats Headphones": return "Headphones"
    case "扬声器", "Speakers", "Beats Speakers": return "Speakers"
    case "Beats 配件", "Beats Accessories": return "Beats Accessories"
    case "MagSafe 保护壳", "MagSafe Cases": return "MagSafe Cases"
    case "电池壳", "Battery Cases": return "Battery Cases"
    case "普通保护壳", "Cases": return "Cases"
    case "其他保护壳与收纳", "Other Cases & Storage": return "Other Cases & Storage"
    case "电源适配器", "Adapters", "Adapter": return "Adapters"
    case "线缆", "Cables", "Cable": return "Cables"
    case "iPhone 数字系列", "iPhone 标准系列", "iPhone Standard": return "iPhone Standard"
    case "iPhone Pro 系列", "iPhone Pro": return "iPhone Pro"
    case "iPhone Air 系列", "iPhone Air": return "iPhone Air"
    case "iPhone mini 系列", "iPhone mini": return "iPhone mini"
    case "iPhone Plus 系列", "iPhone Plus": return "iPhone Plus"
    case "iPhone Duo 系列", "iPhone Duo": return "iPhone Duo"
    case "iPhone SE 系列", "iPhone SE": return "iPhone SE"
    case "iPad 数字系列", "iPad 标准系列", "iPad Standard": return "iPad Standard"
    case "iPad Pro 系列", "iPad Pro": return "iPad Pro"
    case "iPad Air 系列", "iPad Air": return "iPad Air"
    case "iPad mini 系列", "iPad mini": return "iPad mini"
    case "Watch 数字系列", "Watch 标准系列", "Watch Standard", "Apple Watch 数字系列", "Apple Watch 标准系列", "Apple Watch Standard": return "Watch Standard"
    case "Watch SE 系列", "Watch SE", "Apple Watch SE 系列", "Apple Watch SE": return "Watch SE"
    case "Watch Ultra 系列", "Watch Ultra", "Apple Watch Ultra 系列", "Apple Watch Ultra": return "Watch Ultra"
    case "Watch", "Apple Watch", "Apple watch": return "Watch"
    case "AirPods 标准系列", "AirPods Standard", "Standard Series": return "AirPods Standard"
    case "HomePod 标准系列", "HomePod Standard": return "HomePod Standard"
    case "HomePod mini": return "HomePod mini"
    case "MacBook Standard", "MacBook 标准系列": return "MacBook Standard"
    case "Mac 台式机", "Mac Desktops", "Mac Desktop", "Desktops": return "Mac 台式机"
    case "Vision pro", "Vision Pro", "Apple Vision Pro", "Headset": return "Vision Pro"
    case "Airport", "AirPort": return "AirPort"
    case "Classic Apple Computer", "Apple 经典电脑", "Apple Series", "Classic": return "Classic"
    default: return trimmed
    }
}

// MARK: - 官方默认分类代表视觉图 (Default Category Covers)

let defaultCategoryCovers: [String: String] = [
    // 一级大类 (Root Categories)
    "Accessories": "catalog_ATVRemote1_4_280c2750",
    "AirPods": "device_Airpods-8",
    "AirPort": "device_Airport-2",
    "Vision Pro": "device_Vision pro-1",
    "Apple Vision Pro": "device_Vision pro-1",
    "Watch": "catalog_Watch7_14_351065e0",
    "Apple Watch": "catalog_Watch7_14_351065e0",
    "Beats": "catalog_BeatsStudioPro1_1_5b72630a",
    "Home": "device_HomePod-1",
    "Input Devices": "catalog_Magic_Keyboard_with_Numeric_Keypad_b235a5b4",
    "iPhone": "catalog_iPhone16_1_c00ebe62",
    "iPad": "catalog_iPad14_5_1da35057",
    "Mac": "catalog_Mac15_6_69928429",
    "iPod": "catalog_iPod_classic_a645b773",
    "Displays": "catalog_AppleDisplay2_1_dd935854",

    // 二级/三级分类 (Subcategories)
    "HomePod": "device_HomePod-1",
    "HomePod Standard": "device_HomePod-1",
    "HomePod mini": "device_HomePod-3",
    "Apple TV": "catalog_AppleTV14_1_72e871b7",
    "Apple HomeView": "catalog_HomeView1_1_48e718bc",
    
    "Keyboards": "catalog_Magic_Keyboard_with_Numeric_Keypad_b235a5b4",
    "Mice": "catalog_Magic_Mouse_2_83244678",
    "Trackpads": "catalog_Magic_Trackpad_2_d930e2fa",
    "Apple Pencil": "catalog_Apple_Pencil_Pro_0c5ad598",
    
    "MacBook": "catalog_MacBookPro18_1_be8e6794",
    "MacBook Standard": "catalog_MacBookPro18_1_be8e6794",
    "Mac 台式机": "catalog_iMac20_1_1a43c931",
    "Mac Desktops": "catalog_iMac20_1_1a43c931",
    "MacBook Pro": "catalog_MacBookPro18_1_be8e6794",
    "MacBook Air": "catalog_MacBookAir9_1_a1bfb211",
    "iMac": "catalog_iMac20_1_1a43c931",
    "Mac mini": "catalog_Macmini3_1-Server_334db9d2",
    "Classic": "catalog_Apple_I",
    "Classic Apple Computer": "catalog_Apple_I",
    "Apple 经典电脑": "catalog_Apple_I",
    "Xserve": "catalog_Xserve3_1_99c05074",
    
    "显示器": "catalog_AppleDisplay2_1_dd935854",
    "Studio Display": "catalog_AppleDisplay2_1_dd935854",
    "Pro Display": "catalog_Pro_Display_XDR_4ace34f4",
    "Thunderbolt Display": "catalog_Apple_Thunderbolt_Display_c14bff42",
    "Cinema Display": "catalog_Apple_Cinema_Display_20-inch_2004_4d3513eb",
    "Adapters": "catalog_35W_Dual_USB-C_Port_Power_Adapter_695955b0",
    "Cables": "catalog_USB-C_Charge_Cable_2_m_b0a4ff19",
    "MagSafe": "catalog_MagSafe_Charger_1_m_98fbe840",
    "Other": "catalog_35W_Dual_USB-C_Port_Power_Adapter_695955b0",
    "Connectivity & Expansion": "catalog_USB-C_Digital_AV_Multiport_Adapter_HDMI_2.0_8dd79c64",
    "Cases & Storage": "catalog_iPhone_16_Pro_Max_Clear_Case_with_MagSafe_cca1cd34",
    "MagSafe Cases": "catalog_iPhone_15_Pro_FineWoven_Case_with_MagSafe_dcfe9e42",
    "Battery Cases": "catalog_iPhone_11_Pro_Smart_Battery_Case_a273ff6e",
    "Cases": "catalog_iPhone_16_Pro_Max_Clear_Case_with_MagSafe_cca1cd34",
    "Other Cases & Storage": "catalog_iPhone_15_Pro_FineWoven_Case_with_MagSafe_dcfe9e42",
    "AirTag": "catalog_AirTag1_1_16fe8b4a",
    
    "Earbuds": "catalog_BeatsFitPro1_1-case_2a54a027",
    "Headphones": "catalog_BeatsStudioPro1_1_5b72630a",
    "Speakers": "catalog_Beats_Pill_2nd_generation_fea11c0a",
    "Beats Earbuds": "catalog_BeatsFitPro1_1-case_2a54a027",
    "Beats Headphones": "catalog_BeatsStudioPro1_1_5b72630a",
    "Beats Speakers": "catalog_Beats_Pill_2nd_generation_fea11c0a",
    "Beats Accessories": "catalog_Beats_USB-C_to_USB-C_Woven_Cable_1.5_m_178a6aaf",
    
    "AirPods Standard": "device_Airpods-8",
    "AirPods Pro": "catalog_AirPodsPro1_2-usbc-case_a5786e2f",
    "AirPods Max": "catalog_AirPodsMax1_1_56607ec7",
    
    "iPhone Standard": "catalog_iPhone16_1_c00ebe62",
    "iPhone Pro": "catalog_iPhone16_2_82d62ae4",
    "iPhone Air": "catalog_iPhone16_1_c00ebe62",
    "iPhone mini": "catalog_iPhone13_1_bfb3aa93",
    "iPhone Plus": "catalog_iPhone15_5_c36bf6d5",
    "iPhone Duo": "catalog_iPhone16_1_c00ebe62",
    "iPhone SE": "catalog_iPhone14_6_53aa3417",
    
    "iPad Standard": "catalog_iPad13_18_b135c345",
    "iPad Pro": "catalog_iPad14_5_1da35057",
    "iPad Air": "catalog_iPad14_8_5ad722e0",
    "iPad mini": "catalog_iPad14_1_5914fa0c",
    
    "Watch Standard": "catalog_Watch7_14_351065e0",
    "Watch SE": "catalog_Watch6_10_2fbbdd5f",
    "Watch Ultra": "catalog_Watch7_5_8f37bcba",
    "Apple Watch Standard": "catalog_Watch7_14_351065e0",
    "Apple Watch SE": "catalog_Watch6_10_2fbbdd5f",
    "Apple Watch Ultra": "catalog_Watch7_5_8f37bcba"
]

// MARK: - 自定义分类主图持久化存储器 (Category Cover Store)

@MainActor
final class CategoryCoverStore: ObservableObject {
    static let shared = CategoryCoverStore()
    
    private let storageKey = "custom_category_covers_data"
    
    @Published private(set) var customCovers: [String: String] = [:]
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.customCovers = decoded
        }
    }
    
    /// 解析某个分类当前应展示的主视觉图资源名
    func coverAssetName(for categoryKey: String, fallback: String? = nil) -> String? {
        let key = normalizeCategoryCoverKey(categoryKey)
        
        // 1. 用户自定义主图优先
        if let custom = customCovers[key], imageAssetExists(custom) {
            return custom
        }
        
        // 2. 官方精选默认主图
        if let defaultArt = defaultCategoryCovers[key], imageAssetExists(defaultArt) {
            return defaultArt
        }
        
        // 3. 动态回退（如分类下首个产品的图样）
        if let fallback, imageAssetExists(fallback) {
            return fallback
        }
        
        return nil
    }
    
    /// 设置某分类的主图
    func setCover(assetName: String, for categoryKey: String) {
        let key = normalizeCategoryCoverKey(categoryKey)
        customCovers[key] = assetName
        persist()
    }
    
    /// 恢复某分类的默认主图
    func resetCover(for categoryKey: String) {
        let key = normalizeCategoryCoverKey(categoryKey)
        customCovers.removeValue(forKey: key)
        persist()
    }
    
    /// 判断某分类是否经过自定义修改
    func isCustomized(for categoryKey: String) -> Bool {
        let key = normalizeCategoryCoverKey(categoryKey)
        return customCovers[key] != nil
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(customCovers) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}

// MARK: - 设置为主图菜单组件 (Category Cover Menu)

struct CategoryCoverMenuContent: View {
    let artworkAssetName: String
    let tiers: [CategoryHierarchyTier]
    @ObservedObject var coverStore = CategoryCoverStore.shared
    var onSelect: ((String) -> Void)? = nil
    
    init(artworkAssetName: String, tiers: [CategoryHierarchyTier], onSelect: ((String) -> Void)? = nil) {
        self.artworkAssetName = artworkAssetName
        self.tiers = tiers
        self.onSelect = onSelect
    }
    
    var body: some View {
        Section(appLocalized("Set as Category Cover")) {
            if tiers.count > 1 {
                Button {
                    for tier in tiers {
                        coverStore.setCover(assetName: artworkAssetName, for: tier.key)
                    }
                    #if canImport(UIKit) && !os(visionOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    onSelect?(appLocalized("Applied to All Tiers"))
                } label: {
                    Label(appLocalized("Change All Tiers"), systemImage: "square.stack.3d.up.fill")
                }
            }
            ForEach(tiers) { tier in
                let isCurrentCover = coverStore.coverAssetName(for: tier.key) == artworkAssetName
                Button {
                    coverStore.setCover(assetName: artworkAssetName, for: tier.key)
                    #if canImport(UIKit) && !os(visionOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    onSelect?(tierMenuTitle(tier))
                } label: {
                    HStack {
                        Text(tierMenuTitle(tier))
                        if isCurrentCover {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        
        let customizedTiers = tiers.filter { coverStore.isCustomized(for: $0.key) }
        if !customizedTiers.isEmpty {
            Section {
                Button(role: .destructive) {
                    for tier in customizedTiers {
                        coverStore.resetCover(for: tier.key)
                    }
                    #if canImport(UIKit) && !os(visionOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    #endif
                    onSelect?(appLocalized("Default Cover"))
                } label: {
                    Label(appLocalized("Restore Default Covers"), systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
    
    private func tierMenuTitle(_ tier: CategoryHierarchyTier) -> String {
        let localizedName = appLocalized(tier.title)
        switch tier.level {
        case 1:
            return String(format: appLocalized("Set as Root Cover (%@)"), localizedName)
        case 2:
            return String(format: appLocalized("Set as Tier-2 Menu Cover (%@)"), localizedName)
        case 3:
            return String(format: appLocalized("Set as Tier-3 Menu Cover (%@)"), localizedName)
        case 4:
            return String(format: appLocalized("Set as Tier-4 Menu Cover (%@)"), localizedName)
        default:
            return String(format: appLocalized("Set as Cover (%@)"), localizedName)
        }
    }
}
