import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import os

// MARK: - 图片资产存在性高速缓存 (Image Asset Existence Cache)
private final class ImageAssetCache: @unchecked Sendable {
    static let shared = ImageAssetCache()
    private var cache = [String: Bool]()
    private let lock = NSLock()

    func exists(_ name: String) -> Bool {
        if name.isEmpty { return false }
        lock.lock()
        if let hit = cache[name] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let result: Bool
#if canImport(UIKit)
        result = (UIImage(named: name) != nil)
#elseif canImport(AppKit)
        result = (NSImage(named: NSImage.Name(name)) != nil)
#else
        result = false
#endif

        lock.lock()
        cache[name] = result
        lock.unlock()
        return result
    }
}

// MARK: - 苹果设备分类与图鉴工具函数 (Catalog & Category Helpers)

/// 检查图片资产是否存在（带 0 微秒内存缓存，消除主线程频繁查找 Asset Catalog 的 I/O 阻塞）
func imageAssetExists(_ name: String) -> Bool {
    ImageAssetCache.shared.exists(name)
}

/// 国际化本地化快捷辅助
func appLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 仅当系统首选语言为中文时才返回 true，其他所有语言系统均返回 false (以英文为默认基准)
var isChineseLanguage: Bool {
    if let code = Locale.current.language.languageCode?.identifier {
        return code.hasPrefix("zh")
    }
    if let preferred = Bundle.main.preferredLocalizations.first {
        return preferred.hasPrefix("zh")
    }
    return false
}

/// 将分类英文标识转换为显示名称
func categoryTitle(_ category: String) -> String {
    let titles = [
        "Adapter": "Adapters",
        "Adapters": "Adapters",
        "AirTag": "AirTag",
        "AirPods": "AirPods",
        "Airpods": "AirPods",
        "Airport": "AirPort",
        "Apple Pencil": "Apple Pencil",
        "Apple pencil": "Apple Pencil",
        "Apple Watch": "Watch",
        "Apple watch": "Watch",
        "Watch": "Watch",
        "watch": "Watch",
        "Apple TV": "Apple TV",
        "AppleTV": "Apple TV",
        "Beats": "Beats",
        "Beats Earbuds": "Beats Earbuds",
        "Beats Headphones": "Beats Headphones",
        "Beats Speakers": "Beats Speakers",
        "Earbuds": "Earbuds",
        "Headphones": "Headphones",
        "Speakers": "Speakers",
        "入耳式耳机": "Earbuds",
        "头戴式耳机": "Headphones",
        "扬声器": "Speakers",
        "Display": "Displays",
        "Audio": "Audio",
        "Accessories": "Accessories",
        "Cases": "Cases",
        "Power": "Power",
        "Input Devices": "Input Devices",
        "输入设备": "Input Devices",
        "Keyboards": "Keyboards",
        "Mice": "Mice",
        "Trackpad": "Trackpads",
        "Trackpads": "Trackpads",
        "键盘": "Keyboards",
        "鼠标": "Mice",
        "触控板": "Trackpads",
        "Pencil": "Apple Pencil",
        "MagSafe": "MagSafe",
        "MagSafe充电设备": "MagSafe",
        "Docker": "Docks",
        "HomePod": "HomePod",
        "Mac": "Mac",
        "Mac 台式机": "Mac 台式机",
        "Mac Desktops": "Mac 台式机",
        "Mac Desktop": "Mac 台式机",
        "Remote": "Remotes",
        "Apple Vision Pro": "Vision Pro",
        "Vision pro": "Vision Pro",
        "Vision Pro": "Vision Pro",
        "Headset": "Vision Pro",
        "Home": "Home",
        "家庭": "Home",
        "Home Accessories": "Home",
        "家庭配件": "Home",
        "iPad": "iPad",
        "iPhone": "iPhone",
        "iPod": "iPod",
        "MagSafe Cases": "MagSafe Cases",
        "Battery Cases": "Battery Cases",
        "Other Cases & Storage": "Other Cases & Storage",
        "扩展坞": "Docks",
        "配件": "Accessories",
        "Cables": "Cables",
        "Cable": "Cables",
        "Beats Accessories": "Beats Accessories",
        "Beats 配件": "Beats Accessories",
        "Other": "Other",
        "iPhone Standard": "iPhone Standard",
        "iPhone Pro": "iPhone Pro",
        "iPhone Air": "iPhone Air",
        "iPhone mini": "iPhone mini",
        "iPhone Plus": "iPhone Plus",
        "iPhone Duo": "iPhone Duo",
        "iPhone SE": "iPhone SE",
        "iPad Standard": "iPad Standard",
        "iPad Pro": "iPad Pro",
        "iPad Air": "iPad Air",
        "iPad mini": "iPad mini",
        "Apple Watch Standard": "Watch Standard",
        "Apple Watch SE": "Watch SE",
        "Apple Watch Ultra": "Watch Ultra",
        "Watch Standard": "Watch Standard",
        "Watch SE": "Watch SE",
        "Watch Ultra": "Watch Ultra",
        "AirPods Standard": "AirPods Standard",
        "HomePod Standard": "HomePod Standard",
        "HomePod mini": "HomePod mini",
        "MacBook Standard": "MacBook Standard"
    ]
    return appLocalized(titles[category] ?? category)
}

/// 分类对应的 SF Symbols 矢量图标
func categorySymbol(_ category: String) -> String {
    let symbols = [
        "Adapter": "powerplug",
        "Adapters": "powerplug",
        "AirTag": "tag.fill",
        "AirPods": "airpods",
        "Airpods": "airpods",
        "AirPort": "wifi.router",
        "Airport": "wifi.router",
        "Apple Pencil": "applepencil",
        "Apple pencil": "applepencil",
        "Apple Watch": "applewatch",
        "Apple watch": "applewatch",
        "Watch": "applewatch",
        "watch": "applewatch",
        "Apple TV": "appletv",
        "AppleTV": "appletv",
        "Apple Vision Pro": "vision.pro",
        "Vision pro": "vision.pro",
        "Vision Pro": "vision.pro",
        "Vision": "vision.pro",
        "Headset": "vision.pro",
        "Home": "house.fill",
        "家庭": "house.fill",
        "Home Accessories": "house.fill",
        "Apple HomeView": "display.2",
        "LG Smart Security": "video.doorbell.fill",
        "LG 智能安防": "video.doorbell.fill",
        "Schneider Energy & Climate": "thermometer.sun.fill",
        "Schneider 能源与温控": "thermometer.sun.fill",
        "Smart Home Accessories": "house.fill",
        "智能家居配件": "house.fill",
        "Beats": "headphones",
        "Beats Earbuds": "earbuds",
        "Beats Headphones": "headphones",
        "Beats Speakers": "hifispeaker",
        "Earbuds": "earbuds",
        "Headphones": "headphones",
        "Speakers": "hifispeaker",
        "入耳式耳机": "earbuds",
        "头戴式耳机": "headphones",
        "扬声器": "hifispeaker",
        "Display": "display",
        "Displays": "display",
        "Studio Display": "display",
        "Pro Display": "display",
        "Thunderbolt Display": "display",
        "Cinema Display": "display",
        "Audio": "headphones",
        "Audio Accessories": "headphones",
        "音频配件": "headphones",
        "音频设备": "headphones",
        "Accessories": "shippingbox",
        "Cases": "iphone.case",
        "Cases & Storage": "iphone.case",
        "MagSafe Cases": "bolt.shield",
        "MagSafe 保护壳": "bolt.shield",
        "Battery Cases": "battery.100.bolt",
        "电池壳": "battery.100.bolt",
        "Other Cases & Storage": "archivebox",
        "其他保护壳与收纳": "archivebox",
        "保护与收纳": "iphone.case",
        "保护壳与保护套": "iphone.case",
        "Power": "powerplug",
        "Power & Charging": "powerplug",
        "电源与充电": "powerplug",
        "电源设备": "powerplug",
        "Keyboard": "keyboard",
        "Keyboards": "keyboard",
        "Mouse": "computermouse",
        "Mice": "computermouse",
        "Trackpad": "rectangle.and.hand.point.up.left",
        "Trackpads": "rectangle.and.hand.point.up.left",
        "Magic Trackpad": "rectangle.and.hand.point.up.left",
        "触控板": "rectangle.and.hand.point.up.left",
        "Docker": "rectangle.connected.to.line.below",
        "Docks": "rectangle.connected.to.line.below",
        "Connectivity & Expansion": "rectangle.connected.to.line.below",
        "连接与扩展": "rectangle.connected.to.line.below",
        "Input Devices": "keyboard",
        "输入设备": "keyboard",
        "Other Accessories": "sparkles",
        "其他配件": "sparkles",
        "HomePod": "homepodmini",
        "Mac": "laptopcomputer",
        "MacBook": "laptopcomputer",
        "MacBook Air": "laptopcomputer",
        "MacBook Pro": "laptopcomputer",
        "MacBook Neo": "laptopcomputer",
        "iBook": "laptopcomputer",
        "PowerBook": "laptopcomputer",
        "Mac mini": "desktopcomputer",
        "Mac Pro": "desktopcomputer",
        "Mac Studio": "desktopcomputer",
        "Macintosh": "desktopcomputer",
        "Power Mac": "desktopcomputer",
        "iMac": "desktopcomputer",
        "eMac": "desktopcomputer",
        "Mac 台式机": "desktopcomputer",
        "Mac Desktops": "desktopcomputer",
        "Mac Desktop": "desktopcomputer",
        "Desktops": "desktopcomputer",
        "Desktop": "desktopcomputer",
        "台式机": "desktopcomputer",
        "Xserve": "server.rack",
        "Classic": "apple.logo",
        "Classic Apple Computer": "apple.logo",
        "Apple 经典电脑": "apple.logo",
        "Apple Series": "apple.logo",
        "数字系列": "iphone",
        "Air 系列": "iphone",
        "Pro 系列": "iphone",
        "mini 系列": "iphone",
        "Plus 系列": "iphone",
        "Duo 系列": "iphone",
        "SE 系列": "iphone",
        "AirPods Pro": "airpodspro",
        "AirPods Max": "airpodsmax",
        "MagSafe": "bolt.fill",
        "显示器": "display",
        "MagSafe充电设备": "bolt.fill",
        "Remote": "appletvremote.gen4",
        "Remotes": "appletvremote.gen4",
        "遥控器": "appletvremote.gen4",
        "iPad": "ipad",
        "iPhone": "iphone",
        "iPod": "ipodtouch",
        "扩展坞": "rectangle.connected.to.line.below",
        "键盘": "keyboard",
        "通用": "keyboard",
        "iPad 专用": "keyboard.badge.ellipsis",
        "鼠标": "computermouse",
        "Cables": "cable.connector",
        "Cable": "cable.connector",
        "Beats Accessories": "shippingbox",
        "Other": "sparkles",
        "iPhone Standard": "iphone",
        "iPhone Pro": "iphone",
        "iPhone Air": "iphone",
        "iPhone mini": "iphone",
        "iPhone Plus": "iphone",
        "iPhone Duo": "iphone",
        "iPhone SE": "iphone",
        "iPad Standard": "ipad",
        "iPad Pro": "ipad",
        "iPad Air": "ipad",
        "iPad mini": "ipad",
        "Apple Watch Standard": "applewatch",
        "Apple Watch SE": "applewatch",
        "Apple Watch Ultra": "applewatch",
        "Watch Standard": "applewatch",
        "Watch SE": "applewatch",
        "Watch Ultra": "applewatch",
        "AirPods Standard": "airpods",
        "HomePod Standard": "homepod.fill",
        "HomePod mini": "homepodmini.fill",
        "MacBook Standard": "laptopcomputer"
    ]
    if let sym = symbols[category] {
        return sym.trimmingCharacters(in: .whitespaces)
    }
    let lower = category.lowercased()
    for (key, val) in symbols where key.lowercased() == lower {
        return val.trimmingCharacters(in: .whitespaces)
    }
    if lower.contains("desktop") || lower.contains("台式") {
        return "desktopcomputer"
    }
    return "shippingbox"
}

/// 识别是否为 Apple 有线音频配件及特定耳机硬件
func isWiredAppleAudio(_ name: String) -> Bool {
    let lower = name.lowercased()
    if lower.contains("beats") || lower.contains("airpods") { return false }
    // A1307 入耳式耳机、A3046 (EarPods USB-C) 等属于有线音频配件；注意：A3057 为 AirPods 4 ANC 无线耳机，属于 AirPods 大类
    if lower.contains("a1307") || lower.contains("a3046") || lower.contains("ma850") {
        return true
    }
    if lower.contains("adapter") || lower.contains("转换") { return false }
    return ["earpods", "earphone", "in ear", "in-ear", "headphones", "headphone"].contains(where: lower.contains)
}

