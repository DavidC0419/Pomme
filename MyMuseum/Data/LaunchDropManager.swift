//
//  LaunchDropManager.swift
//  Pomme
//
//  新品发售与热门抢购日程通知管理器 (Apple Product Launch & Drop Manager)
//  支持热门首发单品自动追踪、开售前 1 天、30 分钟预警，以及感兴趣单品开售前 5 分钟极速提醒。
//

import Foundation
import SwiftUI
import UserNotifications
import Combine

// MARK: - 发售阶段状态
enum LaunchDropStatus: String, Codable, Sendable {
    case upcoming    // Upcoming drop
    case starting    // Releasing soon (< 30 min)
    case imminent    // 5m Rush (< 5 min)
    case live        // Live now
    case ended       // Ended

    var title: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .starting: return "Starting Soon"
        case .imminent: return "5m Rush"
        case .live: return "Live Now"
        case .ended: return "Ended"
        }
    }
}

// MARK: - 抢购渠道配置
struct LaunchChannel: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let subtitle: String?
    let iconSystemName: String
    let urlString: String

    var url: URL? {
        URL(string: urlString)
    }

    static let officialStore = LaunchChannel(
        name: "Apple Store Online",
        subtitle: "Official web store & order tracking",
        iconSystemName: "apple.logo",
        urlString: "https://www.apple.com/shop"
    )

    static let appleStoreApp = LaunchChannel(
        name: "Apple Store App",
        subtitle: "Fastest checkout with Apple Pay",
        iconSystemName: "iphone",
        urlString: "https://apps.apple.com/app/apple-store/id375380948"
    )

    static let authorizedRetail = LaunchChannel(
        name: "Apple Authorized Retail",
        subtitle: "Premier partners & flagship stores",
        iconSystemName: "cart.fill",
        urlString: "https://www.apple.com/retail"
    )
}

// MARK: - 时区与发售时间工具 (Time Zone & Release Date Utilities)
enum LaunchTimeZoneHelper {
    static let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
    static let usPacificTimeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -7 * 3600)!
    static let usEasternTimeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -4 * 3600)!

    /// 创建固定北京时间（年、月、日、时、分）的绝对日期
    static func dateInBeijing(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = beijingTimeZone
        var comp = DateComponents()
        comp.calendar = cal
        comp.timeZone = beijingTimeZone
        comp.year = year
        comp.month = month
        comp.day = day
        comp.hour = hour
        comp.minute = minute
        comp.second = second
        return cal.date(from: comp) ?? Date()
    }

    /// 从美西时间 (PDT / PST) 换算为全球绝对日期（对应北京时间 +15 小时夏令时或 +16 小时冬令时）
    static func dateFromUSPacific(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = usPacificTimeZone
        var comp = DateComponents()
        comp.calendar = cal
        comp.timeZone = usPacificTimeZone
        comp.year = year
        comp.month = month
        comp.day = day
        comp.hour = hour
        comp.minute = minute
        comp.second = second
        return cal.date(from: comp) ?? Date()
    }

    /// 格式化带有北京时间与用户当地时区的双重发售时间描述（杜绝跨洋时差误读）
    static func formatDualTimeZone(date: Date) -> String {
        let isChinese = isChineseLanguage
        let bjtFormatter = DateFormatter()
        bjtFormatter.timeZone = beijingTimeZone
        bjtFormatter.locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        bjtFormatter.dateFormat = isChinese ? "M月d日 HH:mm" : "MMM d, h:mm a"
        let bjtStr = bjtFormatter.string(from: date)

        let bjtLabel = isChinese ? "北京时间" : "Beijing Time"
        let localLabel = isChinese ? "当地" : "Local"

        let localZone = TimeZone.current
        let isLocalBJT = localZone.secondsFromGMT(for: date) == beijingTimeZone.secondsFromGMT(for: date)
        if isLocalBJT {
            return "\(bjtStr) (\(bjtLabel))"
        } else {
            let localFormatter = DateFormatter()
            localFormatter.timeZone = localZone
            localFormatter.locale = isChinese ? Locale(identifier: "zh_CN") : Locale.current
            localFormatter.dateFormat = isChinese ? "M月d日 HH:mm" : "MMM d, h:mm a zzz"
            let localStr = localFormatter.string(from: date)
            return "\(bjtStr) (\(bjtLabel)) · \(localLabel) \(localStr)"
        }
    }
}

