//
//  MacCuratorDetailInspectorView.swift
//  Pomme
//
//  Mac 策展人工作台右侧详情检查器 (Inspector View)
//

import SwiftUI

struct MacCuratorDetailInspectorView: View {
    let sidebarSelection: MacSidebarSelection?
    let collectionItems: [CollectionItem]
    @Binding var activeHealthFilter: DataHealthFilter?
    let isMultiSelectMode: Bool
    @Binding var selectedItemIDs: Set<String>
    let currentSelectedItem: CollectionItem?
    var favoriteIDs: Binding<Set<String>>
    let onBatchUpdate: ([CollectionItem]) -> Void
    let onUpdate: (CollectionItem) -> Void
    let onDelete: (String) -> Void
    let onQuickLook: (CollectionItem) -> Void
    
    @Environment(\.locale) private var locale
    private var isChineseLanguage: Bool {
        locale.identifier.hasPrefix("zh") || Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }
    
    var body: some View {
        if sidebarSelection == .dataHealth {
            MacDataHealthView(
                items: collectionItems,
                activeFilter: $activeHealthFilter,
                onSelectFilteredItems: { _ in }
            )
        } else if isMultiSelectMode && selectedItemIDs.count > 1 {
            let selectedList = collectionItems.filter { selectedItemIDs.contains($0.id) }
            MacBatchEditorView(
                selectedItems: selectedList,
                favoriteIDs: favoriteIDs,
                onBatchUpdate: onBatchUpdate,
                onBatchDelete: { ids in
                    for id in ids { onDelete(id) }
                },
                onClearSelection: {
                    selectedItemIDs.removeAll()
                }
            )
        } else if let item = currentSelectedItem {
            let favs = favoriteIDs.wrappedValue
            MacSingleItemInspectorView(
                item: item,
                isFavorite: favs.contains(item.favoriteKey),
                onToggleFavorite: {
                    if favs.contains(item.favoriteKey) {
                        favoriteIDs.wrappedValue.remove(item.favoriteKey)
                    } else {
                        favoriteIDs.wrappedValue.insert(item.favoriteKey)
                    }
                },
                onToggleDailyDriver: {
                    var m = item
                    m.isDailyDriver.toggle()
                    onUpdate(m)
                },
                onUpdate: onUpdate,
                onDelete: onDelete,
                onQuickLook: {
                    onQuickLook(item)
                }
            )
        } else {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "sidebar.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(isChineseLanguage ? "选择一件藏品查看详情" : "Select an item to inspect")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
