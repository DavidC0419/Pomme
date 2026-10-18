//
//  BatteryMaintenanceManager.swift
//  Pomme
//
//  老设备防饿死补电日记与周期管理引擎 (Battery Maintenance & Charge Diary Engine)
//  用于管理所有带电池但非日常高频在用的收藏老硬件，提供季度充电提醒、健康度跟踪及一键补电记录。
//

import SwiftUI
import UserNotifications
import Combine

// MARK: - 补电状态分类
enum BatteryMaintenanceStatus: String, CaseIterable, Identifiable, Sendable {
    case overdue       // 濒危已逾期（已超 90 天未充，面临深度放电饿死风险）
    case dueSoon       // 建议近期补电（60~90 天，处于季度维护窗口）
    case healthy       // 状态良好（60 天内刚刚维护过）
    case untracked     // 尚未记录（带电池但未记录初次补电时间）
    case inUse         // 常用在用（日常使用充电中，免受维护限制）

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: return "Overdue · Starvation Risk"
        case .dueSoon: return "Due Soon"
        case .healthy: return "Healthy"
        case .untracked: return "Untracked"
        case .inUse: return "Daily Driver (Exempt)"
        }
    }

    var shortLabel: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueSoon: return "Due Soon"
        case .healthy: return "Good"
        case .untracked: return "Untracked"
        case .inUse: return "In Use"
        }
    }

    var shortLabelChinese: String {
        switch self {
        case .overdue: return "已逾期"
        case .dueSoon: return "建议补电"
        case .healthy: return "状态良好"
        case .untracked: return "未记录"
        case .inUse: return "主力在用"
        }
    }

    var color: Color {
        switch self {
        case .overdue: return .red
        case .dueSoon: return .orange
        case .healthy: return .green
        case .untracked: return .secondary
        case .inUse: return .blue
        }
    }

    var iconName: String {
        switch self {
        case .overdue: return "exclamationmark.triangle.fill"
        case .dueSoon: return "clock.badge.exclamationmark"
        case .healthy: return "checkmark.shield.fill"
        case .untracked: return "questionmark.circle"
        case .inUse: return "sparkles"
        }
    }
}

// MARK: - 补电时剩余电量选项与动态周期调节 (Dynamic Cycle Adaptation Based on Battery Level)
enum BatteryRemainingLevel: String, CaseIterable, Identifiable, Sendable {
    case zero = "0%"
    case under20 = "<20%"
    case from20to50 = "20-50%"
    case from50to80 = "50-80%"
    case from80to100 = "80-100%"
    case noCharge = "NoCharge"
    case unrecorded = "Unrecorded"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zero: return "0%"
        case .under20: return "< 20%"
        case .from20to50: return "20% - 50%"
        case .from50to80: return "50% - 80%"
        case .from80to100: return "80% - 100%"
        case .noCharge: return isChineseLanguage ? "未充电" : "No Charge"
        case .unrecorded: return isChineseLanguage ? "未记录" : "Unrecorded"
        }
    }

    var fullTitle: String {
        switch self {
        case .zero: return isChineseLanguage ? "0% (深度放电 · -10天)" : "0% (Completely Drained · -10 Days)"
        case .under20: return isChineseLanguage ? "低于 20% (电量告急 · -5天)" : "Under 20% (Low Battery · -5 Days)"
        case .from20to50: return isChineseLanguage ? "20% - 50% (中度放电 · 周期不变)" : "20% - 50% (Moderate · No Change)"
        case .from50to80: return isChineseLanguage ? "50% - 80% (电量充裕 · +5天)" : "50% - 80% (Adequate · +5 Days)"
        case .from80to100: return isChineseLanguage ? "80% - 100% (极佳满电 · +10天)" : "80% - 100% (Near Full · +10 Days)"
        case .noCharge: return isChineseLanguage ? "未充电 (电量充足 ≥70% · 周期动态递增)" : "No Charge (Sufficient Battery ≥70% · Dynamic +)"
        case .unrecorded: return isChineseLanguage ? "未记录 (未查电量 / 熄屏)" : "Unrecorded (Not Checked / Screen Off)"
        }
    }

    /// 动态周期调节天数规则：
    /// - 0%: 缩短 10 天 (-10d)，防止再次深度放电饿死；
    /// - 20% 以下: 缩短 5 天 (-5d)，临界放电预警；
    /// - 20-50%: 保持不变 (0d)；
    /// - 50-80%: 增加 5 天 (+5d)，自放电良好；
    /// - 80-100%: 增加 10 天 (+10d)，状态极佳延长周期；
    /// - 未充电: 依据是否满期动态增加 10~30 天；
    /// - 未记录: 保持不变 (0d)。
    var cycleAdjustmentDays: Int {
        switch self {
        case .zero: return -10
        case .under20: return -5
        case .from20to50: return 0
        case .from50to80: return 5
        case .from80to100: return 10
        case .noCharge: return 30
        case .unrecorded: return 0
        }
    }

    var adjustmentBadge: String {
        switch self {
        case .zero: return isChineseLanguage ? "-10天" : "-10 Days"
        case .under20: return isChineseLanguage ? "-5天" : "-5 Days"
        case .from20to50: return isChineseLanguage ? "不变" : "No Change"
        case .from50to80: return isChineseLanguage ? "+5天" : "+5 Days"
        case .from80to100: return isChineseLanguage ? "+10天" : "+10 Days"
        case .noCharge: return isChineseLanguage ? "动态延期" : "Dynamic +"
        case .unrecorded: return isChineseLanguage ? "不变" : "No Change"
        }
    }

    var iconName: String {
        switch self {
        case .zero: return "battery.0percent"
        case .under20: return "battery.25percent"
        case .from20to50: return "battery.50percent"
        case .from50to80: return "battery.75percent"
        case .from80to100: return "battery.100percent"
        case .noCharge: return "battery.75percent"
        case .unrecorded: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .zero: return .red
        case .under20: return .orange
        case .from20to50: return .yellow
        case .from50to80: return .green
        case .from80to100: return .blue
        case .noCharge: return .teal
        case .unrecorded: return .secondary
        }
    }
}

