//
//  MacCategoryHierarchyHelper.swift
//  Pomme
//
//  Mac 策展人工作台层级分类与小分类聚合引擎 (Hierarchical Category Navigation & Grouping)
//

import SwiftUI

/// 策展人层级标签模型
struct MacCategoryTagItem: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let title: String
    let count: Int
    let symbol: String
    let coverAssetName: String?
    let hasChildren: Bool
    let isShowAll: Bool
}

/// 策展人分层展示数据组
struct MacCollectionSectionGroup: Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let localizedTitle: String
    let symbol: String
    let coverAssetName: String?
    let items: [CollectionItem]
}

enum MacCategoryHierarchyHelper {
    
    // MARK: - 1. 获取物品的层级分类标签
    static func tiers(for item: CollectionItem) -> [CategoryHierarchyTier] {
        categoryHierarchyTiers(name: item.resolvedProductName, category: item.category)
    }
    
    // MARK: - 2. 判断某个物品是否属于指定的层级路径
    static func matches(
        item: CollectionItem,
        rootCategory: String?,
        branch: String?,
        family: String?
    ) -> Bool {
        guard let rootCategory else { return true }
        
        let itemTiers = tiers(for: item)
        guard let rootTier = itemTiers.first(where: { $0.level == 1 }) else { return false }
        if normalizeCategoryCoverKey(rootTier.key) != normalizeCategoryCoverKey(rootCategory) {
            return false
        }
        
        if let branch {
            guard let tier2 = itemTiers.first(where: { $0.level == 2 }) else { return false }
            if normalizeCategoryCoverKey(tier2.key) != normalizeCategoryCoverKey(branch) {
                return false
            }
        }
        
        if let family {
            // family 可以是 tier 3（如 MacBook Pro）也可以是 tier 2（如无 branch 时的 iPhone Pro）
            let matchT3 = itemTiers.first(where: { $0.level == 3 && normalizeCategoryCoverKey($0.key) == normalizeCategoryCoverKey(family) }) != nil
            let matchT2 = itemTiers.first(where: { $0.level == 2 && normalizeCategoryCoverKey($0.key) == normalizeCategoryCoverKey(family) }) != nil
            if !matchT3 && !matchT2 {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - 3. 生成当前层级下的所有可点击标签
    static func generateTags(
        items: [CollectionItem],
        rootCategory: String?,
        branch: String?,
        family: String?,
        isShowAll: Bool
    ) -> [MacCategoryTagItem] {
        var tags: [MacCategoryTagItem] = []
        let store = CategoryCoverStore.shared
        
        // ----------------------------------------------------
        // Level 0: 顶层根目录 (Root Level)
        // ----------------------------------------------------
        if rootCategory == nil {
            // Show All 标签
            let allCover = store.coverAssetName(for: "Mac")
            tags.append(
                MacCategoryTagItem(
                    key: "__ALL__",
                    title: isChineseLanguage ? "全部" : "All",
                    count: items.count,
                    symbol: "square.grid.2x2",
                    coverAssetName: allCover,
                    hasChildren: false,
                    isShowAll: true
                )
            )
            
            // 统计各大类设备数
            var rootCounts: [String: Int] = [:]
            for item in items {
                let r = itemRootCategory(item)
                rootCounts[r, default: 0] += 1
            }
            
            // 按照官方标准顺序排列大类
            let standardRoots = [
                "Mac", "iPhone", "iPad", "Watch", "AirPods", "iPod",
                "Input Devices", "Beats", "Accessories", "Displays", "Home", "AirPort", "Vision Pro"
            ]
            let sortedRoots = rootCounts.keys.sorted { r1, r2 in
                let idx1 = standardRoots.firstIndex(of: r1) ?? 99
                let idx2 = standardRoots.firstIndex(of: r2) ?? 99
                if idx1 != idx2 { return idx1 < idx2 }
                return categoryTitle(r1).localizedStandardCompare(categoryTitle(r2)) == .orderedAscending
            }
            
            for r in sortedRoots {
                let c = rootCounts[r] ?? 0
                guard c > 0 else { continue }
                let norm = normalizeCategoryCoverKey(r)
                let cover = store.coverAssetName(for: norm)
                tags.append(
                    MacCategoryTagItem(
                        key: r,
                        title: categoryTitle(r),
                        count: c,
                        symbol: categorySymbol(r),
                        coverAssetName: cover,
                        hasChildren: true,
                        isShowAll: false
                    )
                )
            }
            return tags
        }
        
        // ----------------------------------------------------
        // Level 1: 位于某大类下 (e.g. Mac, iPhone, Accessories)
        // ----------------------------------------------------
        guard let currentRoot = rootCategory else { return tags }
        let rootItems = items.filter { itemRootCategory($0) == currentRoot }
        
        // 如果目前未选 branch，展示该大类下的全部 + 二级分类标签
        if branch == nil {
            let rootNorm = normalizeCategoryCoverKey(currentRoot)
            tags.append(
                MacCategoryTagItem(
                    key: "__SHOW_ALL_ROOT__",
                    title: isChineseLanguage ? "全部 \(categoryTitle(currentRoot))" : "Show All \(categoryTitle(currentRoot))",
                    count: rootItems.count,
                    symbol: categorySymbol(currentRoot),
                    coverAssetName: store.coverAssetName(for: rootNorm),
                    hasChildren: false,
                    isShowAll: true
                )
            )
            
            // 统计 Tier 2 子类
            var tier2Counts: [String: Int] = [:]
            var tier2HasChildren: [String: Bool] = [:]
            
            for item in rootItems {
                let itemTiers = tiers(for: item)
                if let t2 = itemTiers.first(where: { $0.level == 2 }) {
                    tier2Counts[t2.key, default: 0] += 1
                    if itemTiers.contains(where: { $0.level >= 3 }) {
                        tier2HasChildren[t2.key] = true
                    }
                }
            }
            
            let sortedTier2 = tier2Counts.keys.sorted { k1, k2 in
                let o1 = catalogFamilyOrder(k1, root: currentRoot)
                let o2 = catalogFamilyOrder(k2, root: currentRoot)
                if o1 != o2 { return o1 < o2 }
                return appLocalized(k1).localizedStandardCompare(appLocalized(k2)) == .orderedAscending
            }
            
            for k in sortedTier2 {
                let c = tier2Counts[k] ?? 0
                guard c > 0 else { continue }
                let cover = store.coverAssetName(for: k)
                tags.append(
                    MacCategoryTagItem(
                        key: k,
                        title: appLocalized(k),
                        count: c,
                        symbol: categorySymbol(k),
                        coverAssetName: cover,
                        hasChildren: tier2HasChildren[k] == true,
                        isShowAll: false
                    )
                )
            }
            return tags
        }
        
        // ----------------------------------------------------
        // Level 2: 位于某分支下 (e.g. Mac -> MacBook, Accessories -> Power & Charging)
        // ----------------------------------------------------
        guard let currentBranch = branch else { return tags }
        let branchItems = rootItems.filter { item in
            let itemTiers = tiers(for: item)
            return itemTiers.contains(where: { $0.level == 2 && normalizeCategoryCoverKey($0.key) == normalizeCategoryCoverKey(currentBranch) })
        }
        
        tags.append(
            MacCategoryTagItem(
                key: "__SHOW_ALL_BRANCH__",
                title: isChineseLanguage ? "全部 \(appLocalized(currentBranch))" : "Show All \(appLocalized(currentBranch))",
                count: branchItems.count,
                symbol: categorySymbol(currentBranch),
                coverAssetName: store.coverAssetName(for: currentBranch),
                hasChildren: false,
                isShowAll: true
            )
        )
        
        // 统计 Tier 3 子类
        var tier3Counts: [String: Int] = [:]
        for item in branchItems {
            let itemTiers = tiers(for: item)
            if let t3 = itemTiers.first(where: { $0.level == 3 }) {
                tier3Counts[t3.key, default: 0] += 1
            }
        }
        
        let sortedTier3 = tier3Counts.keys.sorted { k1, k2 in
            let o1 = catalogFamilyOrder(k1, root: currentRoot)
            let o2 = catalogFamilyOrder(k2, root: currentRoot)
            if o1 != o2 { return o1 < o2 }
            return appLocalized(k1).localizedStandardCompare(appLocalized(k2)) == .orderedAscending
        }
        
        for k in sortedTier3 {
            let c = tier3Counts[k] ?? 0
            guard c > 0 else { continue }
            let cover = store.coverAssetName(for: k)
            tags.append(
                MacCategoryTagItem(
                    key: k,
                    title: appLocalized(k),
                    count: c,
                    symbol: categorySymbol(k),
                    coverAssetName: cover,
                    hasChildren: false,
                    isShowAll: false
                )
            )
        }
        
        return tags
    }
    
    // MARK: - 4. 针对 Show All 模式生成按小分类分组的 Section 结构
    static func groupItems(
        items: [CollectionItem],
        rootCategory: String?,
        branch: String?,
        family: String?
    ) -> [MacCollectionSectionGroup] {
        let store = CategoryCoverStore.shared
        
        // ----------------------------------------------------
        // Case A: 顶层根目录 (Root "All") -> 按大类划分
        // ----------------------------------------------------
        if rootCategory == nil {
            var grouped: [String: [CollectionItem]] = [:]
            for item in items {
                let r = itemRootCategory(item)
                grouped[r, default: []].append(item)
            }
            
            let standardRoots = [
                "Mac", "iPhone", "iPad", "Watch", "AirPods", "iPod",
                "Input Devices", "Beats", "Accessories", "Displays", "Home", "AirPort", "Vision Pro"
            ]
            let sortedKeys = grouped.keys.sorted { r1, r2 in
                let idx1 = standardRoots.firstIndex(of: r1) ?? 99
                let idx2 = standardRoots.firstIndex(of: r2) ?? 99
                if idx1 != idx2 { return idx1 < idx2 }
                return categoryTitle(r1).localizedStandardCompare(categoryTitle(r2)) == .orderedAscending
            }
            
            return sortedKeys.compactMap { key in
                guard let list = grouped[key], !list.isEmpty else { return nil }
                return MacCollectionSectionGroup(
                    key: key,
                    title: key,
                    localizedTitle: categoryTitle(key),
                    symbol: categorySymbol(key),
                    coverAssetName: store.coverAssetName(for: key),
                    items: list
                )
            }
        }
        
        guard let currentRoot = rootCategory else { return [] }
        
        // ----------------------------------------------------
        // Case B: 大类层级下的 Show All (例如 iPhone 或 Mac)
        // ----------------------------------------------------
        if branch == nil && family == nil {
            var grouped: [String: [CollectionItem]] = [:]
            for item in items {
                let itemTiers = tiers(for: item)
                let subName = itemTiers.first(where: { $0.level == 2 })?.key ?? currentRoot
                grouped[subName, default: []].append(item)
            }
            
            let sortedSubKeys = grouped.keys.sorted { k1, k2 in
                let o1 = catalogFamilyOrder(k1, root: currentRoot)
                let o2 = catalogFamilyOrder(k2, root: currentRoot)
                if o1 != o2 { return o1 < o2 }
                return appLocalized(k1).localizedStandardCompare(appLocalized(k2)) == .orderedAscending
            }
            
            return sortedSubKeys.compactMap { key in
                guard let list = grouped[key], !list.isEmpty else { return nil }
                return MacCollectionSectionGroup(
                    key: key,
                    title: key,
                    localizedTitle: appLocalized(key),
                    symbol: categorySymbol(key),
                    coverAssetName: store.coverAssetName(for: key),
                    items: list
                )
            }
        }
        
        // ----------------------------------------------------
        // Case C: 分支层级下的 Show All (例如 Mac -> MacBook)
        // ----------------------------------------------------
        if let currentBranch = branch, family == nil {
            var grouped: [String: [CollectionItem]] = [:]
            for item in items {
                let itemTiers = tiers(for: item)
                let subName = itemTiers.first(where: { $0.level == 3 })?.key ??
                              itemTiers.first(where: { $0.level == 2 })?.key ?? currentBranch
                grouped[subName, default: []].append(item)
            }
            
            let sortedSubKeys = grouped.keys.sorted { k1, k2 in
                let o1 = catalogFamilyOrder(k1, root: currentRoot)
                let o2 = catalogFamilyOrder(k2, root: currentRoot)
                if o1 != o2 { return o1 < o2 }
                return appLocalized(k1).localizedStandardCompare(appLocalized(k2)) == .orderedAscending
            }
            
            return sortedSubKeys.compactMap { key in
                guard let list = grouped[key], !list.isEmpty else { return nil }
                return MacCollectionSectionGroup(
                    key: key,
                    title: key,
                    localizedTitle: appLocalized(key),
                    symbol: categorySymbol(key),
                    coverAssetName: store.coverAssetName(for: key),
                    items: list
                )
            }
        }
        
        // ----------------------------------------------------
        // Case D: 单一叶子类别 (例如选中了 iPhone Pro 或 MacBook Pro)
        // ----------------------------------------------------
        let leafKey = family ?? branch ?? currentRoot
        return [
            MacCollectionSectionGroup(
                key: leafKey,
                title: leafKey,
                localizedTitle: appLocalized(leafKey),
                symbol: categorySymbol(leafKey),
                coverAssetName: store.coverAssetName(for: leafKey),
                items: items
            )
        ]
    }
}
