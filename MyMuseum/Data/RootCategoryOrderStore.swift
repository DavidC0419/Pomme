//
//  RootCategoryOrderStore.swift
//  Pomme
//
//  一级大类自定义排序持久化存储器与重排视图
//

import SwiftUI
import Combine

@MainActor
final class RootCategoryOrderStore: ObservableObject {
    static let shared = RootCategoryOrderStore()
    
    @Published var encyclopediaOrder: [String] = []
    @Published var collectionOrder: [String] = []
    @Published var batteryOrder: [String] = []
    
    private let encyclopediaKey = "rootCategoryOrder_encyclopedia_v2"
    private let collectionKey = "rootCategoryOrder_collection_v2"
    private let batteryKey = "rootCategoryOrder_battery_v2"
    private let orderUpdatedKey = "rootCategoryOrder_updatedAt"

    @Published var orderUpdatedAt: Date?

    init() {
        let isStaleRoot: (String) -> Bool = {
            $0 == "Mac desktops" || $0 == "Mac Desktops" || $0.localizedCaseInsensitiveContains("mac desktop")
        }
        self.encyclopediaOrder = (UserDefaults.standard.stringArray(forKey: encyclopediaKey) ?? []).filter { !isStaleRoot($0) }
        self.collectionOrder = (UserDefaults.standard.stringArray(forKey: collectionKey) ?? []).filter { !isStaleRoot($0) }
        self.batteryOrder = (UserDefaults.standard.stringArray(forKey: batteryKey) ?? []).filter { !isStaleRoot($0) }
        let timestamp = UserDefaults.standard.double(forKey: orderUpdatedKey)
        self.orderUpdatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    func orderedCategories(from defaultCategories: [String], isEncyclopedia: Bool) -> [String] {
        let saved = isEncyclopedia ? encyclopediaOrder : collectionOrder
        guard !saved.isEmpty else { return defaultCategories }
        var result: [String] = []
        for cat in saved {
            if cat == "Mac desktops" || cat == "Mac Desktops" || cat.localizedCaseInsensitiveContains("mac desktop") { continue }
            let mapped = (cat == "Apple Vision Pro") ? "Vision Pro" : (cat == "Apple Watch" ? "Watch" : cat)
            if defaultCategories.contains(mapped) && !result.contains(mapped) {
                result.append(mapped)
            }
        }
        for cat in defaultCategories where !result.contains(cat) {
            result.append(cat)
        }
        return result
    }

    func orderedBatteryCategories(from defaultCategories: [String]) -> [String] {
        guard !batteryOrder.isEmpty else { return defaultCategories }
        var result: [String] = []
        for cat in batteryOrder {
            let mapped = (cat == "Apple Vision Pro") ? "Vision Pro" : (cat == "Apple Watch" ? "Watch" : (cat == "配件" ? "Accessories" : cat))
            if defaultCategories.contains(mapped) && !result.contains(mapped) {
                result.append(mapped)
            }
        }
        for cat in defaultCategories where !result.contains(cat) {
            result.append(cat)
        }
        return result
    }

    func saveOrder(_ newOrder: [String], isEncyclopedia: Bool) {
        let now = Date()
        if isEncyclopedia {
            encyclopediaOrder = newOrder
            UserDefaults.standard.set(newOrder, forKey: encyclopediaKey)
        } else {
            collectionOrder = newOrder
            UserDefaults.standard.set(newOrder, forKey: collectionKey)
        }
        orderUpdatedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: orderUpdatedKey)
        objectWillChange.send()
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    func saveBatteryOrder(_ newOrder: [String]) {
        let now = Date()
        batteryOrder = newOrder
        UserDefaults.standard.set(newOrder, forKey: batteryKey)
        orderUpdatedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: orderUpdatedKey)
        objectWillChange.send()
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    func applyRemoteOrder(_ newOrder: [String], isEncyclopedia: Bool, updatedAt: Date) {
        if isEncyclopedia {
            encyclopediaOrder = newOrder
            UserDefaults.standard.set(newOrder, forKey: encyclopediaKey)
        } else {
            collectionOrder = newOrder
            UserDefaults.standard.set(newOrder, forKey: collectionKey)
        }
        orderUpdatedAt = updatedAt
        UserDefaults.standard.set(updatedAt.timeIntervalSince1970, forKey: orderUpdatedKey)
        objectWillChange.send()
    }

    func applyRemoteBatteryOrder(_ newOrder: [String], updatedAt: Date) {
        batteryOrder = newOrder
        UserDefaults.standard.set(newOrder, forKey: batteryKey)
        orderUpdatedAt = updatedAt
        UserDefaults.standard.set(updatedAt.timeIntervalSince1970, forKey: orderUpdatedKey)
        objectWillChange.send()
    }

    func reload() {
        self.encyclopediaOrder = UserDefaults.standard.stringArray(forKey: encyclopediaKey) ?? []
        self.collectionOrder = UserDefaults.standard.stringArray(forKey: collectionKey) ?? []
        self.batteryOrder = UserDefaults.standard.stringArray(forKey: batteryKey) ?? []
        let timestamp = UserDefaults.standard.double(forKey: orderUpdatedKey)
        self.orderUpdatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        objectWillChange.send()
    }

    func resetOrder(isEncyclopedia: Bool, defaultCategories: [String]) {
        if isEncyclopedia {
            encyclopediaOrder = []
            UserDefaults.standard.removeObject(forKey: encyclopediaKey)
        } else {
            collectionOrder = []
            UserDefaults.standard.removeObject(forKey: collectionKey)
        }
        objectWillChange.send()
    }

    func resetBatteryOrder(defaultCategories: [String]) {
        batteryOrder = []
        UserDefaults.standard.removeObject(forKey: batteryKey)
        objectWillChange.send()
    }
}

// MARK: - 一级分类重排列表视图
struct ReorderCategoriesSheet: View {
    let isEncyclopedia: Bool
    let defaultCategories: [String]
    @ObservedObject var orderStore = RootCategoryOrderStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentOrder: [String] = []
    
    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text(appLocalized("Drag items using the reorder handle to change how categories appear."))) {
                    ForEach(currentOrder, id: \.self) { category in
                        HStack(spacing: 12) {
                            Image(systemName: categorySymbol(category))
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            Text(categoryTitle(category))
                                .font(.body.weight(.medium))
                            Spacer()
                        }
                    }
                    .onMove { indices, newOffset in
                        currentOrder.move(fromOffsets: indices, toOffset: newOffset)
                        orderStore.saveOrder(currentOrder, isEncyclopedia: isEncyclopedia)
                    }
                }
            }
