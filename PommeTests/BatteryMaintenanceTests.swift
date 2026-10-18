//
//  BatteryMaintenanceTests.swift
//  PommeTests
//
//  补电维护管理核心引擎与算法单元测试
//

import XCTest
@testable import Pomme

final class BatteryMaintenanceTests: XCTestCase {

    func testCycleDaysPerCategory() {
        // 1. AirPods / Beats / Apple Watch: 45 天基准
        var airpods = CollectionItem(id: "test_1", name: "AirPods Pro", category: "AirPods")
        XCTAssertEqual(BatteryMaintenanceManager.cycleDays(for: airpods), 45)

        // 2. iPod: 30 天基准
        var ipod = CollectionItem(id: "test_2", name: "iPod classic", category: "iPod")
        XCTAssertEqual(BatteryMaintenanceManager.cycleDays(for: ipod), 30)

        // 3. iPhone: 60 天基准
        var iphone = CollectionItem(id: "test_3", name: "iPhone 13 mini", category: "iPhone")
        XCTAssertEqual(BatteryMaintenanceManager.cycleDays(for: iphone), 60)

        // 4. iPad / Mac: 90 天基准
        var ipad = CollectionItem(id: "test_4", name: "iPad Air 4", category: "iPad")
        XCTAssertEqual(BatteryMaintenanceManager.cycleDays(for: ipad), 90)

        // 5. 用户自定义自适应周期优先
        airpods.customCycleDays = 55
        XCTAssertEqual(BatteryMaintenanceManager.cycleDays(for: airpods), 55)
    }