// MARK: - 补电日记核心管理器
@Observable
final class BatteryMaintenanceManager {
    static let shared = BatteryMaintenanceManager()

    /// 默认建议补电周期：每季度一次（90 天）
    static let defaultCycleDays: Int = 90
    static let notificationCategory = "POMME_BATTERY_MAINTENANCE"

    // MARK: - 设备电池属性智能判定
    /// 判断任意藏品是否具备内置可充电电池（需要防饿死管理）
    /// 严格遵循硬件规则：
    /// 1. 配件类中仅 MagSafe Battery Pack、Smart Battery Case 与 AirTag 含有电池；
    /// 2. iPhone Lightning Dock、iPad Dock 等带有产品名称的底座与线材均为纯配件，无电池；
    /// 3. 所有 iPad 专用键盘（Magic Keyboard for iPad、Smart Keyboard、触点键盘）由主机供电，无内置电池；
    /// 4. 独立 Mac 蓝牙键盘、Magic Mouse、Magic Trackpad 等输入设备具备可充锂电或干电池改锂电；
    /// 5. iPhone、iPad、iPod、Apple Watch、AirPods、Vision Pro、MacBook 全系自带电池。
    static func deviceHasRechargeableBattery(_ item: CollectionItem) -> Bool {
        let cat = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (item.resolvedProductName.isEmpty ? item.name : item.resolvedProductName).lowercased()
        let rawName = item.name.lowercased()
        let model = (item.model ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (item.notes ?? "").lowercased()

        // 0. 特例排除：若包含 dock/底座，坚决不作为带电池设备（例如 iPhone Lightning Dock A1717、iPad Keyboard Dock A1359 等）
        let isDock = name.contains("dock") || rawName.contains("dock") || model == "A1717" || model == "A1359"
        if isDock {
            return false
        }

        // 0.1 用户显式指定纳入电池健康与周期管理的特定硬件（包括需定期换电池管理的 A1156 遥控器、A1121 iPod Hi-Fi、AirTag、MagSafe 外接电池等）
        if model == "A1156" || name.contains("a1156") || (name.contains("apple remote") && !name.contains("siri")) {
            return true
        }
        if model == "A1121" || name.contains("a1121") || name.contains("ipod hi-fi") || rawName.contains("ipod hi-fi") {
            return true
        }
        if model == "A2384" || name.contains("magsafe battery") || name.contains("battery pack") {
            return true
        }
        if cat == "AirTag" || cat == "airtag" || name.contains("airtag") || model == "A2187" || model == "A2937" {
            return true
        }

        // 1. 配件与外设分类严格规则：配件里只有 battery pack / battery case 与 AirTag 有电池
        let isAccessoryCategory = cat == "Accessories" || cat == "配件" || cat == "Adapter" || cat == "Adapters" ||
            cat == "Cables" || cat == "Power" || cat == "Power & Charging" || cat == "电源设备" || cat == "Cases" || cat == "保护壳与保护套"

        if isAccessoryCategory {
            if name.contains("battery pack") || name.contains("magsafe battery") || model == "A2384" {
                return true
            }
            if name.contains("battery case") || name.contains("smart battery") {
                return true
            }
            if cat == "AirTag" || name.contains("airtag") || model == "A2187" || model == "A2937" {
                return true
            }
            if name.contains("apple pencil") || model == "A1603" || model == "A2051" || model == "A2538" {
                return true
            }
            if name.contains("siri remote") || model == "A1962" || model == "A2540" {
                return true
            }
            return false
        }

        // 单独排除纯转接头、充电器与线缆
        if name.contains("lightning to") || name.contains("usb-c to") || name.contains("adapter") || name.contains("cable") {
            return false
        }

        // 2. 键盘类规则：所有 iPad 专用键盘无内置电池；仅独立 Mac 蓝牙键盘有电池
        if cat == "键盘" || cat == "Keyboard" || cat == "Keyboards" || name.contains("keyboard") {
            let isIPadKeyboard = name.contains("ipad") || rawName.contains("ipad") ||
                name.contains("smart keyboard") || name.contains("folio") ||
                notes.contains("触点") || notes.contains("smart connector") ||
                model == "A1998" || model == "A2261" || model == "A2480" || model == "A2998" || model == "A2999" || model == "A3000"
            if isIPadKeyboard {
                return false
            }
            // 有线 Mac 键盘排除 (Apple Pro Keyboard, USB Keyboard with Numeric Keypad A1243 等)
            if model == "A1243" || model == "A1048" || notes.contains("wired") || notes.contains("有线") || notes.contains("usb-a") {
                return false
            }
            return true
        }

        // 3. 鼠标与触控板 (Mouse & Trackpad)
        if cat == "鼠标" || cat == "Mouse" || cat == "Mice" || name.contains("mouse") || name.contains("trackpad") {
            if name.contains("mighty mouse") || model == "A1152" || notes.contains("usb-a") || notes.contains("有线") {
                return false
            }
            return true
        }

        // 4. 便携移动终端：全系必然带电池（iPhone、iPad 主机、iPod、Apple Watch、AirPods、Vision Pro）
        if cat == "iPhone" || name.contains("iphone") {
            return true
        }
        if cat == "iPad" || name.contains("ipad") {
            return true
        }
        if cat == "iPod" || name.contains("ipod") {
            return true
        }
        if cat == "AirPods" || cat == "Airpods" || name.contains("airpods") {
            return true
        }
        if cat == "Watch" || cat == "Apple Watch" || name.contains("apple watch") || name.contains("watch") {
            return true
        }
        if cat == "Vision Pro" || cat == "Vision" || name.contains("vision pro") {
            return true
        }

        // 5. Mac 电脑（仅便携款 MacBook / Air / Pro / Neo / iBook / PowerBook 有电池；台式 Mac mini / Mac Pro / iMac / Studio 无电池）
        if cat == "Mac" || name.contains("mac") {
            if name.contains("macbook") || rawName.contains("macbook") ||
               name.contains("powerbook") || name.contains("ibook") {
                return true
            }
            if name.contains("mini") || name.contains("mac pro") || name.contains("studio") || name.contains("imac") || name.contains("xserve") {
                return false
            }
        }

        // 6. Beats 耳机（除明确插线款 urBeats / Beats EP / 3.5mm 线控外，无线款全系有电池）
        if cat == "Beats" || name.contains("beats") {
            if name.contains("urbeats") || name.contains("beats ep") || notes.contains("有线") || notes.contains("wired") {
                return false
            }
            return true
        }

        // 7. 特殊配件特例匹配（如 MagSafe Battery Pack, AirTag）
        if name.contains("battery pack") || name.contains("magsafe battery") || model == "A2384" {
            return true
        }
        if cat == "AirTag" || name.contains("airtag") {
            return true
        }

        // 8. 兜底检查：若用户显式录入了有效电池健康或容量信息，则视为有电池
        if let batt = item.battery?.trimmingCharacters(in: .whitespacesAndNewlines), !batt.isEmpty {
            if batt != "无" && batt != "None" && batt != "N/A" {
                return true
            }
        }

        return false
    }

    // MARK: - 日期解析与计算 (High Performance Date Parsing & Caching)
    private static let candidateFormatters: [DateFormatter] = {
        let formats = ["yyyy-MM-dd", "yyyy-M-d", "yyyy-MM", "yyyy"]
        return formats.map { fmt in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = fmt
            return df
        }
    }()

    private static let outputFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy.MM.dd"
        return df
    }()