#if !os(macOS)
            .environment(\.editMode, .constant(.active))
#endif
            .navigationTitle(appLocalized("Rearrange Categories"))
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLocalized("Reset")) {
                        orderStore.resetOrder(isEncyclopedia: isEncyclopedia, defaultCategories: defaultCategories)
                        currentOrder = defaultCategories
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appLocalized("Done")) {
                        orderStore.saveOrder(currentOrder, isEncyclopedia: isEncyclopedia)
                        dismiss()
                    }
                }
            }
            .onAppear {
                currentOrder = orderStore.orderedCategories(from: defaultCategories, isEncyclopedia: isEncyclopedia)
            }
        }
    }
}

// MARK: - 电池管家分类顺序微调与排序面板
struct ReorderBatteryCategoriesSheet: View {
    let availableCategories: [String]
    let defaultCategories: [String]
    @ObservedObject var orderStore = RootCategoryOrderStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentOrder: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(currentOrder, id: \.self) { category in
                        HStack(spacing: 12) {
                            Image(systemName: categorySymbol(category))
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)

                            Text(categoryTitle(category))
                                .font(.body.weight(.medium))

                            Spacer()

                            // 上下移动微调按钮（方便触控点按与无重排手柄环境）
                            HStack(spacing: 8) {
                                Button {
                                    moveCategory(category, direction: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 28, height: 28)
                                        .background(Color.primary.opacity(0.06), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(currentOrder.first == category)

                                Button {
                                    moveCategory(category, direction: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 28, height: 28)
                                        .background(Color.primary.opacity(0.06), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(currentOrder.last == category)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { indices, newOffset in
                        currentOrder.move(fromOffsets: indices, toOffset: newOffset)
                        orderStore.saveBatteryOrder(currentOrder)
                    }
                } footer: {
                    Text(isChineseLanguage ? "拖拽右侧三条线重排手柄，或点按上下箭头，自定义电池管家各分类的排序。" : "Drag the handles on the right or use arrows to customize category order.")
                        .font(.caption)
                }
            }
#if !os(macOS)
            .environment(\.editMode, .constant(.active))
#endif
            .navigationTitle(isChineseLanguage ? "调整分类顺序" : "Reorder Categories")
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChineseLanguage ? "恢复默认" : "Reset") {
                        orderStore.resetBatteryOrder(defaultCategories: defaultCategories)
                        currentOrder = orderStore.orderedBatteryCategories(from: availableCategories)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChineseLanguage ? "完成" : "Done") {
                        orderStore.saveBatteryOrder(currentOrder)
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                }
            }
            .onAppear {
                currentOrder = orderStore.orderedBatteryCategories(from: availableCategories)
            }
        }
    }

    private func moveCategory(_ category: String, direction: Int) {
        guard let idx = currentOrder.firstIndex(of: category) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0 && newIdx < currentOrder.count else { return }
        withAnimation {
            currentOrder.swapAt(idx, newIdx)
            orderStore.saveBatteryOrder(currentOrder)
        }
    }
}