    func testDateParsingFormats() {
        // 支持多种日期格式解析
        let d1 = BatteryMaintenanceManager.parseChargeDate("2026.10.04")
        let d2 = BatteryMaintenanceManager.parseChargeDate("2026-10-04")
        let d3 = BatteryMaintenanceManager.parseChargeDate("2026/10/04")

        XCTAssertNotNil(d1)
        XCTAssertNotNil(d2)
        XCTAssertNotNil(d3)

        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: d1!), 2026)
        XCTAssertEqual(cal.component(.month, from: d1!), 10)
        XCTAssertEqual(cal.component(.day, from: d1!), 4)

        // 无效空字符串返回 nil
        XCTAssertNil(BatteryMaintenanceManager.parseChargeDate(nil))
        XCTAssertNil(BatteryMaintenanceManager.parseChargeDate("   "))
    }

    func testMaintenanceStatusEvaluation() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = Date()

        // 10 天前刚充过电的 iPhone (周期 60 天) -> 应当状态正常 healthy
        let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: today)!
        let itemHealthy = CollectionItem(
            id: "ip_healthy",
            name: "iPhone X",
            category: "iPhone",
            lastCharged: BatteryMaintenanceManager.formatChargeDate(tenDaysAgo)
        )
        let snapHealthy = BatteryMaintenanceManager.evaluateMaintenance(for: itemHealthy, relativeTo: today)
        XCTAssertNotNil(snapHealthy)
        XCTAssertEqual(snapHealthy?.status, .healthy)
        XCTAssertEqual(snapHealthy?.elapsedDays, 10)
        XCTAssertEqual(snapHealthy?.remainingDays, 50)

        // 65 天前充电的 iPhone (周期 60 天) -> 应当状态逾期 overdue
        let sixtyFiveDaysAgo = cal.date(byAdding: .day, value: -65, to: today)!
        let itemOverdue = CollectionItem(
            id: "ip_overdue",
            name: "iPhone X",
            category: "iPhone",
            lastCharged: BatteryMaintenanceManager.formatChargeDate(sixtyFiveDaysAgo)
        )
        let snapOverdue = BatteryMaintenanceManager.evaluateMaintenance(for: itemOverdue, relativeTo: today)
        XCTAssertEqual(snapOverdue?.status, .overdue)
        XCTAssertEqual(snapOverdue?.elapsedDays, 65)
        XCTAssertTrue((snapOverdue?.remainingDays ?? 0) < 0)

        // 常用设备（主力机）-> 应当为 inUse 状态
        var itemInUse = itemHealthy
        itemInUse.isInUse = true
        let snapInUse = BatteryMaintenanceManager.evaluateMaintenance(for: itemInUse, relativeTo: today)
        XCTAssertEqual(snapInUse?.status, .inUse)

        // 停止跟踪电池硬件 -> evaluateMaintenance 返回 nil
        var itemIgnored = itemHealthy
        itemIgnored.isBatteryUntracked = true
        let snapIgnored = BatteryMaintenanceManager.evaluateMaintenance(for: itemIgnored, relativeTo: today)
        XCTAssertNil(snapIgnored)
    }

    func testAirTagInsulationStatus() {
        let today = Date()
        var airtag = CollectionItem(
            id: "airtag_1",
            name: "AirTag",
            category: "AirTag",
            battery: "已装绝缘片"
        )
        // 绝缘片状态下应始终健康 (healthy)
        let snap = BatteryMaintenanceManager.evaluateMaintenance(for: airtag, relativeTo: today)
        XCTAssertEqual(snap?.status, .healthy)
        XCTAssertEqual(snap?.cycleDays, 365)
    }

    func testNoChargeDynamicCycleRules() {
        let cal = Calendar.current
        let today = Date()

        // 1. 已满充电周期（含超期）：当前耗电天数 65 天，原周期 60 天 (iPhone)
        // 规则：在当前耗电天数的基础上直接加 30 天 -> 65 + 30 = 95 天
        let sixtyFiveDaysAgo = cal.date(byAdding: .day, value: -65, to: today)!
        let itemOverdue = CollectionItem(
            id: "t_overdue",
            name: "iPhone 13",
            category: "iPhone",
            lastCharged: BatteryMaintenanceManager.formatChargeDate(sixtyFiveDaysAgo)
        )
        let (cur1, new1, _) = BatteryMaintenanceManager.calculateAdaptedCycle(for: itemOverdue, at: today, remainingLevel: .noCharge)
        XCTAssertEqual(cur1, 60)
        XCTAssertEqual(new1, 95) // 65 + 30

        // 2. 未满充电周期，且 (当前耗电天数 + 30) 未超过周期：
        // 当前耗电天数 20 天，原周期 60 天。20 + 30 = 50 <= 60
        // 规则：给充电周期增加 10 天 -> 60 + 10 = 70 天
        let twentyDaysAgo = cal.date(byAdding: .day, value: -20, to: today)!
        let itemEarlySafe = CollectionItem(
            id: "t_early_safe",
            name: "iPhone 13",
            category: "iPhone",
            lastCharged: BatteryMaintenanceManager.formatChargeDate(twentyDaysAgo)
        )
        let (cur2, new2, _) = BatteryMaintenanceManager.calculateAdaptedCycle(for: itemEarlySafe, at: today, remainingLevel: .noCharge)
        XCTAssertEqual(cur2, 60)
        XCTAssertEqual(new2, 70) // 60 + 10

        // 3. 未满充电周期，但 (当前耗电天数 + 30) 超过了原周期：
        // 当前耗电天数 40 天，原周期 60 天。40 + 30 = 70 > 60
        // 规则：在当前充电周期上直接加 30 天 -> 60 + 30 = 90 天
        let fortyDaysAgo = cal.date(byAdding: .day, value: -40, to: today)!
        let itemEarlyExceed = CollectionItem(
            id: "t_early_exceed",
            name: "iPhone 13",
            category: "iPhone",
            lastCharged: BatteryMaintenanceManager.formatChargeDate(fortyDaysAgo)
        )
        let (cur3, new3, _) = BatteryMaintenanceManager.calculateAdaptedCycle(for: itemEarlyExceed, at: today, remainingLevel: .noCharge)
        XCTAssertEqual(cur3, 60)
        XCTAssertEqual(new3, 90) // 60 + 30

        // 4. 验证 logNoChargeNeeded 不改变原有 lastCharged 充电日期
        var loggedItem = itemEarlyExceed
        let originalDate = loggedItem.lastCharged
        BatteryMaintenanceManager.logNoChargeNeeded(for: loggedItem, date: today) { updated in
            loggedItem = updated
        }
        XCTAssertEqual(loggedItem.lastCharged, originalDate) // 依然保留上次充电日期
        XCTAssertEqual(loggedItem.customCycleDays, 90) // 周期成功延长至 90 天
    }
}