// MARK: - 热门发售单品模型
struct LaunchDropItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let headline: String
    let category: String
    let releaseDate: Date
    let startingPrice: String
    let highlightSpecs: [String]
    let imageAssetName: String
    let catalogProductID: String?
    let channels: [LaunchChannel]

    var isLive: Bool {
        Date() >= releaseDate
    }

    var isImminent: Bool {
        let diff = releaseDate.timeIntervalSince(Date())
        return diff > 0 && diff <= 300
    }

    var isStartingSoon: Bool {
        let diff = releaseDate.timeIntervalSince(Date())
        return diff > 0 && diff <= 1800
    }

    var status: LaunchDropStatus {
        let now = Date()
        if now >= releaseDate.addingTimeInterval(3600 * 24 * 7) {
            return .ended
        } else if now >= releaseDate {
            return .live
        } else if isImminent {
            return .imminent
        } else if isStartingSoon {
            return .starting
        } else {
            return .upcoming
        }
    }

    /// 距离开售倒计时格式化
    func countdownComponents(from now: Date = Date()) -> (days: Int, hours: Int, minutes: Int, seconds: Int, isPast: Bool) {
        let diff = releaseDate.timeIntervalSince(now)
        if diff <= 0 {
            return (0, 0, 0, 0, true)
        }
        let totalSec = Int(diff)
        let days = totalSec / 86400
        let hours = (totalSec % 86400) / 3600
        let minutes = (totalSec % 3600) / 60
        let seconds = totalSec % 60
        return (days, hours, minutes, seconds, false)
    }

    /// 国际化宣传标语
    var localizedHeadline: String {
        appLocalized(headline)
    }

    /// 时区友好的发售时间展示
    var releaseDateFormatted: String {
        LaunchTimeZoneHelper.formatDualTimeZone(date: releaseDate)
    }
}

// MARK: - 发售日程与通知总管
@MainActor
final class LaunchDropManager: ObservableObject {
    static let shared = LaunchDropManager()

    @Published private(set) var drops: [LaunchDropItem] = []
    @Published private(set) var interestedDropIDs: Set<String> = []
    @Published private(set) var dismissedDropIDs: Set<String> = []
    @Published private(set) var userUnstarredDropIDs: Set<String> = []
    @Published private(set) var userRestoredDropIDs: Set<String> = []
    @Published private(set) var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastSyncDate: Date? = nil

    private let interestedStorageKey = "Pomme_Interested_Launch_Drop_IDs_v1"
    private let unstarredStorageKey = "Pomme_Unstarred_Launch_Drop_IDs_v1"
    private let dismissedStorageKey = "Pomme_Dismissed_Launch_Drop_IDs_v1"
    private let restoredStorageKey = "Pomme_Restored_Launch_Drop_IDs_v1"
    private let customDropsStorageKey = "Pomme_Custom_Launch_Drops_v1"
    private let remoteDropsStorageKey = "Pomme_Remote_Launch_Drops_v1"

    /// 动态远程发售单品热更地址（支持自定义 CDN 或官方静态源）
    var remoteDropsEndpoint: URL? {
        if let custom = UserDefaults.standard.string(forKey: "Pomme_Custom_Drops_Endpoint_URL"),
           let url = URL(string: custom) {
            return url
        }
        return URL(string: "https://raw.githubusercontent.com/caodavid/MyMuseum/main/MyMuseum/Data/launch_drops_feed.json")
    }

    init() {
        loadPreferences()
        loadDrops()
        checkNotificationStatus()
    }

