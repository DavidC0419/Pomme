//
//  SampleDataManager.swift
//  Pomme
//
//  示例设备数据管理 (Sample Devices & Demonstration Manager)
//  提供全面的软硬件全功能模拟示例（收藏、喜欢、想要、电池季度防饿死管理等）
//  序列号全部保持空着（不乱写），并提供一键极速清空与按需重新载入。
//

import Foundation
import SwiftUI

struct SampleDataManager {
    static let samplePrefix = "sample-"
    static let sampleClearedKey = "hasClearedSampleDevices_v1"
    static let sampleInitializedKey = "hasInitializedSampleDevices_v1"

    /// 演示愿望单型号 catalogID
    static let sampleWishlistIDs: Set<String> = [
        "RealityDevice14,1", // Apple Vision Pro
        "MacPro7,1"          // Mac Pro (2019)
    ]

    /// 演示最爱藏品 ID
    static let sampleFavoriteIDs: Set<String> = [
        "sample-macbook-pro",
        "sample-ipod-classic",
        "sample-macintosh-128k"
    ]

    /// 判断单件藏品是否属于示例演示数据
    static func isSampleItem(_ item: CollectionItem) -> Bool {
        item.id.hasPrefix(samplePrefix)
    }

    /// 判断当前列表中是否包含示例数据
    static func hasSampleItems(in items: [CollectionItem]) -> Bool {
        items.contains { isSampleItem($0) }
    }

    /// 构建功能全覆盖的模拟示例设备清单
    /// 包含：
    /// 1. Mac: MacBook Pro 16寸 (主力在用设备 · 高规格 · 标星喜欢)
    /// 2. iPhone: iPhone 15 Pro (日常主力 · 锂电健康 · 在用免防饿死)
    /// 3. iPod: iPod classic 160GB (季度防饿死补电超期示范 · 待充电预警 · 标星喜欢)
    /// 4. Apple Watch: Ultra 2 (运动穿戴 · 在用免维护)
    /// 5. AirPods: AirPods Max (经典银色头戴 · 正常存放定期补电示范)
    /// 6. Vintage Mac: Macintosh 128K (复古硬件 · 无锂电池免除电池跟踪示范 · 标星喜欢)
    /// 注意：所有设备 serialNumber 均置为空字符串，不伪造任何序列号。
    static func buildSampleItems() -> [CollectionItem] {
        let now = Date()
        return [
            CollectionItem(
                id: "sample-macbook-pro",
                name: "MacBook Pro (16-inch, Nov 2023)",
                category: "Mac",
                productName: "MacBook Pro (16-inch, Nov 2023)",
                customName: "主力工作站",
                model: "A2991",
                catalogID: "Mac15,9",
                serialNumber: "",
                modelVersion: "MUW63CH/A",
                regionVersion: "国行",
                productIdentifier: "Mac15,9",
                battery: "98%",
                lastCharged: "2026.10.15",
                screenSize: "16.2-inch",
                processor: "Apple M3 Max (14-core)",
                memory: "36 GB",
                storage: "1 TB",
                graphics: "Apple M3 Max 30-core GPU",
                color: "深空黑",
                system: "macOS Sonoma",
                osVersion: "14.6",
                account: "个人主力账号",
                releaseYear: "2023",
                purchaseDate: "2024.1.18",
                purchaseSource: "Apple Store",
                warrantyStatus: "AppleCare+ 保修中",
                price: "24999",
                notes: "主力生产力设备，开启在用主力机模式，免受季度防饿死提醒。",
                isInUse: true,
                isBatteryUntracked: false,
                updatedAt: now
            ),
            CollectionItem(
                id: "sample-iphone-15pro",
                name: "iPhone 15 Pro",
                category: "iPhone",
                productName: "iPhone 15 Pro",
                customName: nil,
                model: "A3102",
                catalogID: "iPhone16,1",
                serialNumber: "",
                modelVersion: "MTV03CH/A",
                regionVersion: "国行",
                productIdentifier: "iPhone16,1",
                battery: "89%",
                lastCharged: "2026.10.18",
                screenSize: "6.1-inch",
                processor: "A17 Pro",
                memory: "8 GB",
                storage: "256 GB",
                graphics: "Apple 6-core GPU",
                color: "原色钛金属",
                system: "iOS 18",
                osVersion: "18.1",
                account: "个人主力账号",
                releaseYear: "2023",
                purchaseDate: "2023.9.22",
                purchaseSource: "Apple Store",
                warrantyStatus: "已过保",
                price: "7999",
                notes: "随身主力机，全天候视网膜屏。",
                isInUse: true,
                isBatteryUntracked: false,
                updatedAt: now
            ),
            CollectionItem(
                id: "sample-ipod-classic",
                name: "iPod classic (160 GB, Late 2009)",
                category: "iPod",
                productName: "iPod classic (160 GB, Late 2009)",
                customName: "无损音乐库",
                model: "A1238",
                catalogID: "iPod-23",
                serialNumber: "",
                modelVersion: "MC297CH/A",
                regionVersion: "国行",
                battery: "62%",
                lastCharged: "2026.7.10", // 距今已超90天，直观展现季度补电预警红标
                screenSize: "2.5-inch",
                storage: "160 GB",
                color: "银色",
                system: "iPod OS 2.0.5",
                releaseYear: "2009",
                purchaseDate: "2022.5.10",
                purchaseSource: "数码玩家收藏转让",
                price: "680",
                notes: "经典微硬盘音乐播放器，已纳入季度防饿死补电管理（当前已超期需补电）。",
                isInUse: false,
                isBatteryUntracked: false,
                updatedAt: now
            ),
            CollectionItem(
                id: "sample-apple-watch-ultra",
                name: "Apple Watch Ultra 2 (GPS + Cellular)",
                category: "Apple Watch",
                productName: "Apple Watch Ultra 2 (GPS + Cellular)",
                customName: nil,
                model: "A2986",
                catalogID: "Watch7,5",
                serialNumber: "",
                modelVersion: "MREG3CH/A",
                battery: "95%",
                lastCharged: "2026.10.18",
                screenSize: "49mm",
                processor: "Apple S9 SiP",
                storage: "64 GB",
                color: "原色钛金属",
                system: "watchOS 11",
                releaseYear: "2023",
                purchaseDate: "2023.10.05",
                purchaseSource: "Apple Store",
                price: "6499",
                notes: "户外运动与跑步记录佩戴，日常在用设备。",
                isInUse: true,
                isBatteryUntracked: false,
                updatedAt: now
            ),
            CollectionItem(
                id: "sample-airpods-max",
                name: "AirPods Max (Lightning)",
                category: "AirPods",
                productName: "AirPods Max (Lightning)",
                customName: nil,
                model: "A2096",
                catalogID: "AirPodsMax1,1",
                serialNumber: "",
                modelVersion: "MGYJ3CH/A",
                battery: "48%",
                lastCharged: "2026.8.20",
                color: "银色",
                releaseYear: "2020",
                purchaseDate: "2021.6.18",
                purchaseSource: "Apple Store",
                price: "3999",
                notes: "静置于耳机支架，定期关注剩余电量维护电池寿命。",
                isInUse: false,
                isBatteryUntracked: false,
                updatedAt: now
            ),
            CollectionItem(
                id: "sample-macintosh-128k",
                name: "Macintosh 128K",
                category: "Macintosh",
                productName: "Macintosh 128K",
                customName: "老乔划时代神作",
                model: "M0001",
                catalogID: "Macintosh_128K",
                serialNumber: "",
                screenSize: "9-inch",
                processor: "Motorola 68000 @ 8 MHz",
                memory: "128 KB",
                storage: "400 KB Floppy",
                color: "米白色",
                system: "System 1.0",
                releaseYear: "1984",
                purchaseDate: "2020.3.15",
                purchaseSource: "海外老电脑拍卖",
                price: "5800",
                notes: "个人电脑里程碑。纯交流电源供电无内置锂电池，已免除电池跟踪。",
                isInUse: false,
                isBatteryUntracked: true, // 免除电池跟踪示范
                updatedAt: now
            )
        ]
    }