    private static var dateParseCache: [String: Date] = [:]
    private static let parseLock = NSLock()

    /// 宽容解析多种格式的补电日期字符串（带极速内存缓存）
    static func parseChargeDate(_ raw: String?) -> Date? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let clean = text.replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: ".", with: "-")
                        .replacingOccurrences(of: " ", with: "")

        parseLock.lock()
        if let cached = dateParseCache[clean] {
            parseLock.unlock()
            return cached
        }
        parseLock.unlock()

        for df in candidateFormatters {
            if let date = df.date(from: clean) {
                parseLock.lock()
                dateParseCache[clean] = date
                parseLock.unlock()
                return date
            }
        }
        return nil
    }

    /// 统一格式化补电日期
    static func formatChargeDate(_ date: Date) -> String {
        outputFormatter.string(from: date)
    }

    /// 计算距上次补电的天数
    static func daysSinceLastCharged(_ item: CollectionItem, relativeTo now: Date = Date()) -> Int? {
        guard let lastDate = parseChargeDate(item.lastCharged) else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDate), to: calendar.startOfDay(for: now))
        return components.day
    }

    // MARK: - 设备专属补电维护周期 (Device Specific Battery Cycles)
    /// 获取藏品当前的有效补电周期（若存在用户/系统动态自适应调优周期则优先使用，否则返回品类基准周期）
    static func cycleDays(for item: CollectionItem) -> Int {
        if let custom = item.customCycleDays, custom > 0 {
            return custom
        }
        return baseCycleDays(for: item)
    }

    /// 根据硬件特性定制的默认基准补电维护周期：
    /// - MagSafe 外接电池 / AirTag / A1156 遥控器 / A1121 iPod Hi-Fi: 180 天
    /// - iPod: 30 天
    /// - 非主力耳机 / 非主力手表 (AirPods, Beats, Apple Watch): 45 天
    /// - 非主力 iPhone: 60 天
    /// - 非主力 iPad: 90 天
    /// - 其他（MacBook、Vision Pro、外设配件等）：默认 90 天
    static func baseCycleDays(for item: CollectionItem) -> Int {
        let cat = item.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = (item.resolvedProductName.isEmpty ? item.name : item.resolvedProductName).lowercased()
        let rawName = item.name.lowercased()
        let model = (item.model ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 0. 特殊长周期设备（MagSafe 外接电池、A1121 iPod Hi-Fi 为 180 天；AirTag 与 A1156 遥控器等 CR2032 纽扣电池超长周期 365 天）
        if cat == "airtag" || name.contains("airtag") || model == "A2187" || model == "A2937" {
            return 365
        }
        if model == "A1156" || name.contains("a1156") || (name.contains("apple remote") && !name.contains("siri")) || model == "A1294" {
            return 365
        }
        if model == "A2384" || name.contains("magsafe battery") || name.contains("battery pack") {
            return 180
        }
        if model == "A1121" || name.contains("a1121") || name.contains("ipod hi-fi") || rawName.contains("ipod hi-fi") {
            return 180
        }

        // 1. iPod: 30 天
        if cat == "ipod" || cat == "ipods" || name.contains("ipod") || rawName.contains("ipod") {
            return 30
        }

        // 2. 非主力耳机 / 非主力手表: 45 天 (AirPods, Beats, Apple Watch)
        if cat == "airpods" || name.contains("airpods") || rawName.contains("airpods") ||
           cat == "beats" || name.contains("beats") || rawName.contains("beats") ||
           cat.contains("watch") || name.contains("watch") || rawName.contains("watch") {
            return 45
        }

        // 3. 非主力 iPhone: 60 天
        if cat == "iphone" || name.contains("iphone") || rawName.contains("iphone") {
            return 60
        }

        // 4. 非主力 iPad: 90 天
        if cat == "ipad" || name.contains("ipad") || rawName.contains("ipad") {
            return 90
        }

        // 5. 其他硬件（MacBook、Vision Pro、智能电池壳等）：90 天
        return defaultCycleDays
    }

    // MARK: - AirTag 纽扣电池与绝缘片专属逻辑
    /// 判断是否为 AirTag 系列硬件（包括 1 代 A2187 与 2 代 A2937）
    static func isAirTag(_ item: CollectionItem) -> Bool {
        let cat = item.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = (item.resolvedProductName.isEmpty ? item.name : item.resolvedProductName).lowercased()
        let rawName = item.name.lowercased()
        let model = (item.model ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let catalogID = item.catalogID ?? ""
        return cat == "airtag" || name.contains("airtag") || rawName.contains("airtag") ||
               model == "A2187" || model == "A2937" ||
               catalogID == "AirTag-1" || catalogID == "afw2,4"
    }

    /// 判断 AirTag 是否处于“已插绝缘片 · 零耗电免维护”的物理断电保护状态
    /// 依据用户硬件实际情况：没在用的都插着原厂塑料绝缘拉片，物理断开电池极片，零耗电无任何饿死风险
    static func isAirTagInsulated(_ item: CollectionItem) -> Bool {
        guard isAirTag(item) else { return false }
        if !item.isDailyDriver {
            return true
        }
        let notes = (item.notes ?? "").lowercased()
        let customName = (item.customName ?? "").lowercased()
        return notes.contains("绝缘片") || notes.contains("insulated") || customName.contains("绝缘片")
    }

    /// 读取 AirTag 篆刻内容描述（优先从 screenSize 读取，降级从 customName / notes 提取）
    static func airTagEngravingDescription(_ item: CollectionItem) -> String? {
        guard isAirTag(item) else { return nil }
        let isZh = isChineseLanguage
        let prefix = isZh ? "篆刻: " : "Engraved: "
        let noneText = isZh ? "无篆刻" : "No Engraving"
        let someText = isZh ? "带篆刻" : "Engraved"

        if let screen = item.screenSize?.trimmingCharacters(in: .whitespacesAndNewlines), !screen.isEmpty {
            if screen == "DC" { return "\(prefix)DC" }
            if screen == "DW" { return "\(prefix)DW" }
            if screen == "无篆刻" || screen.lowercased() == "none" { return noneText }
            if screen == "带篆刻" { return someText }
            return "\(prefix)\(screen)"
        }
        if let custom = item.customName {
            if custom.contains("DC") { return "\(prefix)DC" }
            if custom.contains("DW") { return "\(prefix)DW" }
            if custom.contains("无篆刻") { return noneText }
            if custom.contains("带篆刻") { return someText }
        }
        if let notes = item.notes {
            if notes.contains("DC") { return "\(prefix)DC" }
            if notes.contains("DW") { return "\(prefix)DW" }
            if notes.contains("无篆刻") { return noneText }
            if notes.contains("带篆刻") { return someText }
        }
        return nil
    }

    /// 判断是否为使用 CR2032 等不可充电纽扣电池的硬件设备（AirTag、Apple Remote A1156 / A1294 等）
    static func isCoinCellDevice(_ item: CollectionItem) -> Bool {
        let model = (item.model ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let name = item.name.lowercased()
        let prod = item.resolvedProductName.lowercased()
        if isAirTag(item) { return true }
        if model == "A1156" || name.contains("a1156") || prod.contains("a1156") ||
           model == "A1294" ||
           (name.contains("apple remote") && !name.contains("siri")) ||
           (prod.contains("apple remote") && !prod.contains("siri")) {
            return true
        }
        return false
    }

    /// 记录不可充纽扣电池设备（如 A1156 遥控器、AirTag 等）换入全新 CR2032 电池
    static func logCoinCellBatteryReplaced(
        for item: CollectionItem,
        date: Date = Date(),
        onUpdate: ((CollectionItem) -> Void)?
    ) {
        if isAirTag(item) {
            logAirTagBatteryReplaced(for: item, date: date, onUpdate: { updated in
                onUpdate?(updated)
            })
            return
        }
        var updated = item
        updated.lastCharged = formatChargeDate(date)
        updated.updatedAt = date
        updated.battery = "CR2032 纽扣电池"
        updated.customCycleDays = 365
        onUpdate?(updated)
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    // MARK: - 补电维护快照与统一单次求值引擎
    struct BatteryMaintenanceSnapshot: Equatable, Sendable {
        let status: BatteryMaintenanceStatus
        let elapsedDays: Int?
        let remainingDays: Int?
        let cycleDays: Int
    }

    /// 一次性统一计算设备的补电状态、流逝天数、剩余天数与周期（杜绝重复解析日期与重复日历运算）
    static func evaluateMaintenance(
        for item: CollectionItem,
        relativeTo now: Date = Date(),
        cycleDays customCycle: Int? = nil
    ) -> BatteryMaintenanceSnapshot? {
        guard deviceHasRechargeableBattery(item) else { return nil }
        if item.batteryTrackingIgnored { return nil }

        let cycle = customCycle ?? cycleDays(for: item)

        // AirTag 纽扣电池与绝缘片专属逻辑：
        if isAirTag(item) {
            if isAirTagInsulated(item) {
                return BatteryMaintenanceSnapshot(status: .healthy, elapsedDays: nil, remainingDays: nil, cycleDays: 365)
            }
            guard let elapsed = daysSinceLastCharged(item, relativeTo: now) else {
                return BatteryMaintenanceSnapshot(status: .untracked, elapsedDays: nil, remainingDays: nil, cycleDays: 365)
            }
            let remaining = 365 - elapsed
            let st: BatteryMaintenanceStatus
            if elapsed > 365 {
                st = .overdue
            } else if remaining <= 30 {
                st = .dueSoon
            } else {
                st = .healthy
            }
            return BatteryMaintenanceSnapshot(status: st, elapsedDays: elapsed, remainingDays: remaining, cycleDays: 365)
        }

        let elapsed = daysSinceLastCharged(item, relativeTo: now)
        let remaining = elapsed.map { cycle - $0 }

        if item.isDailyDriver {
            return BatteryMaintenanceSnapshot(status: .inUse, elapsedDays: elapsed, remainingDays: remaining, cycleDays: cycle)
        }

        guard let el = elapsed else {
            return BatteryMaintenanceSnapshot(status: .untracked, elapsedDays: nil, remainingDays: nil, cycleDays: cycle)
        }

        let rem = cycle - el
        let warningWindow = max(7, min(20, cycle / 4))
        let st: BatteryMaintenanceStatus
        if el > cycle {
            st = .overdue
        } else if rem <= warningWindow {
            st = .dueSoon
        } else {
            st = .healthy
        }
        return BatteryMaintenanceSnapshot(status: st, elapsedDays: el, remainingDays: rem, cycleDays: cycle)
    }

    /// 距离下次补电建议的剩余天数（可能为负数代表已逾期）
    static func daysRemainingUntilDue(_ item: CollectionItem, relativeTo now: Date = Date(), cycleDays customCycle: Int? = nil) -> Int? {
        evaluateMaintenance(for: item, relativeTo: now, cycleDays: customCycle)?.remainingDays
    }

    /// 下一次建议补电的理论日期
    static func nextDueDate(_ item: CollectionItem, cycleDays customCycle: Int? = nil) -> Date? {
        if isAirTag(item) && isAirTagInsulated(item) {
            return nil
        }
        guard let lastDate = parseChargeDate(item.lastCharged) else { return nil }
        let cycle = customCycle ?? cycleDays(for: item)
        return Calendar.current.date(byAdding: .day, value: cycle, to: lastDate)
    }

    /// 计算设备的当前补电维护状态
    static func maintenanceStatus(for item: CollectionItem, relativeTo now: Date = Date()) -> BatteryMaintenanceStatus? {
        evaluateMaintenance(for: item, relativeTo: now)?.status
    }

    // MARK: - 补电数据变更与持久化
    /// 根据当前补电时的实际间隔天数（elapsedDays）与剩余电量，智能规划自适应维护周期：
    /// 核心逻辑（实测安全耐力法则）：
    /// 1. 验证安全耐力扩展：若原定周期 45 天，超期到 50 天才补电，且实测电量仍在 80% 以上，
    ///    证明设备客观上在此环境下能安全耐受 50 天。下次周期应基于实测安全间隔（50天）+ 5天动态奖励 = 55天！
    /// 2. 提前补电保护：若下次在第 30 天就提前进行了补电且电量仍满，绝不逆向降级缩短至 30+5=35天，必须维持并锁定已验证的 55天安全基准！
    /// 3. 提前耗尽防御：若在远短于周期的天数内发现临界低电（<20%）或耗尽（0%），则以实际耗尽天数做基准大幅收窄周期，防止锂电饿死。
    static func calculateAdaptedCycle(
        for item: CollectionItem,
        at date: Date = Date(),
        remainingLevel: BatteryRemainingLevel
    ) -> (baseCycle: Int, newCycle: Int, isAdaptedFromEarlyDrain: Bool) {
        let currentCycle = cycleDays(for: item)
        let elapsedDays = daysSinceLastCharged(item, relativeTo: date) ?? 0

        var newCycle = currentCycle
        var isEarlyDrain = false

        switch remainingLevel {
        case .from80to100:
            // 剩余电量 80% - 100%（极佳状态，几乎无自放电损耗）：
            if elapsedDays >= currentCycle {
                // 超期仍满电：以实测安全耐力天数（elapsedDays）为新基准，叠加 5 天动态自适应激励
                newCycle = max(currentCycle, elapsedDays) + 5
            } else {
                // 提前主动补电：维持已验证的高安全周期，绝不退缩缩短；若状态极佳微幅递增 2 天（封顶 180 天）
                newCycle = max(currentCycle, min(currentCycle + 2, 180))
            }

        case .from50to80:
            // 剩余电量 50% - 80%（电量充裕，放电良好）：
            if elapsedDays >= currentCycle {
                newCycle = max(currentCycle, elapsedDays) + 2
            } else {
                newCycle = currentCycle
            }

        case .from20to50:
            // 剩余电量 20% - 50%（中度放电，符合预期）：
            // 维持当前稳定周期
            newCycle = currentCycle

        case .under20:
            // 剩余电量 < 20%（严重濒危，临界放电预警）：
            if elapsedDays < currentCycle && elapsedDays > 0 {
                newCycle = max(7, min(currentCycle, elapsedDays) - 5)
                isEarlyDrain = true
            } else {
                newCycle = max(7, currentCycle - 5)
            }

        case .zero:
            // 剩余电量 0%（已耗尽饿死，最高危险级）：
            if elapsedDays < currentCycle && elapsedDays > 0 {
                newCycle = max(7, min(currentCycle, elapsedDays) - 10)
                isEarlyDrain = true
            } else {
                newCycle = max(7, currentCycle - 10)
            }

        case .noCharge:
            // 用户检查设备发现剩余电量充足（≥70%），无需进行补电：
            if elapsedDays >= currentCycle {
                // 已满充电周期（含超期）：在当前耗电天数的基础上直接加 30 天
                newCycle = elapsedDays + 30
            } else {
                // 未满充电周期：计算 (当前耗电天数 + 30 天)
                if elapsedDays + 30 <= currentCycle {
                    // 没有超过充电周期：给充电周期增加 10 天
                    newCycle = currentCycle + 10
                } else {
                    // 已超过当前充电周期：在当前充电周期上直接加 30 天
                    newCycle = currentCycle + 30
                }
            }

        case .unrecorded:
            newCycle = currentCycle
        }

        // 上限封顶：CR2032 纽扣电池或电量充足免充设备封顶 365 天；常规锂电补电调节封顶 180 天
        let maxCap = (isAirTag(item) || isCoinCellDevice(item) || remainingLevel == .noCharge) ? 365 : 180
        newCycle = max(7, min(maxCap, newCycle))

        return (currentCycle, newCycle, isEarlyDrain)
    }

    /// 单台设备记录完成补电（支持动态周期根据剩余电量与实际耗尽天数自适应调节）
    static func logCharge(
        for item: CollectionItem,
        date: Date = Date(),
        remainingLevel: BatteryRemainingLevel = .unrecorded,
        batteryLevel: String? = nil,
        note: String? = nil,
        onUpdate: (CollectionItem) -> Void
    ) {
        var updated = item
        if remainingLevel == .noCharge {
            // “未充电”表示本次未进行插线充电，保持原充电日期不变；
            // 若此前未记录过充电日期，则初始化为当前日期以便开始追踪
            if updated.lastCharged == nil || updated.lastCharged?.isEmpty == true {
                updated.lastCharged = formatChargeDate(date)
            }
        } else {
            updated.lastCharged = formatChargeDate(date)
        }
        updated.updatedAt = date

        let currentCycle = cycleDays(for: item)
        let (baseCycle, newCycle, isEarlyDrain) = calculateAdaptedCycle(for: item, at: date, remainingLevel: remainingLevel)
        let adjustment = remainingLevel.cycleAdjustmentDays

        if remainingLevel == .noCharge {
            updated.customCycleDays = newCycle
            let diff = newCycle - currentCycle
            let diffStr = diff >= 0 ? "+\(diff)" : "\(diff)"
            let healthSuffix = (batteryLevel?.isEmpty == false) ? " · \(batteryLevel!)" : ""
            updated.battery = "Sufficient (≥70%) · No Charge · Cycle \(newCycle)d (\(diffStr)d)\(healthSuffix)"
        } else if isEarlyDrain || adjustment != 0 {
            updated.customCycleDays = newCycle
            let healthSuffix = (batteryLevel?.isEmpty == false) ? " · \(batteryLevel!)" : ""
            if isEarlyDrain {
                updated.battery = "Remaining \(remainingLevel.label) · Cycle \(newCycle)d (Drained in \(baseCycle)d · \(adjustment > 0 ? "+\(adjustment)" : "\(adjustment)")d)\(healthSuffix)"
            } else {
                let diff = newCycle - currentCycle
                let diffStr = diff > 0 ? "+\(diff)" : "\(diff)"
                updated.battery = "Remaining \(remainingLevel.label) · Cycle \(newCycle)d (\(diffStr)d)\(healthSuffix)"
            }
        } else {
            if remainingLevel != .unrecorded {
                let healthSuffix = (batteryLevel?.isEmpty == false) ? " · \(batteryLevel!)" : ""
                updated.battery = "Remaining \(remainingLevel.label) · Cycle \(currentCycle)d\(healthSuffix)"
            } else if let batteryLevel, !batteryLevel.isEmpty {
                updated.battery = batteryLevel
            }
        }

        if let note, !note.isEmpty {
            if let existing = updated.notes, !existing.isEmpty {
                updated.notes = existing + " | " + note
            } else {
                updated.notes = note
            }
        }
        onUpdate(updated)
    }

    /// 记录“无需补电 / 未充电”（电量充足 ≥70%，自动智能延长维护周期，不修改最后充电日期）
    static func logNoChargeNeeded(
        for item: CollectionItem,
        date: Date = Date(),
        onUpdate: (CollectionItem) -> Void
    ) {
        logCharge(for: item, date: date, remainingLevel: .noCharge, onUpdate: onUpdate)
    }

    /// 重置某台设备的自定义周期，恢复至硬件品类基准周期
    static func resetCycleToBase(for item: CollectionItem, onUpdate: (CollectionItem) -> Void) {
        var updated = item
        updated.customCycleDays = nil
        onUpdate(updated)
    }

    /// 批量为多台设备记录补电（支持指定剩余电量与周期动态调整）
    static func batchLogCharge(
        for items: [CollectionItem],
        date: Date = Date(),
        remainingLevel: BatteryRemainingLevel = .unrecorded,
        batteryLevel: String? = nil,
        onBatchUpdate: (([CollectionItem]) -> Void)?,
        onUpdate: (CollectionItem) -> Void
    ) {
        let formatted = formatChargeDate(date)

        let updatedList = items.map { item -> CollectionItem in
            var m = item
            m.lastCharged = formatted
            m.updatedAt = date

            let currentCycle = cycleDays(for: item)
            let (baseCycle, newCycle, isEarlyDrain) = calculateAdaptedCycle(for: item, at: date, remainingLevel: remainingLevel)
            let adjustment = remainingLevel.cycleAdjustmentDays

            if isEarlyDrain || adjustment != 0 {
                m.customCycleDays = newCycle
                let healthSuffix = (batteryLevel?.isEmpty == false) ? " · \(batteryLevel!)" : ""
                if isEarlyDrain {
                    m.battery = "Remaining \(remainingLevel.label) · Cycle \(newCycle)d (Drained in \(baseCycle)d · \(adjustment > 0 ? "+\(adjustment)" : "\(adjustment)")d)\(healthSuffix)"
                } else {
                    let diff = newCycle - currentCycle
                    let diffStr = diff > 0 ? "+\(diff)" : "\(diff)"
                    m.battery = "Remaining \(remainingLevel.label) · Cycle \(newCycle)d (\(diffStr)d)\(healthSuffix)"
                }
            } else {
                if remainingLevel != .unrecorded {
                    let healthSuffix = (batteryLevel?.isEmpty == false) ? " · \(batteryLevel!)" : ""
                    m.battery = "Remaining \(remainingLevel.label) · Cycle \(currentCycle)d\(healthSuffix)"
                } else if let batteryLevel, !batteryLevel.isEmpty {
                    m.battery = batteryLevel
                }
            }
            return m
        }
        if let onBatchUpdate {
            onBatchUpdate(updatedList)
        } else {
            updatedList.forEach(onUpdate)
        }
    }

    /// 切换常用在用状态
    static func toggleDailyDriver(for item: CollectionItem, onUpdate: (CollectionItem) -> Void) {
        var updated = item
        updated.isDailyDriver.toggle()
        updated.updatedAt = Date()
        onUpdate(updated)
    }

    /// 切换是否停止电池健康跟踪（适用于已损坏/不开机/尸体硬件，支持随时取消反悔）
    static func toggleBatteryTracking(for item: CollectionItem, onUpdate: (CollectionItem) -> Void) {
        var updated = item
        updated.batteryTrackingIgnored.toggle()
        updated.updatedAt = Date()
        onUpdate(updated)
    }

    /// 记录 AirTag 更换新 CR2032 纽扣电池（重置 365 天周期）
    static func logAirTagBatteryReplaced(
        for item: CollectionItem,
        date: Date = Date(),
        batteryBrandOrNote: String? = nil,
        onUpdate: (CollectionItem) -> Void
    ) {
        var updated = item
        updated.lastCharged = formatChargeDate(date)
        updated.updatedAt = date
        updated.isDailyDriver = true
        updated.battery = "CR2032 纽扣电池"
        updated.customCycleDays = 365

        var noteParts: [String] = []
        if let brand = batteryBrandOrNote, !brand.isEmpty {
            noteParts.append(brand)
        }
        let baseNote = (updated.notes ?? "")
            .replacingOccurrences(of: "已插绝缘片 · 零耗电免维护 · ", with: "")
            .replacingOccurrences(of: "已插绝缘片 · 零耗电免维护", with: "")
            .replacingOccurrences(of: "已插绝缘片", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseNote.isEmpty {
            noteParts.append(baseNote)
        }
        noteParts.append("CR2032 电池换新 (\(formatChargeDate(date)))")
        updated.notes = noteParts.joined(separator: " · ")

        onUpdate(updated)
    }

    /// 切换 AirTag 绝缘片插拔状态（拔出启用日常在用 / 插回复位免维护存放）
    static func toggleAirTagInsulationTab(
        for item: CollectionItem,
        onUpdate: (CollectionItem) -> Void
    ) {
        var updated = item
        let wasInsulated = isAirTagInsulated(item)
        if wasInsulated {
            // 拔出绝缘片 -> 启用日常在用，开始消耗 CR2032
            updated.isDailyDriver = true
            if updated.lastCharged == nil || updated.lastCharged?.isEmpty == true {
                updated.lastCharged = formatChargeDate(Date())
            }
            updated.battery = "CR2032 纽扣电池"
            updated.customCycleDays = 365
            let cleanNotes = (updated.notes ?? "")
                .replacingOccurrences(of: "已插绝缘片 · 零耗电免维护 · ", with: "")
                .replacingOccurrences(of: "已插绝缘片 · 零耗电免维护", with: "")
                .replacingOccurrences(of: "已插绝缘片", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            updated.notes = cleanNotes.isEmpty ? "日常在用 · 绝缘片已拔出 · CR2032 供电中" : "日常在用 · 绝缘片已拔出 · " + cleanNotes
        } else {
            // 插回复位绝缘片 -> 免维护存放，物理断电零自放电
            updated.isDailyDriver = false
            updated.battery = "CR2032 (已插绝缘片)"
            let cleanNotes = (updated.notes ?? "")
                .replacingOccurrences(of: "日常在用 · 绝缘片已拔出 · ", with: "")
                .replacingOccurrences(of: "日常在用 · ", with: "")
                .replacingOccurrences(of: "日常在用", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            updated.notes = cleanNotes.isEmpty ? "已插绝缘片 · 零耗电免维护" : "已插绝缘片 · 零耗电免维护 · " + cleanNotes
        }
        updated.updatedAt = Date()
        onUpdate(updated)
    }

    // MARK: - 每日 20:00 聚合本地推送通知 (Daily Consolidated Reminders at 20:00)
    /// 当有设备需要充电的那天，只在晚上 8 点弹出一次通知："今日有收藏需要充电，请点击查看"
    /// 若用户该日未充电，也不会产生连续轰炸二次提醒，但 App 内将持续标红保留直到补电。
    static func scheduleDailyBatteryReminders(for items: [CollectionItem]) {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        center.getPendingNotificationRequests { requests in
            let oldIDs = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("battery_quarterly_") || $0.hasPrefix("battery_daily_") }
            if !oldIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: oldIDs)
            }

            // 筛选出所有带电池、非主力、未停用跟踪且已有补电记录的设备
            let targetItems = items.filter {
                deviceHasRechargeableBattery($0) &&
                !$0.isDailyDriver &&
                !$0.batteryTrackingIgnored &&
                parseChargeDate($0.lastCharged) != nil
            }

            // 按下一次理论到期补电日期（按天对齐）归类
            var itemsByDueDate: [Date: [CollectionItem]] = [:]
            for item in targetItems {
                guard let dueDate = nextDueDate(item) else { continue }
                let dueDay = calendar.startOfDay(for: dueDate)
                itemsByDueDate[dueDay, default: []].append(item)
            }

            // 判断今天是否已过 20:00
            let cutoffToday20 = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: startOfToday) ?? startOfToday

            // 仅对未来（或今天尚未到 20:00）的到期日，每日安排仅 1 条晚上 20:00 的汇总通知
            // 规则：若已在今天之前逾期且当时没充电，不再每日二次提醒轰炸通知栏（App 内保留挂起）
            let eligibleDates = itemsByDueDate.keys
                .filter { dueDay in
                    if dueDay > startOfToday {
                        return true
                    } else if dueDay == startOfToday {
                        return now < cutoffToday20
                    } else {
                        // 到期日在今天之前（已逾期）：不再进行二次提醒
                        return false
                    }
                }
                .sorted()

            let isChinese = isChineseLanguage
            let title = isChinese ? "⚡️ 藏品补电提醒" : "⚡️ Battery Maintenance Reminder"
            let body = isChinese ? "今日有收藏需要充电，请点击查看" : "You have collection devices that need charging today. Tap to review."

            let maxScheduledDates = 50
            for dueDay in eligibleDates.prefix(maxScheduledDates) {
                let dateKey = formatDateKey(dueDay)
                let identifier = "battery_daily_\(dateKey)"

                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.categoryIdentifier = notificationCategory

                var triggerComponents = calendar.dateComponents([.year, .month, .day], from: dueDay)
                triggerComponents.hour = 20
                triggerComponents.minute = 0
                triggerComponents.second = 0

                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                center.add(request)
            }
        }
    }

    /// 兼容旧命名的调用入口
    static func scheduleQuarterlyReminders(for items: [CollectionItem]) {
        scheduleDailyBatteryReminders(for: items)
    }

    private static func formatDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}