    // MARK: - 数据装载与内置热门发售单品
    func loadDrops() {
        // 核心基准时间：完全固定绝对时间戳，严格采用北京时间 (Asia/Shanghai, UTC+8)，杜绝相对 Date() 漂移！
        let iphoneDuoReleaseDate = LaunchTimeZoneHelper.dateInBeijing(year: 2026, month: 10, day: 16, hour: 20, minute: 0)
        let homeViewReleaseDate = LaunchTimeZoneHelper.dateInBeijing(year: 2026, month: 11, day: 13, hour: 9, minute: 0)

        let initialDrops: [LaunchDropItem] = [
            LaunchDropItem(
                id: "drop_iphone_duo_2026",
                name: "iPhone Duo",
                headline: "Dual-Screen Foldable Flagship · Powered by A20 Pro Silicon",
                category: "iPhone",
                releaseDate: iphoneDuoReleaseDate,
                startingPrice: "$1,999 / RMB 15,999",
                highlightSpecs: ["7.6\" Inner & 5.4\" Outer OLED", "A20 Pro Silicon", "Night Sky & Star White", "Dual-Cell Battery System", "Titanium-Infused Hinge"],
                imageAssetName: "catalog_iPhone19_4_0d40727b",
                catalogProductID: "iPhone19,4",
                channels: [.officialStore, .appleStoreApp, .authorizedRetail]
            ),
            LaunchDropItem(
                id: "drop_homeview_tabletop_2026",
                name: "Apple HomeView (Tabletop)",
                headline: "Apple's First Dedicated homeOS Smart Display Hub · Tabletop Stand",
                category: "Home",
                releaseDate: homeViewReleaseDate,
                startingPrice: "$299 / RMB 2,499",
                highlightSpecs: ["7-inch Liquid Retina Display", "Apple A18 Silicon", "Center Stage Camera", "Spatial Audio Speaker Base", "Thread & Matter Smart Hub"],
                imageAssetName: "",
                catalogProductID: "apple-homeview-tabletop",
                channels: [.officialStore, .appleStoreApp, .authorizedRetail]
            ),
            LaunchDropItem(
                id: "drop_homeview_wall_2026",
                name: "Apple HomeView (Wall-Mounted)",
                headline: "Flush Wall-Mounted Smart Home Control Panel · homeOS Native",
                category: "Home",
                releaseDate: homeViewReleaseDate,
                startingPrice: "$299 / RMB 2,499",
                highlightSpecs: ["Wall-Flush Clean Form Factor", "Apple A18 Silicon", "Ultra-Wide Angle Monitoring", "homeOS Native Interface", "Optional Schneider Mounts"],
                imageAssetName: "",
                catalogProductID: "apple-homeview-wall",
                channels: [.officialStore, .appleStoreApp, .authorizedRetail]
            )
        ]

        // 建立字典映射：基础单品 -> 远程热更新单品覆盖 -> 用户自定义单品合并
        var dropMap: [String: LaunchDropItem] = [:]
        for drop in initialDrops {
            dropMap[drop.id] = drop
        }

        // 1. 合并远程缓存热更新单品（可更新官方发售日期、标语与渠道）
        if let remoteData = UserDefaults.standard.data(forKey: remoteDropsStorageKey) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let remoteDrops = try? decoder.decode([LaunchDropItem].self, from: remoteData) {
                for r in remoteDrops {
                    dropMap[r.id] = r
                }
            }
        }

        // 2. 合并用户本地自定义的新品
        if let customData = UserDefaults.standard.data(forKey: customDropsStorageKey),
           let customDrops = try? JSONDecoder().decode([LaunchDropItem].self, from: customData) {
            for c in customDrops {
                dropMap[c.id] = c
            }
        }

        self.drops = Array(dropMap.values).sorted(by: { $0.releaseDate < $1.releaseDate })
        self.lastSyncDate = Date()