    /// 加载示例数据，并同步注入最爱与愿望单
    static func loadSampleData(
        currentItems: [CollectionItem],
        ownedIDs: inout Set<String>,
        favoriteIDs: inout Set<String>,
        wantedIDs: inout Set<String>
    ) -> [CollectionItem] {
        var items = currentItems
        let samples = buildSampleItems()
        for sample in samples {
            if let idx = items.firstIndex(where: { $0.id == sample.id }) {
                items[idx] = sample
            } else {
                items.append(sample)
            }
            ownedIDs.insert(sample.catalogID ?? sample.id)
        }
        favoriteIDs.formUnion(sampleFavoriteIDs)
        wantedIDs.formUnion(sampleWishlistIDs)
        UserDefaults.standard.set(true, forKey: sampleInitializedKey)
        UserDefaults.standard.set(false, forKey: sampleClearedKey)
        return items
    }

    /// 极速清空所有示例数据（保留用户自定义录入的真实设备）
    static func removeSampleData(
        currentItems: [CollectionItem],
        ownedIDs: inout Set<String>,
        favoriteIDs: inout Set<String>,
        wantedIDs: inout Set<String>
    ) -> [CollectionItem] {
        let sampleCatalogIDs = Set(buildSampleItems().compactMap { $0.catalogID ?? $0.id })
        let filtered = currentItems.filter { !isSampleItem($0) }
        
        // 清理示例相关的 catalogID（如果用户没有添加同款真实设备）
        for catID in sampleCatalogIDs {
            let hasReal = filtered.contains { ($0.catalogID ?? $0.id) == catID }
            if !hasReal {
                ownedIDs.remove(catID)
            }
        }
        
        favoriteIDs.subtract(sampleFavoriteIDs)
        wantedIDs.subtract(sampleWishlistIDs)
        
        UserDefaults.standard.set(true, forKey: sampleClearedKey)
        return filtered
    }
}
