import Foundation

/// Compact copy of one collection item, shared by the iPhone app, the watch app and the watch complications.
nonisolated struct WatchItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var category: String
    var year: String?
    var color: String?
    var serial: String?
    var model: String?
    var processor: String?
    var storage: String?
    var thumbnail: Data?
}

nonisolated struct PommeSnapshot: Codable, Sendable {
    var items: [WatchItem]
    var wishlistCount: Int
    var generatedAt: Date

    static let empty = PommeSnapshot(items: [], wishlistCount: 0, generatedAt: .distantPast)

    var categoryCount: Int { Set(items.map(\.category)).count }

    /// 判断是否为配件类物品（排除在 Today's Exhibit 展出之外）
    static func isAccessory(item: WatchItem) -> Bool {
        let cat = item.category.lowercased()
        let name = item.name.lowercased()

        // 1. 分类匹配
        let accessoryCategories = [
            "accessories", "配件", "audio accessories", "音频配件",
            "other accessories", "其他配件", "power & charging", "电源与充电",
            "cases & storage", "保护与收纳", "connectivity & expansion", "连接与扩展",
            "beats accessories", "beats 配件", "remote", "遥控器", "adapters", "adapter"
        ]
        if accessoryCategories.contains(where: { cat.contains($0) || $0.contains(cat) }) {
            return true
        }

        // 2. 硬件配件关键词特征识别（转接头、线缆、保护套、表带、充电器、抛光布等）
        let accessoryKeywords = [
            "adapter", "cable", "case with magsafe", "silicone case", "leather case",
            "smart folio", "smart cover", "sport band", "sport loop", "milanese loop",
            "link bracelet", "ocean band", "trail loop", "alpine loop", "fine woven",
            "polishing cloth", "power adapter", "magsafe charger", "magsafe duo",
            "battery pack", "ear tips", "camera adapter", "lightning to", "usb-c to",
            "转接", "转换器", "线缆", "连接线", "充电线", "充电器", "电源适配器", "表带",
            "保护壳", "保护套", "双面夹", "抛光布", "清洁布", "耳塞", "配件", "挂绳"
        ]

        for kw in accessoryKeywords {
            if name.contains(kw) {
                return true
            }
        }

        return false
    }

    /// 满足 Today's Exhibit 展出条件的候选品集合：
    /// 遵循用户要求的「非配件 & 已有 & 必须有图片」原则
    var exhibitCandidates: [WatchItem] {
        items.filter { item in
            // 排除配件
            if Self.isAccessory(item: item) { return false }
            // 必须具备有效图片
            guard let thumb = item.thumbnail, !thumb.isEmpty else { return false }
            return true
        }
    }

    /// 确定性每日展品（“Today's Exhibit”）：按日轮播，且严格遵循非配件、已有、有图片原则
    func exhibit(for date: Date = Date()) -> WatchItem? {
        let candidates = exhibitCandidates
        guard !candidates.isEmpty else {
            // 容错兜底：若暂未生成缩略图，优先从带图的非配件中选；若全部无图才选第一个非配件
            let nonAccessoriesWithThumb = items.filter { !Self.isAccessory(item: $0) && $0.thumbnail != nil && !($0.thumbnail?.isEmpty ?? true) }
            if !nonAccessoriesWithThumb.isEmpty { return selectDeterministic(from: nonAccessoriesWithThumb, for: date) }
            let nonAccessories = items.filter { !Self.isAccessory(item: $0) }
            if !nonAccessories.isEmpty { return selectDeterministic(from: nonAccessories, for: date) }
            return items.first
        }
        return selectDeterministic(from: candidates, for: date)
    }

    private func selectDeterministic(from list: [WatchItem], for date: Date) -> WatchItem? {
        guard !list.isEmpty else { return nil }
        let sorted = list.sorted { $0.id < $1.id }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var hash: UInt64 = 0xcbf29ce484222325 // FNV-1a, 跨进程稳定哈希
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return sorted[Int(hash % UInt64(sorted.count))]
    }
}

nonisolated enum PommeStore {
    static let appGroupID = "group.com.caodavidpersonalteam.Pomme"

    /// App Group container when the entitlement is provisioned; otherwise the app's own Documents folder.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var snapshotURL: URL { containerURL.appendingPathComponent("watch-snapshot.json") }

    static func loadSnapshot() -> PommeSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(PommeSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: PommeSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }
}

/// Fuzzy name (+ optional year) matching used by Siri: "AirPods Pro", "2017 MacBook Pro", "macbookpro 2017".
nonisolated enum PommeMatcher {
    static func normalize(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func matches(_ query: String, in items: [WatchItem]) -> [WatchItem] {
        var words = tokens(query)
        let year = words.first { $0.count == 4 && Int($0).map { (1976...2100).contains($0) } == true }
        words.removeAll { $0 == year }
        let stop: Set<String> = ["my", "the", "a", "of", "do", "i", "have", "how", "many", "serial", "number", "我的", "的", "有", "几", "个", "台"]
        words.removeAll { stop.contains($0) }
        let squashedQuery = words.joined()
        let scored: [(WatchItem, Double)] = items.compactMap { item in
            if let year, item.year?.contains(year) != true { return nil }
            guard !words.isEmpty else { return (item, 1) }
            let nameTokens = tokens(item.name)
            let squashedName = nameTokens.joined()
            if squashedName.contains(squashedQuery) { return (item, 1) }
            let hits = words.filter { word in nameTokens.contains { $0.hasPrefix(word) || word.hasPrefix($0) && $0.count >= 3 } }
            let score = Double(hits.count) / Double(words.count)
            return score >= 0.75 ? (item, score) : nil
        }
        guard let best = scored.map(\.1).max() else { return [] }
        return scored.filter { $0.1 == best }.map(\.0)
    }
}