/// 藏品分组：除了解析出的产品名，也结合藏品自己记录的名称
func itemRootCategory(_ item: CollectionItem) -> String {
    let model = (item.model ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if model == "A1307" || model == "A3046" || isWiredAppleAudio(item.name) || isWiredAppleAudio(item.resolvedProductName) {
        return "配件"
    }
    return catalogRootCategory(item.category, name: item.resolvedProductName)
}

func itemFamilyName(_ item: CollectionItem, root: String) -> String {
    let model = (item.model ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if root == "配件", model == "A1307" || model == "A3046" || isWiredAppleAudio(item.name) || isWiredAppleAudio(item.resolvedProductName) {
        return "Audio Accessories"
    }
    return catalogFamilyName(name: item.resolvedProductName, category: item.category, root: root)
}

/// 把数据源里的细分类归纳为用户可见的一级大类
func catalogRootCategory(_ rawCategory: String, name: String) -> String {
    let text = "\(rawCategory) \(name)".lowercased()
    let raw = rawCategory.lowercased()
    if ["sdk", "simulator", "virtual machine"].contains(raw) { return "" }
    if isWiredAppleAudio(name) { return "配件" }
    
    // 家庭大类（含 HomePod、Apple TV、HomeView 及智能家居配件）
    if text.contains("homepod") || text.contains("appletv") || text.contains("apple tv") ||
       text.contains("homeview") || text.contains("home collection") ||
       raw == "home" || raw == "家庭" || raw == "home accessories" || raw == "家庭配件" ||
       text.contains("doorbell") || text.contains("deadbolt") || text.contains("thermostat") || text.contains("schneider") {
        return "Home"
    }

    // 输入设备大类（包含键盘、鼠标、触控板、Apple Pencil）
    if raw == "keyboard" || raw == "键盘" || raw == "mouse" || raw == "鼠标" ||
       raw == "trackpad" || raw == "触控板" || raw == "apple pencil" || raw == "pencil" ||
       raw == "input devices" || raw == "输入设备" ||
       text.contains("apple pencil") || (text.contains("pencil") && !text.contains("case") && !text.contains("holder")) ||
       text.contains("trackpad") || text.contains("触控板") ||
       text.contains("magic mouse") || text.contains("mighty mouse") || text.contains("apple mouse") ||
       raw == "mouse" || text.contains("鼠标") ||
       (text.contains("keyboard") && !["powerbook", "mac", "macbook", "ipad", "ibook"].contains(raw)) {
        return "Input Devices"
    }

    // 配件大类（含 AirTag、MagSafe 等）
    if text.contains("beats") && !(text.contains("case") && text.contains("iphone")) {
        return "Beats"
    }
    if text.contains("airtag") || text.contains("magsafe") || raw == "magsafe充电设备" {
        return "配件"
    }

    let accessoryCategories = [
        "adapter", "adapters", "accessories", "配件", "cases", "docker", "power",
        "bluetooth", "module", "network card", "graphics cards", "storage", "audio",
        "audio accessories", "音频配件", "remote", "other"
    ]
    if accessoryCategories.contains(raw) { return "配件" }
    if text.contains("airpods") { return "AirPods" }
    if text.contains("iphone") { return "iPhone" }
    if text.contains("ipad") { return "iPad" }
    if text.contains("beats") { return "Beats" }
    if text.contains("ipod") { return "iPod" }
    if text.contains("macbook") || text.contains("mac mini") || text.contains("mac pro") ||
        text.contains("mac studio") || text.contains("macintosh") || text.contains("powermac") ||
        text.contains("power mac") || text.contains("powerbook") || text.contains("ibook") ||
        text.contains("imac") || text.contains("emac") || text.contains("xserve") ||
        rawCategory == "Mac" || raw.contains("mac") || raw.contains("desktop") || raw == "classic" {
        return "Mac"
    }
    if text.contains("display") || text.contains("monitor") || rawCategory == "显示器" { return "显示器" }
    if text.contains("apple watch") || text.contains("watch") { return "Watch" }
    if text.contains("airport") { return "AirPort" }
    if raw == "headset" || text.contains("vision pro") { return "Vision Pro" }
    if text.contains("apple i") || text.contains("apple ii") || text.contains("apple iii") || text.contains("apple ///") || text.contains("lisa") || text.contains("classic") { return "Mac" }
    return categoryTitle(rawCategory)
}

func macProductBranch(for product: CatalogDisplayProduct) -> String {
    let text = "\(product.category) \(product.name)".lowercased()
    return ["macbook", "ibook", "powerbook"].contains(where: text.contains) ? "MacBook" : "Mac 台式机"
}

func ownedMacBranch(_ item: CollectionItem) -> String {
    let text = "\(item.category) \(item.resolvedProductName)".lowercased()
    return ["macbook", "ibook", "powerbook"].contains(where: text.contains) ? "MacBook" : "Mac 台式机"
}

func catalogFamily(_ product: CatalogDisplayProduct, root: String) -> String {
    catalogFamilyName(name: product.name, category: product.category, root: root)
}

/// 计算二级产品族名称（例如 iPhone 下划分 Pro系列、mini系列等）
func catalogFamilyName(name: String, category: String, root: String) -> String {
    let text = "\(category) \(name)".lowercased()
    switch root {
    case "iPhone":
        if text.contains("duo") { return "iPhone Duo" }
        if text.contains("mini") { return "iPhone mini" }
        if text.contains("plus") { return "iPhone Plus" }
        if text.contains("pro") { return "iPhone Pro" }
        if text.contains("air") { return "iPhone Air" }
        if text.contains("se") { return "iPhone SE" }
        return "iPhone Standard"
    case "iPad":
        if text.contains("ipad pro") { return "iPad Pro" }
        if text.contains("ipad air") { return "iPad Air" }
        if text.contains("ipad mini") { return "iPad mini" }
        return "iPad Standard"
    case "Mac":
        if text.contains("macbook neo") { return "MacBook Neo" }
        if text.contains("macbook air") { return "MacBook Air" }
        if text.contains("macbook pro") { return "MacBook Pro" }
        if text.contains("macbook") { return "MacBook Standard" }
        if text.contains("powerbook") { return "PowerBook" }
        if text.contains("ibook") { return "iBook" }
        if text.contains("imac") { return "iMac" }
        if text.contains("emac") { return "eMac" }
        if text.contains("mac mini") { return "Mac mini" }
        if text.contains("mac studio") { return "Mac Studio" }
        if text.contains("mac pro") { return "Mac Pro" }
        if text.contains("powermac") || text.contains("power mac") { return "Power Mac" }
        if text.contains("xserve") { return "Xserve" }
        if text.contains("macintosh") { return "Macintosh" }
        if text.contains("apple i") || text.contains("apple ii") || text.contains("apple iii") || text.contains("apple ///") || text.contains("lisa") || text.contains("classic apple") { return "Classic" }
        return "其他 Mac"
    case "AirPods":
        if text.contains("max") { return "AirPods Max" }
        if text.contains("pro") { return "AirPods Pro" }
        return "AirPods Standard"
    case "iPod":
        if text.contains("nano") { return "iPod nano" }
        if text.contains("touch wheel") { return "基础款" }
        if text.contains("ipod touch") || category.localizedCaseInsensitiveContains("touch") { return "iPod touch" }
        if text.contains("shuffle") { return "iPod shuffle" }
        if text.contains("classic") { return "iPod classic" }
        if text.contains("mini") { return "iPod mini" }
        return "基础款"
    case "Beats":
        if text.contains("speaker") || text.contains("pill") { return "Speakers" }
        if text.contains("earbud") || text.contains("in-ear") || text.contains("bud") || text.contains("fit") || text.contains("powerbeats") || text.contains("urbeats") || text.contains("tour") || text.contains("beatsx") || text.contains("beats x") || text.contains("flex") || text.contains("heartbeats") || text.contains("earphone") {
            return "Earbuds"
        }
        if text.contains("cable") || text.contains("adapter") || text.contains("remotetalk") || text.contains("remote") || text.contains("cushion") || text.contains("earpad") || text.contains("accessory") || category.lowercased() == "beats accessories" {
            return "Beats Accessories"
        }
        return "Headphones"
    case "Watch", "Apple Watch":
        if text.contains("ultra") { return "Watch Ultra" }
        if !text.contains("series") && name.range(of: #"\bSE\b"#) != nil {
            return "Watch SE"
        }
        return "Watch Standard"
    case "Input Devices", "输入设备":
        if text.contains("pencil") { return "Apple Pencil" }
        if text.contains("trackpad") || text.contains("触控板") { return "Trackpads" }
        if text.contains("mouse") || text.contains("mice") || text.contains("鼠标") { return "Mice" }
        return "Keyboards"
    case "配件", "Accessories":
        if text.contains("airtag") { return "AirTag" }
        if text.contains("remote") || text.contains("遥控器") { return "Remote" }
        if text.contains("case") || text.contains("cover") || text.contains("sleeve") || text.contains("folio") || text.contains("wallet") || text.contains("bumper") {
            return "Cases & Storage"
        }
        if text.contains("charger") || text.contains("power") || text.contains("battery") || text.contains("magsafe charger") || text.contains("magsafe battery") || text.contains("magsafe duo") {
            return "Power & Charging"
        }
        // 音频配件优先检查（如 EarPods USB-C、In-Ear、A1307、A3046 等），防止因包含 USB-C / Cable 被误判为转接扩展
        if isWiredAppleAudio(name) || text.contains("speaker") || text.contains("headphone") || text.contains("earphone") || text.contains("earpod") || text.contains("in-ear") || text.contains("in ear") || text.contains("a1307") || text.contains("a3046") || text.contains("audio") {
            return "Audio Accessories"
        }
        if text.contains("adapter") || text.contains("dock") || text.contains("cable") || text.contains("usb") || text.contains("thunderbolt") || text.contains("converter") || text.contains("magsafe") {
            return "Connectivity & Expansion"
        }
        return "Other Accessories"
    case "显示器":
        if text.contains("studio display") { return "Studio Display" }
        if text.contains("pro display") { return "Pro Display" }
        if text.contains("thunderbolt display") { return "Thunderbolt Display" }
        if text.contains("cinema display") || text.contains("cinema") { return "Cinema Display" }
        return "其他显示器"
    case "Vision Pro", "Apple Vision Pro", "Vision pro", "Headset":
        return "Vision Pro"
    case "Home", "家庭", "Home Accessories", "家庭配件":
        if text.contains("appletv") || text.contains("apple tv") { return "Apple TV" }
        if text.contains("homepod") { return "HomePod" }
        if text.contains("homeview") { return "Apple HomeView" }
        if text.contains("lg") || text.contains("doorbell") || text.contains("deadbolt") || text.contains("camera") { return "LG Smart Security" }
        if text.contains("schneider") || text.contains("thermostat") || text.contains("sensor") || text.contains("mount") { return "Schneider Energy & Climate" }
        return "Smart Home Accessories"
    default:
        return categoryTitle(category)
    }
}

/// 保护壳与收纳二级子分类
func caseSubfamily(name: String, category: String) -> String {
    let text = "\(category) \(name)".lowercased()
    if text.contains("battery case") {
        return "Battery Cases"
    }
    if text.contains("16e") && !text.contains("magsafe") {
        return "Cases"
    }
    if text.contains("magsafe") || text.contains("duo case") || text.contains("duo folio") {
        return "MagSafe Cases"
    }
    return "Other Cases & Storage"
}

/// 电源与充电二级子分类
func powerSubfamily(name: String, category: String) -> String {
    let text = "\(category) \(name)".lowercased()
    if text.contains("magsafe") {
        return "MagSafe"
    }
    if text.contains("cable") || text.contains("cord") || text.contains("wire") {
        return "Cables"
    }
    if text.contains("adapter") || text.contains("charger") || text.contains("power supply") || text.contains("watt") || text.contains("w ") {
        return "Adapters"
    }
    return "Other"
}

/// HomePod 子分类 (标准版与 mini)
func homepodSubfamily(name: String, category: String) -> String {
    let text = "\(category) \(name)".lowercased()
    if text.contains("mini") {
        return "HomePod mini"
    }
    return "HomePod Standard"
}

func keyboardFamily(_ text: String) -> String {
    let iPadMarkers = ["ipad", "smart keyboard", "folio", "-inch", "keyboard dock"]
    if iPadMarkers.contains(where: text.contains) { return "iPad 专用" }
    let classicMarkers = ["adjustable keyboard", "desktop bus keyboard", "extended keyboard", "appledesign keyboard",
                          "apple keyboard", "apple pro keyboard", "standard keyboard", "usb keyboard",
                          "numeric keypad iie", "macintosh", "lisa keyboard", "newton keyboard"]
    return classicMarkers.contains(where: text.contains) ? "经典" : "通用"
}

func catalogFamilyOrder(_ family: String, root: String) -> Int {
    let order: [String: [String]] = [
        "iPhone": ["iPhone Standard", "iPhone Air", "iPhone Pro", "iPhone mini", "iPhone Plus", "iPhone Duo", "iPhone SE", "数字系列", "Air 系列", "Pro 系列", "mini 系列", "Plus 系列", "Duo 系列", "SE 系列"],
        "iPad": ["iPad Standard", "iPad Air", "iPad Pro", "iPad mini", "数字系列", "Air 系列", "Pro 系列", "mini 系列"],
        "iPod": ["基础款", "iPod mini", "iPod nano", "iPod shuffle", "iPod classic", "iPod touch"],
        "Mac": ["MacBook Neo", "MacBook Air", "MacBook Pro", "MacBook Standard", "MacBook", "iBook", "PowerBook", "Classic", "Macintosh", "Power Mac", "iMac", "eMac", "Mac mini", "Mac Pro", "Mac Studio", "Xserve", "其他 Mac"],
        "AirPods": ["AirPods Standard", "AirPods Pro", "AirPods Max", "AirPods"],
        "Watch": ["Watch Standard", "Watch SE", "Watch Ultra", "Apple Watch Standard", "Apple Watch SE", "Apple Watch Ultra", "数字系列", "SE 系列", "Ultra 系列"],
        "Apple Watch": ["Watch Standard", "Watch SE", "Watch Ultra", "Apple Watch Standard", "Apple Watch SE", "Apple Watch Ultra", "数字系列", "SE 系列", "Ultra 系列"],
        "HomePod": ["HomePod Standard", "HomePod mini"],
        "Power & Charging": ["Adapters", "Cables", "MagSafe", "Other"],
        "Input Devices": ["Keyboards", "Mice", "Trackpads", "Apple Pencil"],
        "输入设备": ["Keyboards", "Mice", "Trackpads", "Apple Pencil", "键盘", "鼠标", "触控板"],
        "Accessories": ["Power & Charging", "Connectivity & Expansion", "Cases & Storage", "AirTag", "Audio Accessories", "Remote", "Other Accessories"],
        "配件": ["Power & Charging", "Connectivity & Expansion", "Cases & Storage", "AirTag", "Audio Accessories", "Remote", "Other Accessories", "电源与充电", "连接与扩展", "保护与收纳", "音频配件", "遥控器", "其他配件"],
        "Cases & Storage": ["MagSafe Cases", "Battery Cases", "Cases", "Other Cases & Storage"],
        "保护与收纳": ["MagSafe Cases", "Battery Cases", "Cases", "Other Cases & Storage", "MagSafe 保护壳", "电池壳", "普通保护壳", "其他保护壳与收纳"],
        "显示器": ["Studio Display", "Pro Display", "Thunderbolt Display", "Cinema Display", "其他显示器"],
        "Home": ["Apple TV", "HomePod", "Apple HomeView", "LG Smart Security", "Schneider Energy & Climate", "Smart Home Accessories"],
        "家庭": ["Apple TV", "HomePod", "Apple HomeView", "LG Smart Security", "Schneider Energy & Climate", "Smart Home Accessories"],
        "Home Accessories": ["Apple TV", "HomePod", "Apple HomeView", "LG Smart Security", "Schneider Energy & Climate", "Smart Home Accessories"],
        "Beats": ["Earbuds", "Headphones", "Speakers", "Beats Accessories", "Beats Earbuds", "Beats Headphones", "Beats Speakers", "配件", "入耳式耳机", "头戴式耳机", "扬声器"]
    ]
    return order[root]?.firstIndex(of: family) ?? 100
}

// MARK: - AirPods & Beats 耳机套装聚合辅助

func airPodsSetBaseID(_ id: String) -> String? {
    for suffix in ["-magsafe-case", "-left", "-right", "-case"] where id.hasSuffix(suffix) {
        let base = String(id.dropLast(suffix.count))
        if base.hasPrefix("AirPods") || base.hasPrefix("Beats") || base.hasPrefix("Power") {
            return base
        }
    }
    return nil
}

func airPodsPartOrder(_ id: String) -> Int {
    if id.hasSuffix("-left") { return 0 }
    if id.hasSuffix("-right") { return 1 }
    if id.hasSuffix("-case") || id.hasSuffix("-magsafe-case") { return 2 }
    return 0
}

func airPodsSetTitle(from name: String) -> String {
    for side in [" (Left", " (Right", " Charging Case"] {
        if let range = name.range(of: side) {
            let family = String(name[..<range.lowerBound])
            let detail = String(name[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ", )"))
            return detail.isEmpty ? family : "\(family) · \(detail)"
        }
    }
    return name
}

// MARK: - 设备外观配色与图片资源

let deviceColorOptions: [String: [String]] = [
    "鼠标-5": ["White", "Black", "Space Gray", "Silver", "Blue", "Green", "Pink", "Yellow", "Orange", "Purple"],
    "鼠标-4": ["Silver", "Space Gray", "Black", "White"],
    "键盘-6": ["Silver", "White", "Black"],
    "HomePod-1": ["White", "Space Gray"],
    "HomePod-3": ["Midnight", "Blue", "Orange", "Yellow", "Space Gray", "White"],
    "HomePod-4": ["Midnight", "White", "Blue", "Yellow", "Orange", "Pink", "Green"],
    "iPhone-6": ["Blue", "Green", "Pink", "White", "Yellow"],
    "iPhone-7": ["Gold", "Rose Gold", "Silver", "Space Gray"],
    "iPhone-x": ["Gold", "Red", "Silver", "Space Gray"],
    "iPhone-x-2": ["Gold", "Midnight Green", "Silver", "Space Gray"],
    "iPhone-x-3": ["Blue", "Green", "Midnight", "Pink", "Red", "Starlight"],
    "iPhone-x-4": ["Deep Purple", "Gold", "Silver", "Space Black"],
    "iPhone-x-5": ["Cosmic Orange", "Deep Blue", "Silver"],
    "iPod-9": ["Silver", "Pink", "Blue", "Green", "Black", "White"],
    "iPod-15": ["Silver", "Black", "Blue", "Yellow", "Pink", "Green"],
    "iPod-17": ["Black", "Silver", "Red", "Blue", "Purple", "Pink", "Yellow", "Orange", "Green"],
    "iPod-18": ["Black"],
    "iPod-21": ["White", "Black"],
    "iPod-22": ["Silver", "Space Gray", "Gold", "Blue", "Pink", "Yellow", "Orange", "Green", "Red"],
    "iPod-23": ["Space Gray", "Red", "Blue", "Pink", "Silver", "Yellow", "Black"],
    "iPod-25": ["Red", "Blue", "Gold", "Pink", "Silver", "Space Gray"],
    "Mac-2": ["White", "Black"],
    "Mac-10": ["Silver", "Space Black"],
    "iPad-1": ["Black"],
    "iPad-2": ["Black", "White"],
    "iPad-3": ["Black", "White"],
    "iPad-4": ["Space Gray", "Silver", "Black"],
    "iPad-5": ["Black", "White"],
    "iPad-6": ["Silver", "Space Gray"],
    "iPad-7": ["Gold", "Silver", "Space Gray"],
    "iPad-8": ["Space Gray", "Pink", "Purple", "Starlight"],
    "iPad-9": ["Silver", "Space Gray"],
    "HomeView-1": ["Silver", "Starlight", "Rose Pink", "Space Gray"],
    "HomeView-2": ["Silver", "Space Gray"],
    "AirPodsMax1,1": ["Space Gray", "Silver", "Sky Blue", "Pink", "Green"],
    "AirPodsMax1,2": ["Midnight", "Starlight", "Blue", "Purple", "Orange"],
    "AirPodsMax1,1-usbc": ["Midnight", "Starlight", "Blue", "Purple", "Orange"],
    "Airpods-10": ["Midnight", "Starlight", "Blue", "Purple", "Orange"],
    "A3454": ["Midnight", "Starlight", "Blue", "Purple", "Orange"],
    "A3184": ["Midnight", "Starlight", "Blue", "Purple", "Orange"],
    "Airpods-5": ["Space Gray", "Silver", "Sky Blue", "Pink", "Green"],
    "A2096": ["Space Gray", "Silver", "Sky Blue", "Pink", "Green"],
    "BeatsStudioPro1,1": ["Black", "Deep Brown", "Navy", "Sandstone"],
    "Beats-29": ["Black", "Deep Brown", "Navy", "Sandstone"],
    "A2924": ["Black", "Deep Brown", "Navy", "Sandstone"],
    "BeatsSolo4,1": ["Matte Black", "Slate Blue", "Cloud Pink"],
    "Beats-30": ["Matte Black", "Slate Blue", "Cloud Pink"],
    "A3140": ["Matte Black", "Slate Blue", "Cloud Pink"],
    "BeatsStudio3,2": ["Matte Black", "Shadow Gray", "White", "Red", "Blue", "Defiant Black-Red"],
    "Beats-22": ["Matte Black", "Shadow Gray", "White", "Red", "Blue", "Defiant Black-Red"],
    "A1914": ["Matte Black", "Shadow Gray", "White", "Red", "Blue", "Defiant Black-Red"],
    "Beats3601,1": ["Black", "Cloud", "Pink", "Sky"],
    "A3577": ["Black", "Cloud", "Pink", "Sky"],
    "BeatsPill1,2": ["Matte Black", "Statement Red", "Champagne Gold"],
    "A3211": ["Matte Black", "Statement Red", "Champagne Gold"],
    "BeatsX2,1": ["Beats Black", "Flame Blue", "Smoke Gray", "Yuzu Yellow"],
    "Beats-27": ["Beats Black", "Flame Blue", "Smoke Gray", "Yuzu Yellow"],
    "A2295": ["Beats Black", "Flame Blue", "Smoke Gray", "Yuzu Yellow"],
    "BeatsFitPro1,1": ["Black", "White", "Sage Gray", "Stone Purple"],
    "A2576": ["Black", "White", "Sage Gray", "Stone Purple"],
    "A2577": ["Black", "White", "Sage Gray", "Stone Purple"],
    "A2578": ["Black", "White", "Sage Gray", "Stone Purple"],
    "BeatsSoloBuds1,1": ["Matte Black", "Storm Gray", "Arctic Purple", "Transparent Red"],
    "A3150": ["Matte Black", "Storm Gray", "Arctic Purple", "Transparent Red"],
    "A3151": ["Matte Black", "Storm Gray", "Arctic Purple", "Transparent Red"],
    "A3152": ["Matte Black", "Storm Gray", "Arctic Purple", "Transparent Red"],
    "A3153": ["Matte Black", "Storm Gray", "Arctic Purple", "Transparent Red"],
    "BeatsStudioBuds1,1": ["Black", "White"],
    "A2512": ["Black", "White"],
    "A2513": ["Black", "White"],
    "A2514": ["Black", "White"],
    "BeatsStudioBuds1,2": ["Black / Gold", "Ivory", "Transparent"],
    "Beats-28": ["Black / Gold", "Ivory", "Transparent"],
    "A2870": ["Black / Gold", "Ivory", "Transparent"],
    "A2871": ["Black / Gold", "Ivory", "Transparent"],
    "A2872": ["Black / Gold", "Ivory", "Transparent"],
    "Powerbeats Fit": ["Gravel Gray", "Jet Black", "Power Pink", "Spark Orange"],
    "PowerbeatsFit": ["Gravel Gray", "Jet Black", "Power Pink", "Spark Orange"],
    "A3476": ["Gravel Gray", "Jet Black", "Power Pink", "Spark Orange"],
    "A3477": ["Gravel Gray", "Jet Black", "Power Pink", "Spark Orange"],
    "A3479": ["Gravel Gray", "Jet Black", "Power Pink", "Spark Orange"],
    "PowerbeatsPro1,1": ["Black", "Ivory", "Moss", "Navy", "Glacier Blue", "Spring Yellow", "Cloud Pink", "Lava Red"],
    "PowerbeatsPro2,1": ["Black", "Ivory", "Moss", "Navy", "Glacier Blue", "Spring Yellow", "Cloud Pink", "Lava Red"],
    "Beats-26": ["Black", "Ivory", "Moss", "Navy", "Glacier Blue", "Spring Yellow", "Cloud Pink", "Lava Red"],
    "A2047": ["Black", "Ivory", "Moss", "Navy", "Glacier Blue", "Spring Yellow", "Cloud Pink", "Lava Red"],
    "A2048": ["Black", "Ivory", "Moss", "Navy", "Glacier Blue", "Spring Yellow", "Cloud Pink", "Lava Red"],
    "A2078": ["Black", "Ivory", "Moss", "Navy", "Glacier Blue", "Spring Yellow", "Cloud Pink", "Lava Red"],
    "A2453": ["Black", "Ivory", "Moss", "Navy", "Glacier Blue", "Spring Yellow", "Cloud Pink", "Lava Red"],
    "A2454": ["Black", "Ivory", "Moss", "Navy", "Glacier Blue", "Spring Yellow", "Cloud Pink", "Lava Red"],
    "Powerb3,1": ["Black & Volt", "Electric Orange", "Hyper Purple", "Jet Black", "Quick Sand"],
    "A3157": ["Black & Volt", "Electric Orange", "Hyper Purple", "Jet Black", "Quick Sand"],
    "A3158": ["Black & Volt", "Electric Orange", "Hyper Purple", "Jet Black", "Quick Sand"],
    "A3160": ["Black & Volt", "Electric Orange", "Hyper Purple", "Jet Black", "Quick Sand"],
    "BeatsSolo3,1": ["College Red", "College Yellow", "College White", "College Blue", "Mickey’s 90th Anniversary", "Electric Red", "Matte Black", "Gloss Black", "Gloss White", "Silver", "Gold", "Rose Gold", "Satin Gold", "Satin Silver"],
    "BeatsSolo3,1-mickey": ["Mickey’s 90th Anniversary"],
    "BeatsSolo3,1-nayva": ["College Blue", "Club Navy"],
    "Beats-15": ["College Red", "College Yellow", "College White", "College Blue", "Mickey’s 90th Anniversary", "Electric Red", "Matte Black", "Gloss Black", "Gloss White", "Silver", "Gold", "Rose Gold", "Satin Gold", "Satin Silver"],
    "A1796": ["College Red", "College Yellow", "College White", "College Blue", "Mickey’s 90th Anniversary", "Electric Red", "Matte Black", "Gloss Black", "Gloss White", "Silver", "Gold", "Rose Gold", "Satin Gold", "Satin Silver"],
    // 2025+ 最新 Apple 产品线官方配色
    "Mac16,12": ["Midnight", "Starlight", "Silver", "Sky Blue"],
    "Mac16,13": ["Midnight", "Starlight", "Silver", "Sky Blue"],
    "Mac17,3": ["Midnight", "Starlight", "Silver", "Sky Blue"],
    "Mac17,4": ["Midnight", "Starlight", "Silver", "Sky Blue"],
    "Mac16,1": ["Silver", "Space Black"],
    "Mac16,5": ["Silver", "Space Black"],
    "Mac16,6": ["Silver", "Space Black"],
    "Mac16,7": ["Silver", "Space Black"],
    "Mac16,8": ["Silver", "Space Black"],
    "Mac16,2": ["Blue", "Green", "Orange", "Pink", "Purple", "Silver", "Yellow"],
    "Mac16,3": ["Blue", "Green", "Orange", "Pink", "Purple", "Silver", "Yellow"],
    "iPhone18,3": ["Black", "White", "Lavender", "Mist Blue", "Sage"],
    "iPhone18,5": ["Black", "Soft Pink", "White"],
    "iPhone18,4": ["Space Black", "Cloud White", "Light Gold", "Sky Blue"],
    "iPhone19,2": ["Black", "Burgundy", "Glacier", "Silver"],
    "iPhone19,3": ["Black", "Burgundy", "Glacier", "Silver"],
    "iPhone19,7": ["Black", "Burgundy", "Glacier", "Silver"],
    "iPad16,3": ["Silver", "Space Black"],
    "iPad16,4": ["Silver", "Space Black"],
    "iPad16,5": ["Silver", "Space Black"],
    "iPad16,6": ["Silver", "Space Black"],
    "iPad17,1": ["Silver", "Space Black"],
    "iPad17,3": ["Silver", "Space Black"],
    "iPad14,8": ["Blue", "Purple", "Starlight", "Space Gray"],
    "iPad14,9": ["Blue", "Purple", "Starlight", "Space Gray"],
    "iPad14,10": ["Blue", "Purple", "Starlight", "Space Gray"],
    "iPad14,11": ["Blue", "Purple", "Starlight", "Space Gray"],
    "iPad16,1": ["Blue", "Purple", "Starlight", "Space Gray"],
    "iPad16,2": ["Blue", "Purple", "Starlight", "Space Gray"],
    "iPad13,18": ["Blue", "Pink", "Silver", "Yellow"],
    "iPad13,19": ["Blue", "Pink", "Silver", "Yellow"],
    "Watch8,1": ["Black", "Natural"],
    "Watch8,2": ["Black", "Dark Bronze", "Light Gold", "Space Gray", "Night Blue", "Pearl White", "Natural", "Radiant Gold"],
    "Watch8,3": ["Black", "Dark Bronze", "Light Gold", "Space Gray", "Night Blue", "Pearl White", "Natural", "Radiant Gold"],
    "Watch8,4": ["Black", "Dark Bronze", "Light Gold", "Space Gray", "Night Blue", "Pearl White", "Natural", "Radiant Gold"],
    "Watch8,5": ["Black", "Dark Bronze", "Light Gold", "Space Gray", "Night Blue", "Pearl White", "Natural", "Radiant Gold"],
    "Watch8,6": ["Midnight", "Starlight"],
    "Watch8,7": ["Midnight", "Starlight"]
]

func resolveColorDeviceKey(for id: String) -> String {
    let lower = id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower.contains("airpods max") || lower.contains("airpodsmax") || id == "Airpods-10" || id == "A3454" || id == "A3184" || id == "Airpods-5" || id == "A2096" {
        if lower.contains("usb-c") || lower.contains("usbc") || lower.contains("2") || id == "AirPodsMax1,2" || id == "AirPodsMax1,1-usbc" || id == "Airpods-10" || id == "A3454" || id == "A3184" {
            return "AirPodsMax1,2"
        }
        return "AirPodsMax1,1"
    }
    if lower.contains("magic mouse") || lower.contains("magic-mouse") || id == "鼠标-5" || id == "鼠标-2" {
        return "鼠标-5"
    }
    if lower.contains("magic trackpad") || id == "鼠标-4" {
        return "鼠标-4"
    }
    if lower.contains("magic keyboard with touch id") || id == "键盘-6" {
        return "键盘-6"
    }
    if id == "HomePod-3" || id == "HomePod-4" || lower.contains("homepod mini") || lower.contains("homepod-3") || lower.contains("homepod-4") || id.hasPrefix("AudioAccessory5,1") {
        return "HomePod-3"
    }
    if id == "HomePod-1" || lower.contains("homepod-1") || (lower.contains("homepod") && !lower.contains("mini")) || id.hasPrefix("AudioAccessory1,1") || id.hasPrefix("AudioAccessory1,2") || id.hasPrefix("AudioAccessory6,1") {
        return "HomePod-1"
    }
    if lower.contains("iphone se (1st") || lower == "iphone se" || lower == "iphonese" || id == "iPhone-7" || id == "iPhone8,4" {
        return "iPhone-7"
    }
    // 2025+ 最新 Apple 产品线键值映射
    if lower.contains("iphone 18 pro max") || id == "iPhone19,3" || id == "iPhone19,7" {
        return "iPhone19,3"
    }
    if lower.contains("iphone 18 pro") || id == "iPhone19,2" {
        return "iPhone19,2"
    }
    if lower.contains("iphone air") || id == "iPhone18,4" {
        return "iPhone18,4"
    }
    if lower.contains("iphone 17e") || id == "iPhone18,5" {
        return "iPhone18,5"
    }
    if lower.contains("iphone 17 pro max") || id == "iPhone-x-5" || id == "iPhone18,2" {
        return "iPhone-x-5"
    }
    if lower.contains("iphone 17") || id == "iPhone18,3" {
        return "iPhone18,3"
    }
    if lower.contains("macbook air (13") || lower.contains("macbook-air-13") || id == "Mac16,12" || id == "Mac17,3" {
        return "Mac16,12"
    }
    if lower.contains("macbook air (15") || lower.contains("macbook-air-15") || id == "Mac16,13" || id == "Mac17,4" {
        return "Mac16,13"
    }
    if lower.contains("macbook air") || lower.contains("macbook-air") {
        return "Mac16,12"
    }
    if lower.contains("macbook pro (14") || lower.contains("macbook-pro-14") || id == "Mac16,1" || id == "Mac16,6" || id == "Mac16,8" {
        return "Mac16,1"
    }
    if lower.contains("macbook pro (16") || lower.contains("macbook-pro-16") || id == "Mac16,5" || id == "Mac16,7" || id == "Mac-10" {
        return "Mac16,5"
    }
    if lower.contains("imac (24") || (lower.contains("imac") && (lower.contains("m4") || lower.contains("2024") || lower.contains("2025"))) || id == "Mac16,2" || id == "Mac16,3" {
        return "Mac16,2"
    }
    if lower.contains("studio display") || id == "AppleDisplay2,1" || id == "AppleDisplay18,2" || lower == "a2525" || lower == "a3350" {
        return "AppleDisplay2,1"
    }
    if lower.contains("ipad pro 11") || id == "iPad16,3" || id == "iPad16,4" || id == "iPad17,1" {
        return "iPad16,3"
    }
    if lower.contains("ipad pro 13") || id == "iPad16,5" || id == "iPad16,6" || id == "iPad17,3" {
        return "iPad16,5"
    }
    if lower.contains("ipad air 11") || id == "iPad14,8" || id == "iPad14,9" || id == "iPad15,3" {
        return "iPad14,8"
    }
    if lower.contains("ipad air 13") || id == "iPad14,10" || id == "iPad14,11" || id == "iPad15,5" {
        return "iPad14,10"
    }
    if lower.contains("ipad mini (a17") || lower.contains("ipad mini 7") || id == "iPad16,1" || id == "iPad16,2" {
        return "iPad16,1"
    }
    if lower.contains("ipad (10th") || id == "iPad13,18" || id == "iPad13,19" {
        return "iPad13,18"
    }
    if lower.contains("watch ultra 4") || id == "Watch8,1" {
        return "Watch8,1"
    }
    if lower.contains("watch series 12") || id == "Watch8,2" || id == "Watch8,3" || id == "Watch8,4" || id == "Watch8,5" {
        return "Watch8,2"
    }
    if lower.contains("watch se 3") || id == "Watch8,6" || id == "Watch8,7" {
        return "Watch8,6"
    }
    if lower.contains("ipod shuffle (3rd") || lower.contains("shuffle 3") || id == "iPod-15" {
        return "iPod-15"
    }
    if lower.contains("ipod shuffle (4th") || lower.contains("shuffle 4") || id == "iPod-22" {
        return "iPod-22"
    }
    if lower.contains("ipod nano (2nd") || lower.contains("nano 2") || id == "iPod-9" {
        return "iPod-9"
    }
    if lower.contains("ipod nano (4th") || lower.contains("nano 4") || id == "iPod-17" {
        return "iPod-17"
    }
    if lower.contains("macbook pro (16-inch, m4") || id == "Mac-10" {
        return "Mac-10"
    }
    if lower.contains("macbook (13-inch, mid 2009") || id == "Mac-2" {
        return "Mac-2"
    }
    if lower.contains("ipad mini (6th") || lower.contains("ipad14,1") || lower.contains("ipad14,2") || id == "iPad-8" {
        return "iPad-8"
    }
    if lower.contains("ipad (6th") || lower.contains("ipad7,5") || lower.contains("ipad7,6") || id == "iPad-7" {
        return "iPad-7"
    }
    if lower.contains("ipad mini 2") || lower.contains("ipad4,4") || lower.contains("ipad4,5") || lower.contains("ipad4,6") || id == "iPad-6" {
        return "iPad-6"
    }
    if lower.contains("ipad (4th") || lower.contains("ipad3,4") || lower.contains("ipad3,5") || lower.contains("ipad3,6") || id == "iPad-5" {
        return "iPad-5"
    }
    if lower.contains("ipad mini") || lower.contains("ipad2,5") || lower.contains("ipad2,6") || lower.contains("ipad2,7") || id == "iPad-4" {
        return "iPad-4"
    }
    if lower.contains("ipad (3rd") || lower.contains("ipad3,1") || lower.contains("ipad3,2") || lower.contains("ipad3,3") || id == "iPad-3" {
        return "iPad-3"
    }
    if lower.contains("ipad 2") || lower.contains("ipad2,1") || lower.contains("ipad2,2") || lower.contains("ipad2,3") || lower.contains("ipad2,4") || id == "iPad-2" {
        return "iPad-2"
    }
    if lower == "ipad" || lower.contains("ipad (1st") || lower.contains("ipad1,1") || lower.contains("ipad1,2") || id == "iPad-1" {
        return "iPad-1"
    }
    if lower.contains("ipad pro 12.9") || lower.contains("ipad14,5") || lower.contains("ipad14,6") || id == "iPad-9" {
        return "iPad-9"
    }
    
    // Beats 全系型号统一解析到专属官方外观图主键
    if lower.contains("beats solo 4") || id == "BeatsSolo4,1" || id == "Beats-30" || lower == "a3140" { return "BeatsSolo4,1" }
    if lower.contains("beats studio pro") || id == "BeatsStudioPro1,1" || id == "Beats-29" || lower == "a2924" { return "BeatsStudioPro1,1" }
    if lower.contains("beats studio 3") || lower.contains("beats studio³") || id == "BeatsStudio3,2" || id == "Beats-22" || lower == "a1914" { return "BeatsStudio3,2" }
    if lower.contains("beats 360") || id == "Beats3601,1" || lower == "a3577" { return "Beats3601,1" }
    if lower.contains("beats pill") || id == "BeatsPill1,2" || lower == "a3211" { return "BeatsPill1,2" }
    if lower.contains("beats flex") || id == "BeatsX2,1" || id == "Beats-27" || lower == "a2295" { return "BeatsX2,1" }
    if lower.contains("beats fit pro") || id.hasPrefix("BeatsFitPro1,1") || lower == "a2576" || lower == "a2577" || lower == "a2578" { return "BeatsFitPro1,1" }
    if lower.contains("beats solo buds") || id.hasPrefix("BeatsSoloBuds1,1") || lower == "a3150" || lower == "a3151" || lower == "a3152" || lower == "a3153" { return "BeatsSoloBuds1,1" }
    if lower.contains("beats studio buds +") || lower.contains("beats studio buds+") || id.hasPrefix("BeatsStudioBuds1,2") || id == "Beats-28" || lower == "a2870" || lower == "a2871" || lower == "a2872" { return "BeatsStudioBuds1,2" }
    if lower.contains("beats studio buds") || id.hasPrefix("BeatsStudioBuds1,1") || lower == "a2512" || lower == "a2513" || lower == "a2514" { return "BeatsStudioBuds1,1" }
    if lower.contains("powerbeats fit") || id.hasPrefix("Powerbeats Fit") || id == "PowerbeatsFit" || lower == "a3476" || lower == "a3477" || lower == "a3479" { return "PowerbeatsFit" }
    if lower.contains("powerbeats pro 2") || id.hasPrefix("Powerb3,1") || lower == "a3157" || lower == "a3158" || lower == "a3160" { return "Powerb3,1" }
    if lower.contains("powerbeats pro") || id.hasPrefix("PowerbeatsPro1,1") || id.hasPrefix("PowerbeatsPro2,1") || id == "Beats-26" || lower == "a2047" || lower == "a2048" || lower == "a2078" { return "PowerbeatsPro1,1" }
    if let record = SearchCatalogProductIndex.records.first(where: {
        $0.id == id || $0.id.lowercased() == lower ||
        $0.model == id || $0.model.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains(id) ||
        $0.name.lowercased() == lower
    }), !record.legacyCatalogID.isEmpty {
        return record.legacyCatalogID
    }
    if let prod = SearchCatalogProductIndex.products.first(where: {
        $0.id == id || $0.id.lowercased() == lower || $0.name.lowercased() == lower
    }), let leg = prod.records.first(where: { !$0.legacyCatalogID.isEmpty })?.legacyCatalogID {
        return leg
    }
    return id
}

func deviceColors(for id: String) -> [String]? {
    let key = resolveColorDeviceKey(for: id)
    let candidateKeys = (key == id) ? [id] : [key, id]
    var savedColors: [String] = []
    for k in candidateKeys {
        if let options = deviceColorOptions[k] {
            savedColors.append(contentsOf: options)
        }
        if let catalogColors = SearchCatalogArtworkIndex.colorsByLegacyID[k] {
            savedColors.append(contentsOf: catalogColors)
        }
    }
    if savedColors.isEmpty {
        let lower = id.lowercased()
        if let record = SearchCatalogProductIndex.records.first(where: {
            $0.id == id || $0.id.lowercased() == lower ||
            $0.name.lowercased() == lower ||
            $0.model == id
        }), !record.colors.isEmpty {
            savedColors.append(contentsOf: record.colors.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        if savedColors.isEmpty {
            if let prod = SearchCatalogProductIndex.products.first(where: {
                $0.id == id || $0.id.lowercased() == lower || $0.name.lowercased() == lower
            }) {
                for r in prod.records where !r.colors.isEmpty {
                    for c in r.colors.components(separatedBy: ", ").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                        if !savedColors.contains(c) { savedColors.append(c) }
                    }
                }
            }
        }
    }
    var colors: [String] = []
    for color in savedColors {
        let label = deviceColorLabel(color)
        guard !label.isEmpty else { continue }
        if colors.contains(label) { continue }
        colors.append(label)
    }
    return colors.isEmpty ? nil : colors
}

func deviceColorToken(_ color: String?) -> String? {
    guard let color else { return nil }
    let raw = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch raw {
    case "college white", "collegewhite", "学院白": return "CollegeWhite"
    case "college red", "collegered", "学院红": return "CollegeRed"
    case "college yellow", "collegeyellow", "学院黄": return "CollegeYellow"
    case "college blue", "collegeblue", "学院蓝": return "CollegeBlue"
    case "electric red", "electricred", "闪电红": return "ElectricRed"
    case "defiant black-red", "defiant black/red", "defiant red", "defiant": return "DefiantBlackRed"
    case "gloss white", "glosswhite": return "GlossWhite"
    case "gloss black", "glossblack": return "GlossBlack"
    case "matte black", "matteblack": return "MatteBlack"
    case "satin gold", "satingold": return "SatinGold"
    case "satin silver", "satinsilver": return "SatinSilver"
    case "club navy", "clubnavy": return "ClubNavy"
    case "club red", "clubred": return "ClubRed"
    case "club yellow", "clubyellow": return "ClubYellow"
    case "club white", "clubwhite": return "ClubWhite"
    case "cloud pink", "cloudpink", "猛男粉": return "CloudPink"
    case "slate blue", "slateblue": return "SlateBlue"
    case "gravel gray", "gravelgray": return "GravelGray"
    case "jet black", "jetblack": return "JetBlack"
    case "power pink", "powerpink": return "PowerPink"
    case "spark orange", "sparkorange": return "SparkOrange"
    case "arctic purple", "arcticpurple": return "ArcticPurple"
    case "storm gray", "stormgray": return "StormGray"
    case "transparent red", "transparentred": return "TransparentRed"
    case "champagne gold", "champagnegold": return "ChampagneGold"
    case "statement red", "statementred": return "StatementRed"
    case "black gold", "blackgold", "black / gold", "black/gold": return "BlackGold"
    case "deep brown", "deepbrown", "棕色": return "DeepBrown"
    case "black & volt", "black volt", "blackvolt": return "BlackVolt"
    case "electric orange", "electricorange": return "ElectricOrange"
    case "hyper purple", "hyperpurple": return "HyperPurple"
    case "quick sand", "quicksand": return "QuickSand"
    case "sage gray", "sagegray": return "SageGray"
    case "stone purple", "stonepurple": return "StonePurple"
    case "flame blue", "flameblue": return "FlameBlue"
    case "smoke gray", "smokegray": return "SmokeGray"
    case "yuzu yellow", "yuzuyellow": return "YuzuYellow"
    case "beats black", "beatsblack": return "BeatsBlack"
    case "beats white", "beatswhite": return "BeatsWhite"
    case "transparent", "透明": return "Transparent"
    case "cloud", "云白": return "Cloud"
    case "sky", "天空蓝": return "Sky"
    case "sandstone": return "Sandstone"
    case "glacier", "glacier blue", "冰川", "冰川色", "冰川蓝": return "Glacier"
    case "burgundy", "勃艮第", "酒红", "勃艮第红": return "Burgundy"
    case "soft pink", "softpink", "柔粉", "浅粉": return "SoftPink"
    case "cloud white", "cloudwhite": return "CloudWhite"
    case "mist blue", "mistblue", "雾蓝", "薄雾蓝": return "MistBlue"
    case "lavender", "薰衣草", "薰衣草紫": return "Lavender"
    case "light gold", "lightgold", "浅金": return "LightGold"
    case "dark bronze", "darkbronze", "深青铜", "青铜": return "DarkBronze"
    case "night blue", "nightblue", "夜蓝": return "NightBlue"
    case "pearl white", "pearlwhite", "珍珠白": return "PearlWhite"
    case "radiant gold", "radiantgold", "辉光金": return "RadiantGold"
    case "白色", "white": return "White"
    case "深空灰色", "太空灰色", "space gray", "space grey", "gray", "grey": return "SpaceGray"
    case "午夜色", "午夜", "midnight", "midnight black": return "Midnight"
    case "暗夜绿色", "午夜绿色", "midnight green": return "MidnightGreen"
    case "蓝色", "blue": return "Blue"
    case "天蓝色", "sky blue", "skyblue", "sky": return "SkyBlue"
    case "橙色", "橘色", "orange": return "Orange"
    case "星宇橙色", "宇宙橙色", "cosmic orange", "cosmicorange": return "CosmicOrange"
    case "深蓝色", "deep blue", "deepblue": return "DeepBlue"
    case "深紫色", "deep purple": return "DeepPurple"
    case "暗紫色", "dark purple": return "DarkPurple"
    case "紫色", "purple": return "Purple"
    case "星光色", "starlight": return "Starlight"
    case "银色", "silver", "white & silver": return "Silver"
    case "金色", "gold": return "Gold"
    case "香槟金", "champagne gold": return "Gold"
    case "玫瑰金色", "玫瑰金", "rose gold": return "RoseGold"
    case "玫瑰粉色", "rose pink": return "RosePink"
    case "黄色", "yellow": return "Yellow"
    case "粉色", "猛男粉", "pink": return "Pink"
    case "绿色", "green": return "Green"
    case "苍岭绿色", "alpine green": return "AlpineGreen"
    case "远峰蓝色", "sierra blue": return "SierraBlue"
    case "红色", "red", "(product)red": return "Red"
    case "黑色", "black", "小黑", "black & slate": return "Black"
    case "亮黑色", "jet black": return "JetBlack"
    case "深空黑色", "space black": return "SpaceBlack"
    case "石墨色", "graphite": return "Graphite"
    case "原色钛金属", "natural titanium": return "NaturalTitanium"
    case "白色钛金属", "white titanium": return "WhiteTitanium"
    case "黑色钛金属", "black titanium": return "BlackTitanium"
    case "原色", "natural": return "Natural"
    case "沙漠色钛金属", "desert titanium": return "DesertTitanium"
    case "深蓝色钛金属", "blue titanium": return "BlueTitanium"
    case "ivory": return "Ivory"
    case "navy": return "Navy"
    case "sandstone": return "Sandstone"
    case "moss": return "Moss"
    case "dune": return "Dune"
    case "earth": return "Earth"
    case "moon": return "Moon"
    default:
        if raw.contains("mickey") || raw.contains("米奇") { return "Mickey90th" }
        if raw.contains("college white") || raw.contains("学院白") { return "CollegeWhite" }
        if raw.contains("college red") || raw.contains("学院红") { return "CollegeRed" }
        if raw.contains("college yellow") || raw.contains("学院黄") { return "CollegeYellow" }
        if raw.contains("college blue") || raw.contains("学院蓝") { return "CollegeBlue" }
        if raw.contains("electric red") || raw.contains("闪电红") { return "ElectricRed" }
        if raw.contains("defiant") { return "DefiantBlackRed" }
        if raw.contains("gloss white") { return "GlossWhite" }
        if raw.contains("gloss black") { return "GlossBlack" }
        if raw.contains("matte black") { return "MatteBlack" }
        if raw.contains("satin gold") { return "SatinGold" }
        if raw.contains("satin silver") { return "SatinSilver" }
        if raw.contains("titanium") || raw.contains("钛") {
            if raw.contains("black") || raw.contains("黑") { return "BlackTitanium" }
            if raw.contains("white") || raw.contains("白") { return "WhiteTitanium" }
            if raw.contains("gold") || raw.contains("金") { return "GoldTitanium" }
            if raw.contains("slate") { return "SlateTitanium" }
            return "NaturalTitanium"
        }
        if raw.contains("ceramic") {
            if raw.contains("gray") || raw.contains("grey") { return "GrayCeramic" }
            return "WhiteCeramic"
        }
        if raw.contains("ivory") { return "Ivory" }
        if raw.contains("navy") { return "Navy" }
        if raw.contains("moss") || raw.contains("olive") { return "Moss" }
        if raw.contains("sandstone") || raw.contains("beige") { return "Sandstone" }
        if raw.contains("dune") { return "Dune" }
        if raw.contains("earth") || raw.contains("deep brown") { return "Earth" }
        if raw.contains("moon") { return "Moon" }
        if raw.contains("slate blue") || raw.contains("tidal blue") { return "SlateBlue" }
        if raw.contains("cloud pink") || raw.contains("blush") { return "CloudPink" }
        if raw.contains("transparent") { return "Transparent" }
        if raw.contains("coral") || raw.contains("guava") { return "Coral" }
        if raw.contains("volt") || raw.contains("yuzu") { return "Volt" }
        if raw.contains("sage") { return "SageGray" }
        if raw.contains("stone purple") { return "StonePurple" }
        if raw.contains("bronze") { return "DarkBronze" }
        if raw.contains("indigo") { return "Indigo" }
        if raw.contains("glacier") || raw.contains("冰川") { return "Glacier" }
        if raw.contains("burgundy") || raw.contains("勃艮第") { return "Burgundy" }
        if raw.contains("soft pink") || raw.contains("柔粉") { return "SoftPink" }
        if raw.contains("cloud white") || raw.contains("云白") { return "CloudWhite" }
        if raw.contains("mist blue") || raw.contains("雾蓝") { return "MistBlue" }
        if raw.contains("lavender") || raw.contains("薰衣草") { return "Lavender" }
        if raw.contains("light gold") || raw.contains("浅金") { return "LightGold" }
        if raw.contains("dark bronze") || raw.contains("深青铜") { return "DarkBronze" }
        if raw.contains("night blue") || raw.contains("夜蓝") { return "NightBlue" }
        if raw.contains("pearl white") || raw.contains("珍珠白") { return "PearlWhite" }
        if raw.contains("radiant gold") || raw.contains("辉光金") { return "RadiantGold" }
        if raw.contains("橙") || raw.contains("orange") {
            if raw.contains("宇宙") || raw.contains("星宇") || raw.contains("cosmic") { return "CosmicOrange" }
            return "Orange"
        }
        if raw.contains("深蓝") || raw.contains("deep blue") { return "DeepBlue" }
        if raw.contains("天蓝") || raw.contains("sky blue") { return "SkyBlue" }
        if raw.contains("蓝") || raw.contains("blue") { return "Blue" }
        if raw.contains("黑") || raw.contains("black") {
            if raw.contains("深空") || raw.contains("space") { return "SpaceBlack" }
            if raw.contains("亮") || raw.contains("jet") { return "JetBlack" }
            return "Black"
        }
        if raw.contains("白") || raw.contains("white") { return "White" }
        if raw.contains("银") || raw.contains("silver") { return "Silver" }
        if raw.contains("金") || raw.contains("gold") {
            if raw.contains("玫瑰") || raw.contains("rose") { return "RoseGold" }
            return "Gold"
        }
        if raw.contains("粉") || raw.contains("pink") { return "Pink" }
        if raw.contains("红") || raw.contains("red") { return "Red" }
        if raw.contains("绿") || raw.contains("green") { return "Green" }
        if raw.contains("黄") || raw.contains("yellow") { return "Yellow" }
        if raw.contains("紫") || raw.contains("purple") { return "Purple" }
        if raw.contains("灰") || raw.contains("gray") || raw.contains("grey") { return "SpaceGray" }
        if raw.contains("星光") || raw.contains("starlight") { return "Starlight" }
        if raw.contains("午夜") || raw.contains("midnight") { return "Midnight" }
        
        let alphanumeric = raw.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return alphanumeric.isEmpty ? nil : alphanumeric.capitalized
    }
}

/// 为 AirPods 各型号统一匹配其专属充电盒外观图（避免单耳散装图）
func airPodsCaseArtwork(for identifier: String, name: String = "") -> String? {
    let text = "\(identifier) \(name)".lowercased()
    guard text.contains("airpod") else { return nil }
    
    // 排除有线入耳式耳机 (Apple In-Ear Headphones) 和 EarPods
    if text.contains("in ear") || text.contains("in-ear") || text.contains("earpod") || text.contains("airpods-1") || text.contains("airpods-x") || text.contains("a1307") || text.contains("a3046") || text.contains("a1748") || text.contains("a1472") {
        return nil
    }
    
    // AirPods Max 头戴式耳机官方外观 (1代用老图，2代及USB-C用新图)
    if text.contains("max") || text.contains("airpods-5") || text.contains("airpods-10") || text.contains("a2096") || text.contains("a3454") || text.contains("a3184") {
        if text.contains("usb-c") || text.contains("usbc") || text.contains("max 2") || text.contains("max2") || text.contains("a3454") || text.contains("a3184") || text.contains("airpods-10") || text.contains("airpodsmax1,2") || text.contains("airpodsmax1,1-usbc") {
            return "catalog_AirPodsMax1_1-usbc_cdc7882a"
        }
        return "catalog_AirPodsMax1_1_56607ec7"
    }
    
    // AirPods Pro 系列（全系使用充电盒外观）
    if text.contains("pro") {
        if text.contains("pro 2") || text.contains("pro2") || text.contains("pro 3") || text.contains("pro3") || text.contains("a3049") || text.contains("a3122") || text.contains("airpods-7") || text.contains("airpods-9") || text.contains("airpodspro1,2") || text.contains("airpodspro1,3") {
            return "catalog_AirPodsPro1_2-usbc-case_a5786e2f"
        }
        // AirPods Pro 1代
        return "catalog_AirPodsPro1_1-case_37b9681c"
    }
    
    // AirPods 标准系列（全系使用充电盒外观）
    if text.contains("airpods 4") || text.contains("airpods4") || text.contains("airpods1,5") || text.contains("airpods-8") || text.contains("a3057") {
        return "catalog_AirPods1_5-case_47d71e0f"
    }
    if text.contains("airpods1,4") {
        return "catalog_AirPods1_4-case_830f7990"
    }
    if text.contains("airpods 3") || text.contains("airpods3") || text.contains("airpods1,3") || text.contains("airpods-6") || text.contains("a2565") {
        return "catalog_AirPods1_3-magsafe-case_961f6c80"
    }
    if text.contains("airpods 2") || text.contains("airpods2") || text.contains("airpods1,2") || text.contains("airpods-3") || text.contains("a2032") {
        return "catalog_AirPods1_2-case_54e1089d"
    }
    if text.contains("airpods 1") || text.contains("airpods1") || text.contains("airpods1,1") || text.contains("airpods-2") || text.contains("a1523") || text.contains("airpods") {
        return "catalog_AirPods1_1-case_3cd1f113"
    }
    
    return nil
}

/// 为 Beats 耳机型号统一匹配其专属充电盒外观图（避免单耳散装图）
func beatsCaseArtwork(for identifier: String, name: String = "") -> String? {
    if identifier == "Beats-26" {
        return "catalog_PowerbeatsPro1_1-case_45beb30f"
    }
    if identifier == "Beats-28" {
        return "catalog_BeatsStudioBuds1_2-case_dcd80d0a"
    }
    if let baseID = airPodsSetBaseID(identifier), (baseID.hasPrefix("Beats") || baseID.hasPrefix("Power")) {
        if let caseArt = SearchCatalogArtworkIndex.names["\(baseID)-case"] ?? SearchCatalogArtworkIndex.names["\(baseID)-magsafe-case"] {
            return caseArt
        }
    }
    let text = "\(identifier) \(name)".lowercased()
    guard text.contains("beats") || text.contains("powerbeats") else { return nil }
    if text.contains("fit pro") {
        return "catalog_BeatsFitPro1_1-case_2a54a027"
    }
    if text.contains("studio buds +") || text.contains("studio buds+") {
        return "catalog_BeatsStudioBuds1_2-case_dcd80d0a"
    }
    if text.contains("studio buds") {
        return "catalog_BeatsStudioBuds1_1-case_062f5304"
    }
    if text.contains("solo buds") {
        return "catalog_BeatsSoloBuds1_1-case_447de0c6"
    }
    if text.contains("powerbeats pro 2") || text.contains("powerb3,1") {
        return "catalog_Powerb3,1-case_4d78a016"
    }
    if text.contains("powerbeats pro") || text.contains("powerbeatspro") {
        if text.contains("2020") || text.contains("powerbeatspro2,1") {
            return "catalog_PowerbeatsPro2_1-case_388270af"
        }
        return "catalog_PowerbeatsPro1_1-case_45beb30f"
    }
    if text.contains("powerbeats fit") {
        return "catalog_Powerbeats_Fit-case_cba7ae13"
    }
    return nil
}

/// AirPods Max 2代 / USB-C 款判定（图片周围留白极多）
func isAirPodsMax2(artworkName: String? = nil, model: String? = nil, catalogID: String? = nil, name: String? = nil) -> Bool {
    if let art = artworkName {
        if art == "catalog_AirPodsMax1_1-usbc_cdc7882a"
            || art.contains("AirPodsMax1,2")
            || art.contains("AirPodsMax1,1-usbc")
            || art.contains("Airpods-10") {
            return true
        }
    }
    if let m = model, m == "A3454" || m == "A3184" {
        return true
    }
    if let cid = catalogID, cid == "AirPodsMax1,2" || cid == "AirPodsMax1,1-usbc" || cid == "Airpods-10" {
        return true
    }
    if let n = name, n.contains("Max 2") || n.localizedCaseInsensitiveContains("usb-c") {
        return true
    }
    return false
}

/// AirPods Max 1代（Lightning 口）：图片紧凑无留白
func isAirPodsMax1(artworkName: String? = nil, model: String? = nil, catalogID: String? = nil, name: String? = nil) -> Bool {
    if isAirPodsMax2(artworkName: artworkName, model: model, catalogID: catalogID, name: name) {
        return false
    }
    if let art = artworkName {
        if art == "catalog_AirPodsMax1_1_56607ec7"
            || (art.contains("AirPodsMax") && !art.contains("usbc") && !art.contains("1,2"))
            || art.contains("Airpods-5") {
            return true
        }
    }
    if let m = model, m == "A2096" {
        return true
    }
    if let cid = catalogID, cid == "AirPodsMax1,1" || cid == "Airpods-5" {
        return true
    }
    if let n = name, (n == "AirPods Max" || n.localizedCaseInsensitiveContains("lightning")) && !n.contains("2") && !n.localizedCaseInsensitiveContains("usb-c") {
        return true
    }
    return false
}

func isAirPodsMax2Device(_ item: CollectionItem) -> Bool {
    isAirPodsMax2(artworkName: item.artworkAssetName, model: item.model, catalogID: item.catalogID, name: item.name)
}

func isAirPodsMax1Device(_ item: CollectionItem) -> Bool {
    isAirPodsMax1(artworkName: item.artworkAssetName, model: item.model, catalogID: item.catalogID, name: item.name)
}

func isAirPodsMaxDevice(_ item: CollectionItem) -> Bool {
    isAirPodsMax2Device(item)
}

/// Powerbeats Pro (Glacier Blue 冰川蓝等留白款)：详情大图需 2x 放大
func isPowerbeatsProGlacier(artworkName: String? = nil, model: String? = nil, catalogID: String? = nil, name: String? = nil, color: String? = nil) -> Bool {
    if let art = artworkName?.lowercased() {
        if (art.contains("powerbeatspro") || art.contains("beats-26")) && (art.contains("glacier") || art.contains("glacierblue")) {
            return true
        }
    }
    if let n = name?.lowercased(), n.contains("powerbeats pro") {
        if let c = color?.lowercased(), c.contains("glacier") {
            return true
        }
    }
    return false
}

func isPowerbeatsProGlacierDevice(_ item: CollectionItem) -> Bool {
    isPowerbeatsProGlacier(artworkName: item.artworkAssetName, model: item.model, catalogID: item.catalogID, name: item.name, color: item.color)
}

/// 获取某硬件官方定义的所有标准配色列表（去重且保序）
func officialColorOptions(for item: CollectionItem) -> [String] {
    let keys = [item.catalogID, item.model, item.colorLookupKey, item.id].compactMap { $0 }.filter { !$0.isEmpty }
    for k in keys {
        if let opts = deviceColorOptions[k], !opts.isEmpty {
            return opts
        }
    }
    if let cid = item.catalogID, let record = SearchCatalogArtworkIndex.records.first(where: { $0.id == cid || $0.legacyCatalogID == cid }) {
        let colors = record.colors.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !colors.isEmpty { return colors }
    }
    if let model = item.model, let record = SearchCatalogArtworkIndex.records.first(where: { $0.model.contains(model) }) {
        let colors = record.colors.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !colors.isEmpty { return colors }
    }
    return []
}

func deviceArtworkAssetName(_ id: String, color: String? = nil) -> String {
    if id == "Lightning to 3.5 mm Headphone Jack Adapter" {
        return "catalog_Lightning_to_3.5_mm_Headphone_Jack_Adapter_81230c96"
    }
    if id == "Airpods-1" || id == "In-Ear Earphones with Remote and Mic" || id == "In-Ear Headphones with Remote and Mic" || id == "Apple In-Ear Headphones with Remote and Mic" || id == "In Ear headphone" {
        return "catalog_In-Ear_Earphones_with_Remote_and_Mic_c0a8e03d"
    }
    // EarPods 有线耳机专属官方外观图
    if id == "Airpods-x" || id == "A3046" || id == "EarPods with USB-C Connector" || id == "Earpods（USB-C）" {
        return "catalog_EarPods_with_USB-C_Connector_e839b810"
    }
    if id == "A1748" || id == "EarPods with Lightning Connector" || id == "Earpods（Lightning）" {
        return "catalog_EarPods_with_Lightning_Connector_e505042e"
    }
    if id == "A1472" || id == "EarPods with 3.5mm Headphone Plug" || id == "EarPods with 3.5 mm Headphone Plug" || id == "Earpods（3.5mm）" {
        return "catalog_EarPods_with_3.5mm_Headphone_Plug_7b9631aa"
    }
    
    // 最高优先级：如果指定了颜色，优先查找色彩专属渲染图（支持所有官方耳机配色图）
    if let token = deviceColorToken(color) {
        let key = resolveColorDeviceKey(for: id)
        var candidateKeys = (key == id) ? [id] : [key, id]
        if let base = airPodsSetBaseID(id), !candidateKeys.contains(base) {
            candidateKeys.append(base)
        }
        var tokens = [token]
        if token == "SkyBlue" { tokens.append("Blue") }
        if token == "Blue" { tokens.append("SkyBlue") }
        if token == "Midnight" { tokens.append("SpaceGray") }
        if token == "SpaceGray" { tokens.append("Midnight") }
        if token == "Glacier" { tokens.append("GlacierBlue"); tokens.append("Blue") }
        if token == "GlacierBlue" { tokens.append("Glacier"); tokens.append("Blue") }
        for k in candidateKeys {
            for t in tokens {
                let colorAssetName = "device_\(k)_color_\(t)"
                if imageAssetExists(colorAssetName) { return colorAssetName }
            }
        }
    }
    
    // Beats Solo3 专属官方艺术图精确回溯（米奇 90 周年、学院蓝、Line Friends等）
    if id == "BeatsSolo3,1" || id == "Beats-15" || id.hasPrefix("BeatsSolo3,1") {
        let c = (color ?? "").lowercased()
        if c.contains("米奇") || c.contains("mickey") || id == "BeatsSolo3,1-mickey" {
            return "catalog_BeatsSolo3_1-mickey_525665f6"
        }
        if c.contains("蓝") || c.contains("navy") || c.contains("blue") || id == "BeatsSolo3,1-nayva" {
            return "catalog_BeatsSolo3_1-nayva_c128ede4"
        }
        if c.contains("line") || id == "BeatsSolo3,1-line" {
            return "catalog_BeatsSolo3_1-line_1ef8b6bd"
        }
        if c.contains("thirdman") || id == "BeatsSolo3,1-thirdman" {
            return "catalog_BeatsSolo3_1-thirdman_a77b00af"
        }
        if c.contains("newyear") || id == "BeatsSolo3,1-newyears" {
            return "catalog_BeatsSolo3_1-newyears_03082beb"
        }
        return "catalog_BeatsSolo3_1_1d4e9ea1"
    }
    
    // AirPods 统一优先解析为充电盒外观图，避免单只左耳或右耳零散展示
    if let airPodsCase = airPodsCaseArtwork(for: id) {
        return airPodsCase
    }
    
    // Beats 耳机统一优先解析为充电盒外观图，避免单只左耳或右耳零散展示
    if let beatsCase = beatsCaseArtwork(for: id) {
        return beatsCase
    }
    if id == "Adapter-23" || id == "A1731" {
        return "catalog_Beats_by_Dr._Dre_10W_USB_Power_Adapter_63d59466"
    }
    if id == "Adapter-39" || id == "MD837FE/A" || id.contains("World Travel") {
        return "catalog_Apple_World_Travel_Adapter_Kit_CHN_f61d4053"
    }
    if id == "Apple Composite AV Cable" || id == "Composite AV Cable" || id == "A1258" {
        return "catalog_Composite_AV_Cable_051efbe3"
    }
    if id == "Apple Component AV Cable" || id == "Component AV Cable" || id == "A1259" {
        return "catalog_Component_AV_Cable_65de7548"
    }
    if id == "Apple-III" || id == "Apple III" || id == "Apple ///" {
        return "catalog_Apple_III"
    }
    if id == "Apple-III-Plus" || id == "Apple III Plus" || id == "Apple /// Plus" {
        return "catalog_Apple_III_Plus"
    }
    if id == "iPod-7" || id == "iPod with video-u2" || id == "iPod with video-lateu2" || id == "iPod with video U2 Edition" || id == "iPod video U2" {
        return "catalog_iPod_with_video-u2_d50928e4"
    }
    if let catalogArtwork = SearchCatalogArtworkIndex.names[id] ?? SearchCatalogArtworkIndex.namesByLegacyID[id] ?? SearchCatalogArtworkIndex.namesByModel[id] {
        return catalogArtwork
    }
    return "device_\(id)"
}

func colorSwatch(_ color: String) -> Color {
    let lower = color.lowercased()
    
    // Beats & Watch 专属丰富配色
    if lower.contains("college blue") || lower.contains("学院蓝") { return Color(red: 0.12, green: 0.25, blue: 0.55) }
    if lower.contains("college red") || lower.contains("学院红") { return Color(red: 0.85, green: 0.15, blue: 0.18) }
    if lower.contains("college yellow") || lower.contains("学院黄") { return Color(red: 0.98, green: 0.82, blue: 0.12) }
    if lower.contains("college white") || lower.contains("学院白") { return Color(red: 0.95, green: 0.95, blue: 0.95) }
    if lower.contains("club navy") { return Color(red: 0.12, green: 0.18, blue: 0.35) }
    if lower.contains("club red") { return Color(red: 0.85, green: 0.15, blue: 0.18) }
    if lower.contains("club yellow") { return Color(red: 0.98, green: 0.82, blue: 0.12) }
    if lower.contains("club white") { return Color(red: 0.95, green: 0.95, blue: 0.95) }
    if lower.contains("electric red") || lower.contains("闪电红") { return Color(red: 0.88, green: 0.08, blue: 0.12) }
    if lower.contains("defiant") { return Color(red: 0.82, green: 0.10, blue: 0.12) }
    if lower.contains("米奇") || lower.contains("mickey") { return Color(red: 0.78, green: 0.78, blue: 0.80) }
    if lower.contains("cloud pink") || lower.contains("猛男粉") { return Color(red: 0.95, green: 0.75, blue: 0.82) }
    if lower.contains("gravel gray") { return Color(red: 0.55, green: 0.55, blue: 0.58) }
    if lower.contains("jet black") { return Color(red: 0.10, green: 0.10, blue: 0.12) }
    if lower.contains("power pink") { return Color(red: 0.96, green: 0.45, blue: 0.65) }
    if lower.contains("spark orange") || lower.contains("electric orange") { return Color(red: 0.98, green: 0.45, blue: 0.12) }
    if lower.contains("arctic purple") || lower.contains("hyper purple") { return Color(red: 0.55, green: 0.28, blue: 0.72) }
    if lower.contains("storm gray") || lower.contains("smoke gray") { return Color(red: 0.48, green: 0.50, blue: 0.54) }
    if lower.contains("transparent red") || lower.contains("statement red") { return Color(red: 0.88, green: 0.12, blue: 0.16) }
    if lower.contains("champagne gold") { return Color(red: 0.88, green: 0.78, blue: 0.58) }
    if lower.contains("black gold") || lower.contains("black / gold") { return Color(red: 0.20, green: 0.18, blue: 0.14) }
    if lower.contains("quick sand") { return Color(red: 0.82, green: 0.75, blue: 0.65) }
    if lower.contains("black & volt") { return Color(red: 0.15, green: 0.15, blue: 0.15) }
    if lower.contains("flame blue") { return Color(red: 0.15, green: 0.45, blue: 0.85) }
    if lower.contains("yuzu yellow") { return Color(red: 0.88, green: 0.92, blue: 0.22) }
    if lower.contains("sky") { return Color(red: 0.55, green: 0.75, blue: 0.92) }
    if lower.contains("ivory") { return Color(red: 0.94, green: 0.92, blue: 0.86) }
    if lower.contains("sandstone") || lower.contains("beige") || lower.contains("summit stone") { return Color(red: 0.86, green: 0.82, blue: 0.74) }
    if lower.contains("dune") { return Color(red: 0.76, green: 0.66, blue: 0.56) }
    if lower.contains("earth") || lower.contains("deep brown") || lower.contains("brown") { return Color(red: 0.42, green: 0.30, blue: 0.22) }
    if lower.contains("moon") || lower.contains("cloud") { return Color(red: 0.82, green: 0.80, blue: 0.78) }
    if lower.contains("slate blue") || lower.contains("tidal blue") { return Color(red: 0.32, green: 0.45, blue: 0.58) }
    if lower.contains("navy") { return Color(red: 0.12, green: 0.20, blue: 0.35) }
    if lower.contains("moss") || lower.contains("olive") { return Color(red: 0.33, green: 0.40, blue: 0.28) }
    if lower.contains("volt") || lower.contains("yuzu") || lower.contains("neon") { return Color(red: 0.84, green: 0.95, blue: 0.15) }
    if lower.contains("coral") || lower.contains("guava") { return Color(red: 0.95, green: 0.45, blue: 0.38) }
    if lower.contains("transparent") { return Color(red: 0.82, green: 0.84, blue: 0.88) }
    if lower.contains("sage") { return Color(red: 0.52, green: 0.58, blue: 0.54) }
    if lower.contains("bronze") { return Color(red: 0.48, green: 0.38, blue: 0.30) }
    if lower.contains("indigo") { return Color(red: 0.22, green: 0.25, blue: 0.48) }
    if lower.contains("ceramic") { return Color(red: 0.96, green: 0.96, blue: 0.96) }
    if lower.contains("platinum") { return Color(red: 0.88, green: 0.86, blue: 0.82) }
    if lower.contains("stone purple") { return Color(red: 0.55, green: 0.48, blue: 0.58) }
    if lower.contains("glacier") || lower.contains("冰川") { return Color(red: 0.82, green: 0.88, blue: 0.92) }
    if lower.contains("burgundy") || lower.contains("勃艮第") { return Color(red: 0.50, green: 0.12, blue: 0.20) }
    if lower.contains("soft pink") || lower.contains("柔粉") { return Color(red: 0.96, green: 0.80, blue: 0.84) }
    if lower.contains("cloud white") || lower.contains("云白") { return Color(red: 0.95, green: 0.95, blue: 0.96) }
    if lower.contains("mist blue") || lower.contains("雾蓝") { return Color(red: 0.70, green: 0.80, blue: 0.88) }
    if lower.contains("lavender") || lower.contains("薰衣草") { return Color(red: 0.78, green: 0.72, blue: 0.86) }
    if lower.contains("light gold") || lower.contains("浅金") { return Color(red: 0.90, green: 0.82, blue: 0.65) }
    if lower.contains("dark bronze") || lower.contains("深青铜") { return Color(red: 0.45, green: 0.35, blue: 0.25) }
    if lower.contains("night blue") || lower.contains("夜蓝") { return Color(red: 0.10, green: 0.15, blue: 0.28) }
    if lower.contains("pearl white") || lower.contains("珍珠白") { return Color(red: 0.95, green: 0.94, blue: 0.92) }
    if lower.contains("radiant gold") || lower.contains("辉光金") { return Color(red: 0.86, green: 0.76, blue: 0.52) }

    let token = deviceColorToken(color)
    switch token {
    case "Red":
        return Color(red: 0.90, green: 0.15, blue: 0.15)
    case "Gold":
        return Color(red: 0.88, green: 0.74, blue: 0.45)
    case "RoseGold":
        return Color(red: 0.91, green: 0.65, blue: 0.65)
    case "RosePink", "Pink":
        return Color(red: 0.95, green: 0.58, blue: 0.68)
    case "Blue":
        return Color(red: 0.18, green: 0.52, blue: 0.88)
    case "DeepBlue":
        return Color(red: 0.10, green: 0.25, blue: 0.45)
    case "SkyBlue":
        return Color(red: 0.45, green: 0.70, blue: 0.90)
    case "SierraBlue":
        return Color(red: 0.53, green: 0.67, blue: 0.80)
    case "Green":
        return Color(red: 0.28, green: 0.68, blue: 0.45)
    case "AlpineGreen", "MidnightGreen":
        return Color(red: 0.22, green: 0.38, blue: 0.30)
    case "Yellow":
        return Color(red: 0.96, green: 0.82, blue: 0.25)
    case "Orange", "CosmicOrange":
        return Color(red: 0.95, green: 0.50, blue: 0.15)
    case "Purple", "DeepPurple", "DarkPurple":
        return Color(red: 0.65, green: 0.45, blue: 0.85)
    case "Black", "SpaceBlack", "JetBlack", "BlackTitanium":
        return Color(red: 0.12, green: 0.12, blue: 0.14)
    case "SpaceGray", "Graphite":
        return Color(red: 0.38, green: 0.40, blue: 0.43)
    case "Midnight":
        return Color(red: 0.12, green: 0.16, blue: 0.24)
    case "Silver", "White", "WhiteTitanium":
        return Color(red: 0.92, green: 0.92, blue: 0.94)
    case "Starlight":
        return Color(red: 0.93, green: 0.90, blue: 0.85)
    case "Natural", "NaturalTitanium":
        return Color(red: 0.76, green: 0.74, blue: 0.70)
    case "DesertTitanium":
        return Color(red: 0.78, green: 0.70, blue: 0.62)
    case "BlueTitanium":
        return Color(red: 0.25, green: 0.33, blue: 0.45)
    default:
        break
    }

    if lower.contains("星宇") || lower.contains("宇宙橙") || lower.contains("cosmic") { return Color(red: 0.95, green: 0.50, blue: 0.15) }
    if lower.contains("深蓝") || lower.contains("deep blue") { return Color(red: 0.10, green: 0.25, blue: 0.45) }
    if lower.contains("天蓝") || lower.contains("sky blue") { return Color(red: 0.45, green: 0.70, blue: 0.90) }
    if lower.contains("玫瑰") || lower.contains("rose") { return Color(red: 0.91, green: 0.65, blue: 0.65) }
    if lower.contains("红") || lower.contains("red") { return Color(red: 0.90, green: 0.15, blue: 0.15) }
    if lower.contains("金") || lower.contains("gold") { return Color(red: 0.88, green: 0.74, blue: 0.45) }
    if lower.contains("粉") || lower.contains("pink") { return Color(red: 0.95, green: 0.58, blue: 0.68) }
    if lower.contains("绿") || lower.contains("green") { return Color(red: 0.28, green: 0.68, blue: 0.45) }
    if lower.contains("蓝") || lower.contains("blue") { return Color(red: 0.18, green: 0.52, blue: 0.88) }
    if lower.contains("紫") || lower.contains("purple") { return Color(red: 0.65, green: 0.45, blue: 0.85) }
    if lower.contains("黄") || lower.contains("yellow") { return Color(red: 0.96, green: 0.82, blue: 0.25) }
    if lower.contains("橙") || lower.contains("橘") || lower.contains("orange") { return Color(red: 0.95, green: 0.50, blue: 0.15) }
    if lower.contains("黑") || lower.contains("black") || lower.contains("午夜") || lower.contains("midnight") { return Color(red: 0.12, green: 0.12, blue: 0.14) }
    if lower.contains("灰") || lower.contains("gray") || lower.contains("grey") || lower.contains("石墨") { return Color(red: 0.38, green: 0.40, blue: 0.43) }
    if lower.contains("白") || lower.contains("white") || lower.contains("银") || lower.contains("silver") || lower.contains("星光") || lower.contains("starlight") { return Color(red: 0.92, green: 0.92, blue: 0.94) }
    if lower.contains("原色") || lower.contains("natural") { return Color(red: 0.76, green: 0.74, blue: 0.70) }
    return Color(red: 0.18, green: 0.52, blue: 0.88)
}

func deviceColorLabel(_ color: String) -> String {
    let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }
    
    // 如果包含 " / " 双语分割，优先提取英文字段
    if trimmed.contains("/") {
        let parts = trimmed.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let englishPart = parts.last(where: { $0.rangeOfCharacter(from: CharacterSet.letters) != nil }) {
            return englishPart
        }
    }

    // 规范化表壳与联名格式，去除冗余横线并生成标准英文标签
    if trimmed.hasPrefix("Titanium - ") {
        let suffix = trimmed.replacingOccurrences(of: "Titanium - ", with: "")
        return "\(suffix) Titanium"
    }
    if trimmed.hasPrefix("Stainless Steel - ") {
        let suffix = trimmed.replacingOccurrences(of: "Stainless Steel - ", with: "")
        return "\(suffix) Stainless Steel"
    }
    if trimmed.hasPrefix("Ceramic - ") {
        let suffix = trimmed.replacingOccurrences(of: "Ceramic - ", with: "")
        return "\(suffix) Ceramic"
    }
    if trimmed.hasPrefix("Gold - ") {
        return trimmed.replacingOccurrences(of: "Gold - ", with: "")
    }
    if trimmed.hasPrefix("Kim K Edition - ") {
        return trimmed.replacingOccurrences(of: "Kim K Edition - ", with: "")
    }

    let normalized = trimmed.lowercased()
    if normalized.contains("college blue") || normalized.contains("学院蓝") { return "College Blue" }
    if normalized.contains("college red") || normalized.contains("学院红") { return "College Red" }
    if normalized.contains("college yellow") || normalized.contains("学院黄") { return "College Yellow" }
    if normalized.contains("college white") || normalized.contains("学院白") { return "College White" }
    if normalized.contains("electric red") || normalized.contains("闪电红") { return "Electric Red" }
    if normalized.contains("mickey") || normalized.contains("米奇") { return "Mickey’s 90th Anniversary" }
    if normalized.contains("defiant black-red") || normalized.contains("defiant black/red") || normalized.contains("defiant") { return "Defiant Black-Red" }
    if normalized.contains("club navy") { return "Club Navy" }
    if normalized.contains("club red") { return "Club Red" }
    if normalized.contains("club yellow") { return "Club Yellow" }
    if normalized.contains("club white") { return "Club White" }
    if normalized.contains("gloss white") { return "Gloss White" }
    if normalized.contains("gloss black") { return "Gloss Black" }
    if normalized.contains("matte black") { return "Matte Black" }
    if normalized.contains("satin gold") { return "Satin Gold" }
    if normalized.contains("satin silver") { return "Satin Silver" }
    if normalized.contains("cloud pink") || normalized.contains("猛男粉") { return "Cloud Pink" }
    if normalized.contains("slate blue") { return "Slate Blue" }
    if normalized.contains("gravel gray") { return "Gravel Gray" }
    if normalized.contains("jet black") { return "Jet Black" }
    if normalized.contains("power pink") { return "Power Pink" }
    if normalized.contains("spark orange") { return "Spark Orange" }
    if normalized.contains("electric orange") { return "Electric Orange" }
    if normalized.contains("arctic purple") { return "Arctic Purple" }
    if normalized.contains("hyper purple") { return "Hyper Purple" }
    if normalized.contains("storm gray") { return "Storm Gray" }
    if normalized.contains("smoke gray") { return "Smoke Gray" }
    if normalized.contains("transparent red") { return "Transparent Red" }
    if normalized.contains("statement red") { return "Statement Red" }
    if normalized.contains("champagne gold") { return "Champagne Gold" }
    if normalized.contains("black gold") || normalized.contains("black / gold") { return "Black / Gold" }
    if normalized.contains("deep brown") { return "Deep Brown" }
    if normalized.contains("black & volt") { return "Black & Volt" }
    if normalized.contains("quick sand") { return "Quick Sand" }
    if normalized.contains("sage gray") { return "Sage Gray" }
    if normalized.contains("stone purple") { return "Stone Purple" }
    if normalized.contains("glacier") || normalized.contains("冰川") { return "Glacier" }
    if normalized.contains("burgundy") || normalized.contains("勃艮第") { return "Burgundy" }
    if normalized.contains("soft pink") || normalized.contains("柔粉") { return "Soft Pink" }
    if normalized.contains("cloud white") || normalized.contains("云白") { return "Cloud White" }
    if normalized.contains("mist blue") || normalized.contains("雾蓝") { return "Mist Blue" }
    if normalized.contains("lavender") || normalized.contains("薰衣草") { return "Lavender" }
    if normalized.contains("light gold") || normalized.contains("浅金") { return "Light Gold" }
    if normalized.contains("dark bronze") || normalized.contains("深青铜") { return "Dark Bronze" }
    if normalized.contains("night blue") || normalized.contains("夜蓝") { return "Night Blue" }
    if normalized.contains("pearl white") || normalized.contains("珍珠白") { return "Pearl White" }
    if normalized.contains("radiant gold") || normalized.contains("辉光金") { return "Radiant Gold" }
    if normalized.contains("flame blue") { return "Flame Blue" }
    if normalized.contains("yuzu yellow") { return "Yuzu Yellow" }
    if normalized.contains("beats black") { return "Beats Black" }
    if normalized.contains("beats white") { return "Beats White" }
    if normalized.contains("transparent") || normalized.contains("透明") { return "Transparent" }
    if normalized.contains("cloud") || normalized.contains("云白") { return "Cloud" }
    if normalized.contains("sky") || normalized.contains("天空蓝") { return "Sky" }
    if normalized.contains("标准") || normalized.contains("standard") { return "Standard" }
    if normalized.contains("星白") || normalized.contains("star white") { return "Star White" }
    if normalized.contains("夜空") || normalized.contains("night sky") { return "Night Sky" }
    if normalized.contains("cosmic orange") || normalized.contains("星宇") || normalized.contains("宇宙橙") { return "Cosmic Orange" }
    if normalized.contains("deep blue") || normalized.contains("深蓝") { return "Deep Blue" }
    if normalized.contains("sky blue") || normalized.contains("天蓝") { return "Sky Blue" }
    if normalized.contains("sierra blue") || normalized.contains("远峰蓝") { return "Sierra Blue" }
    if normalized.contains("alpine green") || normalized.contains("苍岭绿") { return "Alpine Green" }
    if normalized.contains("midnight green") || normalized.contains("暗夜绿") { return "Midnight Green" }
    if normalized.contains("space gray") || normalized.contains("space grey") || normalized.contains("深空灰") || normalized.contains("太空灰") { return "Space Gray" }
    if normalized.contains("space black") || normalized.contains("深空黑") { return "Space Black" }
    if normalized.contains("jet black") || normalized.contains("亮黑") { return "Jet Black" }
    if normalized.contains("midnight") || normalized.contains("午夜") { return "Midnight" }
    if normalized.contains("starlight") || normalized.contains("星光") { return "Starlight" }
    if normalized.contains("rose gold") || normalized.contains("玫瑰金") { return "Rose Gold" }
    if normalized.contains("rose pink") || normalized.contains("玫瑰粉") { return "Rose Pink" }
    if normalized.contains("deep purple") || normalized.contains("暗紫") || normalized.contains("深紫") { return "Deep Purple" }
    if normalized.contains("natural titanium") || normalized.contains("原色钛") { return "Natural Titanium" }
    if normalized.contains("white titanium") || normalized.contains("白钛") { return "White Titanium" }
    if normalized.contains("black titanium") || normalized.contains("黑钛") { return "Black Titanium" }
    if normalized.contains("desert titanium") || normalized.contains("沙漠色钛") { return "Desert Titanium" }
    if normalized.contains("blue titanium") || normalized.contains("深蓝钛") { return "Blue Titanium" }
    if normalized.contains("graphite") || normalized.contains("石墨") { return "Graphite" }
    
    // 中文常用色彩转标准官方英文
    if normalized.contains("金") { return "Gold" }
    if normalized.contains("银") { return "Silver" }
    if normalized.contains("白") { return "White" }
    if normalized.contains("黑") { return "Black" }
    if normalized.contains("红") { return "Red" }
    if normalized.contains("蓝") { return "Blue" }
    if normalized.contains("绿") { return "Green" }
    if normalized.contains("粉") { return "Pink" }
    if normalized.contains("黄") { return "Yellow" }
    if normalized.contains("橙") { return "Orange" }
    if normalized.contains("紫") { return "Purple" }
    if normalized.contains("灰") { return "Space Gray" }
    
    return trimmed
}

// MARK: - 集合与持久化辅助函数

func toggleMembership(_ id: String, in binding: Binding<Set<String>>) {
    var ids = binding.wrappedValue
    if ids.contains(id) {
        ids.remove(id)
        CloudVaultSyncManager.shared.recordFavoriteRemoval(ids: [id])
    } else {
        ids.insert(id)
        CloudVaultSyncManager.shared.recordFavoriteAddition(id: id)
    }
    binding.wrappedValue = ids
}

func decodeIDs(from data: Data) -> Set<String> {
    (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
}

func encodeIDs(_ ids: Set<String>) -> Data {
    (try? JSONEncoder().encode(ids)) ?? Data()
}

/// 判断序列号是否属于真实唯一的物理硬件序列号（排除通用占位符及缺失标记）
func isUniqueHardwareSerial(_ sn: String?) -> Bool {
    guard let trimmed = sn?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return false
    }
    let lower = trimmed.lowercased()
    let invalid = ["暂时无法辨认", "未知", "无", "none", "n/a", "null", "丢失", "unknown", "辨认不清", "已磨损", "未标注", "-"]
    if invalid.contains(lower) { return false }
    return trimmed.count >= 6
}
