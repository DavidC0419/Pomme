//
//  MacWorkbenchSidebarView.swift
//  Pomme
//
//  Mac 策展人工作台左侧导航边栏 (Mac Curator Workbench Sidebar)
//

import SwiftUI

struct MacWorkbenchSidebarView: View {
    @Binding var sidebarSelection: MacSidebarSelection?
    let collectionItems: [CollectionItem]
    let favoriteIDs: Set<String>
    let museumTitle: String
    
    var body: some View {
        List(selection: $sidebarSelection) {
            // 馆藏智能视图
            Section(isChineseLanguage ? "馆藏策展视图" : "Curator Views") {
                NavigationLink(value: MacSidebarSelection.all) {
                    Label {
                        HStack {
                            Text(isChineseLanguage ? "全部藏品" : "All Collection")
                            Spacer()
                            badgeCount(collectionItems.count)
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.blue)
                    }
                }
                
                NavigationLink(value: MacSidebarSelection.inUse) {
                    Label {
                        HStack {
                            Text(isChineseLanguage ? "在用主力机" : "Daily Drivers")
                            Spacer()
                            badgeCount(collectionItems.filter(\.isDailyDriver).count)
                        }
                    } icon: {
                        Image(systemName: "bolt.badge.clock")
                            .foregroundStyle(.green)
                    }
                }
                
                NavigationLink(value: MacSidebarSelection.battery) {
                    Label {
                        HStack {
                            Text(isChineseLanguage ? "电池巡检" : "Battery Health")
                            Spacer()
                            let overdue = collectionItems.filter {
                                (BatteryMaintenanceManager.deviceHasRechargeableBattery($0) || BatteryMaintenanceManager.isAirTag($0)) &&
                                !$0.batteryTrackingIgnored &&
                                !BatteryMaintenanceManager.isAirTagInsulated($0) &&
                                BatteryMaintenanceManager.evaluateMaintenance(for: $0, relativeTo: Date())?.status == .overdue
                            }.count
                            if overdue > 0 {
                                Text("\(overdue)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                                    .foregroundStyle(.white)
                            } else {
                                badgeCount(collectionItems.filter { (BatteryMaintenanceManager.deviceHasRechargeableBattery($0) || BatteryMaintenanceManager.isAirTag($0)) && !$0.batteryTrackingIgnored }.count)
                            }
                        }
                    } icon: {
                        Image(systemName: "battery.100.bolt")
                            .foregroundStyle(.orange)
                    }
                }
                
                NavigationLink(value: MacSidebarSelection.favorites) {
                    Label {
                        HStack {
                            Text(isChineseLanguage ? "星标最爱" : "Favorites")
                            Spacer()
                            badgeCount(collectionItems.filter { favoriteIDs.contains($0.favoriteKey) }.count)
                        }
                    } icon: {
                        Image(systemName: "star")
                            .foregroundStyle(.yellow)
                    }
                }
                
                NavigationLink(value: MacSidebarSelection.dataHealth) {
                    Label {
                        HStack {
                            Text(isChineseLanguage ? "数据健康体检" : "Data Health")
                            Spacer()
                            let snap = MacDataHealthSnapshot.analyze(items: collectionItems)
                            Text("\(snap.overallScore)%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(snap.overallScore >= 80 ? .green : .orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    } icon: {
                        Image(systemName: "heart.text.square")
                            .foregroundStyle(.purple)
                    }
                }
            }
            
            // 系统探索与资讯
            Section(isChineseLanguage ? "探索与档案" : "Library") {
                NavigationLink(value: MacSidebarSelection.encyclopedia) {
                    Label(isChineseLanguage ? "硬件全景百科" : "Encyclopedia", systemImage: "books.vertical")
                }
                NavigationLink(value: MacSidebarSelection.wishlist) {
                    Label(isChineseLanguage ? "愿望单与雷达" : "Wishlist & Radar", systemImage: "dollarsign.circle")
                }
                NavigationLink(value: MacSidebarSelection.rumors) {
                    Label(isChineseLanguage ? "资讯与传闻" : "News & Rumors", systemImage: "newspaper")
                }
                #if DEBUG
                NavigationLink(value: MacSidebarSelection.spatialMuseum) {
                    Label(isChineseLanguage ? "3D 空间展厅" : "3D Gallery", systemImage: "cube.transparent")
                }
                #endif
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(museumTitle.isEmpty ? (isChineseLanguage ? "我的藏品" : "My Museum") : museumTitle)
    }
    
    private func badgeCount(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}