        // 立即刷新并清除所有已过期的提醒，防止历史单品误触发重复通知
        rescheduleAllActiveDrops()
    }

    // MARK: - 忽略与取消提醒管理 (Dismiss & Hide Drops)
    func isDismissed(_ item: LaunchDropItem) -> Bool {
        dismissedDropIDs.contains(item.id)
    }

    func dismissDrop(_ item: LaunchDropItem) {
        dismissedDropIDs.insert(item.id)
        userRestoredDropIDs.remove(item.id)
        // 取消该单品的关注与通知
        interestedDropIDs.remove(item.id)
        userUnstarredDropIDs.insert(item.id)
        cancelScheduledNotifications(for: item)
        savePreferences()

        #if canImport(UIKit) && !os(visionOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    func restoreDrop(_ item: LaunchDropItem) {
        dismissedDropIDs.remove(item.id)
        userRestoredDropIDs.insert(item.id)
        savePreferences()

        #if canImport(UIKit) && !os(visionOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    // MARK: - 感兴趣状态切换 (Starred / Unstarred)
    func isInterested(in item: LaunchDropItem) -> Bool {
        interestedDropIDs.contains(item.id) && !isDismissed(item)
    }

    func toggleInterested(in item: LaunchDropItem) {
        let wasInterested = isInterested(in: item)
        if wasInterested {
            interestedDropIDs.remove(item.id)
            userUnstarredDropIDs.insert(item.id)
            cancelScheduledNotifications(for: item)
        } else {
            interestedDropIDs.insert(item.id)
            userUnstarredDropIDs.remove(item.id)
            dismissedDropIDs.remove(item.id)
            userRestoredDropIDs.insert(item.id)
            scheduleAllNotifications(for: item, isUserInterested: true)
        }
        savePreferences()

        #if canImport(UIKit) && !os(visionOS)
        UIImpactFeedbackGenerator(style: wasInterested ? .light : .medium).impactOccurred()
        #endif
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    private func savePreferences() {
        UserDefaults.standard.set(Array(interestedDropIDs), forKey: interestedStorageKey)
        UserDefaults.standard.set(Array(userUnstarredDropIDs), forKey: unstarredStorageKey)
        UserDefaults.standard.set(Array(dismissedDropIDs), forKey: dismissedStorageKey)
        UserDefaults.standard.set(Array(userRestoredDropIDs), forKey: restoredStorageKey)
    }

    func loadPreferences() {
        if let array = UserDefaults.standard.stringArray(forKey: interestedStorageKey) {
            self.interestedDropIDs = Set(array)
        } else {
            self.interestedDropIDs = []
        }

        if let unstarred = UserDefaults.standard.stringArray(forKey: unstarredStorageKey) {
            self.userUnstarredDropIDs = Set(unstarred)
        } else {
            self.userUnstarredDropIDs = []
        }

        if let dismissed = UserDefaults.standard.stringArray(forKey: dismissedStorageKey) {
            self.dismissedDropIDs = Set(dismissed)
        } else {
            self.dismissedDropIDs = []
        }

        if let restored = UserDefaults.standard.stringArray(forKey: restoredStorageKey) {
            self.userRestoredDropIDs = Set(restored)
        } else {
            self.userRestoredDropIDs = []
        }
    }

    func updateInterestedIDsFromCloud(_ cloudIDs: [String], dismissedCloudIDs: [String]? = nil) {
        if let dCloud = dismissedCloudIDs {
            var cloudDismissed = Set(dCloud)
            // 核心防复活逻辑：绝不将用户在本机已明确解除隐藏（Unhide）的单品加回隐藏列表！
            cloudDismissed.subtract(self.userRestoredDropIDs)
            self.dismissedDropIDs = self.dismissedDropIDs.union(cloudDismissed).subtracting(self.userRestoredDropIDs)
        }

        var filteredCloud = Set(cloudIDs)
        // 核心防复活逻辑：绝不将用户已明确点灭小星星的单品加回！
        filteredCloud.subtract(self.userUnstarredDropIDs)
        // 绝不将用户已隐藏/忽略的单品加回感兴趣
        filteredCloud.subtract(self.dismissedDropIDs)

        self.interestedDropIDs = filteredCloud
        savePreferences()
    }

    // MARK: - 通知权限管理
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.notificationPermissionStatus = settings.authorizationStatus
            }
        }
    }

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.notificationPermissionStatus = granted ? .authorized : .denied
            }
            if granted {
                // 重新刷新排期已有发售提醒
                rescheduleAllActiveDrops()
            }
            return granted
        } catch {
            print("❌ Notification authorization failed: \(error)")
            return false
        }
    }

    // MARK: - 发售提醒调度引擎 (开售前 1 天、30 分钟、以及感兴趣时的开售前 5 分钟)
    func scheduleAllNotifications(for item: LaunchDropItem, isUserInterested: Bool) {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let releaseDate = item.releaseDate

        // 1. 开售前 1 天预警 (T - 24 小时)
        let oneDayBefore = releaseDate.addingTimeInterval(-86400)
        if oneDayBefore > now {
            let content = UNMutableNotificationContent()
            content.title = "Drop Alert Tomorrow · \(item.name)"
            content.subtitle = "\(item.name) launches tomorrow"
            content.body = "\(item.headline). Starting at \(item.startingPrice). Get ready!"
            content.sound = .default
            content.categoryIdentifier = "POMME_LAUNCH_DROP"

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: oneDayBefore.timeIntervalSince(now), repeats: false)
            let request = UNNotificationRequest(identifier: "\(item.id)_24h", content: content, trigger: trigger)
            center.add(request)
        }

        // 2. 开售前 30 分钟准备 (T - 30 分钟)
        let thirtyMinBefore = releaseDate.addingTimeInterval(-1800)
        if thirtyMinBefore > now {
            let content = UNMutableNotificationContent()
            content.title = "Get Ready · \(item.name) drops in 30 minutes"
            content.subtitle = "30-minute countdown · Channels opening soon"
            content.body = "Ensure your Apple ID is signed in and payment method is ready."
            content.sound = .defaultCritical
            content.categoryIdentifier = "POMME_LAUNCH_DROP"

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: thirtyMinBefore.timeIntervalSince(now), repeats: false)
            let request = UNNotificationRequest(identifier: "\(item.id)_30m", content: content, trigger: trigger)
            center.add(request)
        }

        // 3. 用户标记「感兴趣」的核心特权：开售前 5 分钟极速提醒 (T - 5 分钟)
        if isUserInterested {
            let fiveMinBefore = releaseDate.addingTimeInterval(-300)
            if fiveMinBefore > now {
                let content = UNMutableNotificationContent()
                content.title = "⚡️ 5-Minute Rush · \(item.name) drops very soon!"
                content.subtitle = "Starred Drop · Final 5-minute sprint"
                content.body = "Only 5 minutes left! Keep your screen on and refresh the checkout page."
                content.sound = .default
                content.categoryIdentifier = "POMME_LAUNCH_DROP"

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fiveMinBefore.timeIntervalSince(now), repeats: false)
                let request = UNNotificationRequest(identifier: "\(item.id)_5m_interested", content: content, trigger: trigger)
                center.add(request)
            }

            // 4. 正式开售准时提醒 (T = 0)
            if releaseDate > now {
                let content = UNMutableNotificationContent()
                content.title = "🎉 \(item.name) is Now Live!"
                content.subtitle = "Pre-orders are officially open · Order now"
                content.body = "Channels are open! Tap to jump directly into the Apple Store."
                content.sound = .default
                content.categoryIdentifier = "POMME_LAUNCH_DROP"

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: releaseDate.timeIntervalSince(now), repeats: false)
                let request = UNNotificationRequest(identifier: "\(item.id)_live", content: content, trigger: trigger)
                center.add(request)
            }
        }
    }

    func cancelScheduledNotifications(for item: LaunchDropItem) {
        let center = UNUserNotificationCenter.current()
        let ids = [
            "\(item.id)_24h",
            "\(item.id)_30m",
            "\(item.id)_5m_interested",
            "\(item.id)_live"
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func rescheduleAllActiveDrops() {
        for drop in drops {
            cancelScheduledNotifications(for: drop)
            // 仅对尚未开售的未来单品排期发售提醒；已开售的历史单品杜绝二次提醒
            if !drop.isLive {
                let interested = isInterested(in: drop)
                scheduleAllNotifications(for: drop, isUserInterested: interested)
            }
        }
    }

    // MARK: - 网络抓取与更新（与远程发售 JSON 源及 Apple 官网动态联动）
    func syncDropsFromNetwork(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // 1. 尝试从远程发售 JSON 源拉取动态热更单品
        if let endpoint = remoteDropsEndpoint {
            do {
                var req = URLRequest(url: endpoint)
                req.timeoutInterval = 10
                req.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    if let remoteDrops = try? decoder.decode([LaunchDropItem].self, from: data), !remoteDrops.isEmpty {
                        UserDefaults.standard.set(data, forKey: remoteDropsStorageKey)
                        loadDrops()
                    }
                }
            } catch {
                print("⚠️ Remote launch drops sync fallback to local cache: \(error.localizedDescription)")
            }
        }

        // 2. 尝试抓取 Apple 官方 Newsroom RSS 辅助更新时间戳
        if let newsroomURL = URL(string: "https://www.apple.com/newsroom/rss-feed.rss") {
            do {
                var req = URLRequest(url: newsroomURL)
                req.timeoutInterval = 8
                let (data, _) = try await URLSession.shared.data(for: req)
                if let stories = try? RumorRSSParser.parse(data, source: "Apple Newsroom") {
                    parseDropsFromStories(stories)
                }
            } catch {
                // 忽略非关键官方源波动
            }
        }

        self.lastSyncDate = Date()
        rescheduleAllActiveDrops()
    }

    private func parseDropsFromStories(_ stories: [RumorStory]) {
        self.lastSyncDate = Date()
    }

    // MARK: - 自定义发售单品（支持备选方案与离线自定义）
    func addCustomDrop(
        name: String,
        headline: String,
        category: String,
        releaseDate: Date,
        price: String,
        specs: [String],
        channels: [LaunchChannel]
    ) {
        let newDrop = LaunchDropItem(
            id: "custom_drop_\(UUID().uuidString)",
            name: name,
            headline: headline,
            category: category,
            releaseDate: releaseDate,
            startingPrice: price,
            highlightSpecs: specs,
            imageAssetName: "catalog_iPhone19_4_0d40727b",
            catalogProductID: nil,
            channels: channels.isEmpty ? [.officialStore, .appleStoreApp] : channels
        )

        var currentCustom: [LaunchDropItem] = []
        if let data = UserDefaults.standard.data(forKey: customDropsStorageKey),
           let decoded = try? JSONDecoder().decode([LaunchDropItem].self, from: data) {
            currentCustom = decoded
        }
        currentCustom.append(newDrop)
        if let encoded = try? JSONEncoder().encode(currentCustom) {
            UserDefaults.standard.set(encoded, forKey: customDropsStorageKey)
        }

        self.drops.append(newDrop)
        self.drops.sort(by: { $0.releaseDate < $1.releaseDate })

        // 自动标为感兴趣并安排提醒
        toggleInterested(in: newDrop)
    }
}
