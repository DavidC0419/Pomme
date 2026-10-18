//
//  MacCuratorGroupedGridView.swift
//  Pomme
//
//  Mac 策展人工作台网格与表格小分类聚合展示组件 (Grouped Gallery & Table View)
//

import SwiftUI

struct MacCuratorGroupedGridView: View {
    let groups: [MacCollectionSectionGroup]
    let viewMode: MacViewMode
    let isMultiSelectMode: Bool
    @Binding var selectedItemID: String?
    @Binding var selectedItemIDs: Set<String>
    var favoriteIDs: Binding<Set<String>>
    let isBatteryMode: Bool
    let onSelect: (CollectionItem) -> Void
    let onToggleFavorite: (CollectionItem) -> Void
    let onToggleDailyDriver: (CollectionItem) -> Void
    let onLogCharge: ((CollectionItem) -> Void)?
    let onQuickLook: (CollectionItem) -> Void
    let onUpdate: (CollectionItem) -> Void
    
    @ObservedObject private var coverStore = CategoryCoverStore.shared
    @Environment(\.locale) private var locale
    private var isChineseLanguage: Bool {
        locale.identifier.hasPrefix("zh") || Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }
    
    var body: some View {
        if viewMode == .grid {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(groups) { group in
                        sectionBlock(group)
                    }
                }
                .padding(18)
            }
        } else {
            // 表格视图
            List(selection: isMultiSelectMode ? nil : $selectedItemID) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            MacWorkbenchTableRowView(
                                item: item,
                                isBatteryMode: isBatteryMode,
                                isMultiSelectMode: isMultiSelectMode,
                                selectedItemIDs: $selectedItemIDs,
                                onUpdate: onUpdate
                            )
                        }
                    } header: {
                        sectionHeaderView(group)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #else
            .listStyle(.inset)
            #endif
        }
    }
    
    // MARK: - 网格单个分组块
    private func sectionBlock(_ group: MacCollectionSectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 分组标题栏 (带小分类主图封面与件数)
            sectionHeaderView(group)
            
            // 组内网格
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175, maximum: 220), spacing: 16)], spacing: 16) {
                ForEach(group.items) { item in
                    let isSelected = isMultiSelectMode ? selectedItemIDs.contains(item.id) : (selectedItemID == item.id)
                    let favs = favoriteIDs.wrappedValue
                    
                    MacGridItemCardView(
                        item: item,
                        isSelected: isSelected,
                        isMultiSelectMode: isMultiSelectMode,
                        isFavorite: favs.contains(item.favoriteKey),
                        isBatteryMode: isBatteryMode,
                        onSelect: {
                            onSelect(item)
                        },
                        onToggleFavorite: {
                            onToggleFavorite(item)
                        },
                        onToggleDailyDriver: {
                            onToggleDailyDriver(item)
                        },
                        onLogCharge: onLogCharge != nil ? {
                            onLogCharge?(item)
                        } : nil,
                        onQuickLook: {
                            onQuickLook(item)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - 分类段落头部 (Section Header with Cover Artwork)
    private func sectionHeaderView(_ group: MacCollectionSectionGroup) -> some View {
        HStack(spacing: 8) {
            // 封面图视觉系统：优先展示该分类官方或用户自定义封面大图
            let coverName = group.coverAssetName ?? coverStore.coverAssetName(for: group.key)
            if let cover = coverName, imageAssetExists(cover) {
                Image(cover)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: group.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            
            Text(group.localizedTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
            
            Text("\(group.items.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.06), in: Capsule())
            
            Spacer()
            
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}
