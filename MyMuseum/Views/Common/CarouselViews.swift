//
//  CarouselViews.swift
//  Pomme
//
//  轮播图组件 (Carousel Views)
//  用于首页“特别心动/喜欢”藏品或图鉴产品的自动轮播与手动滑动画廊。
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 轮播数据项模型
struct FavoriteCarouselEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let artworkName: String
    let item: CollectionItem?
    let device: Device?
    
    static func == (lhs: FavoriteCarouselEntry, rhs: FavoriteCarouselEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 轮播图原始顺序存储器
@MainActor
final class CarouselOrderStore: ObservableObject {
    static let shared = CarouselOrderStore()
    
    private let storageKey = "favorite_carousel_custom_order_ids_v2"
    @Published var customOrderIDs: [String] = []
    
    init() {
        self.customOrderIDs = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }
    
    func orderedEntries(_ entries: [FavoriteCarouselEntry]) -> [FavoriteCarouselEntry] {
        guard !customOrderIDs.isEmpty else { return entries }
        var result: [FavoriteCarouselEntry] = []
        let entryMap = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in customOrderIDs {
            if let entry = entryMap[id] {
                result.append(entry)
            }
        }
        for entry in entries where !result.contains(where: { $0.id == entry.id }) {
            result.append(entry)
        }
        return result
    }
    
    func saveOrder(_ ids: [String]) {
        self.customOrderIDs = ids
        UserDefaults.standard.set(ids, forKey: storageKey)
        objectWillChange.send()
    }
    
    func resetOrder() {
        self.customOrderIDs = []
        UserDefaults.standard.removeObject(forKey: storageKey)
        objectWillChange.send()
    }
}

// MARK: - 轮播原始顺序自定义编辑页
struct ReorderCarouselSheet: View {
    let entries: [FavoriteCarouselEntry]
    @ObservedObject var store = CarouselOrderStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentEntries: [FavoriteCarouselEntry] = []
    
    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text(appLocalized("Drag items to customize the original carousel order."))) {
                    ForEach(currentEntries) { entry in
                        HStack(spacing: 12) {
                            if !entry.artworkName.isEmpty, imageAssetExists(entry.artworkName) {
                                Image(entry.artworkName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            } else {
                                Image(systemName: "photo")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                            }
                            Text(appLocalized(entry.title))
                                .font(.body.weight(.medium))
                            Spacer()
                        }
                    }
                    .onMove { indices, newOffset in
                        currentEntries.move(fromOffsets: indices, toOffset: newOffset)
                        store.saveOrder(currentEntries.map(\.id))
                    }
                }
            }
#if !os(macOS)
            .environment(\.editMode, .constant(.active))
#endif
            .navigationTitle(appLocalized("Customize Carousel Order"))
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLocalized("Reset")) {
                        store.resetOrder()
                        currentEntries = entries
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appLocalized("Done")) {
                        store.saveOrder(currentEntries.map(\.id))
                        dismiss()
                    }
                }
            }
            .onAppear {
                currentEntries = store.orderedEntries(entries)
            }
        }
    }
}

// MARK: - 首页喜欢设备自动轮播画廊
// 首页喜欢区每十秒平移到下一张，支持随机重排、自定义原始顺序与手动滑动浏览。
struct FavoriteDeviceCarousel: View {
    let originalEntries: [FavoriteCarouselEntry]
    let onOpenItem: (CollectionItem) -> Void
    let onOpenDevice: (Device) -> Void
    
    @ObservedObject private var orderStore = CarouselOrderStore.shared
    @State private var isShuffled = false
    @State private var shuffledEntries: [FavoriteCarouselEntry] = []
    @State private var showingReorderSheet = false
    @State private var currentEntryID: String?
    @State private var isUserScrolling = false
    @Environment(\.scenePhase) private var scenePhase

    init(
        items: [CollectionItem],
        devices: [Device],
        onOpenItem: @escaping (CollectionItem) -> Void,
        onOpenDevice: @escaping (Device) -> Void
    ) {
        self.originalEntries = items.map {
            FavoriteCarouselEntry(id: $0.id, title: $0.displayName, artworkName: $0.artworkAssetName, item: $0, device: nil)
        } + devices.map {
            FavoriteCarouselEntry(id: "catalog-\($0.id)", title: $0.name, artworkName: deviceArtworkAssetName($0.id, color: $0.color), item: nil, device: $0)
        }
        self.onOpenItem = onOpenItem
        self.onOpenDevice = onOpenDevice
    }

    private var displayEntries: [FavoriteCarouselEntry] {
        if isShuffled {
            return shuffledEntries
        }
        return orderStore.orderedEntries(originalEntries)
    }

    private func toggleShuffle() {
        if isShuffled {
            isShuffled = false
        } else {
            let base = orderStore.orderedEntries(originalEntries)
            var shuffled = base.shuffled()
            if shuffled == base && base.count > 1 {
                shuffled = Array(base.reversed())
            }
            shuffledEntries = shuffled
            isShuffled = true
        }
        #if canImport(UIKit) && !os(visionOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    var body: some View {
        VStack(spacing: 8) {
            // 控制条：随机按钮（按一下打开随机重排，再按一下关上回到原始顺序，再按一下再次随机重排）与自定义顺序入口
            HStack(spacing: 10) {
                Spacer()
                Button {
                    toggleShuffle()
                } label: {
                    Label(appLocalized(isShuffled ? "Shuffled" : "Shuffle"), systemImage: isShuffled ? "shuffle.circle.fill" : "shuffle")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isShuffled ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(isShuffled ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    showingReorderSheet = true
                } label: {
                    Label(appLocalized("Order"), systemImage: "arrow.up.arrow.down.circle")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 4)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(displayEntries) { entry in
                        carouselLink(for: entry)
                            .containerRelativeFrame(.horizontal) { width, axis in
                                min(340.0, max(240.0, width * 0.78))
                            }
                            .id(entry.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentEntryID, anchor: .center)
            .frame(height: 220)
        }
        .task(id: "\(isShuffled)_\(displayEntries.map(\.id).joined(separator: ","))") {
            guard !displayEntries.isEmpty else { return }
            if currentEntryID == nil || !displayEntries.contains(where: { $0.id == currentEntryID }) {
                currentEntryID = displayEntries.first?.id
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
                guard !Task.isCancelled, !isUserScrolling, !displayEntries.isEmpty,
                      scenePhase == .active, !PowerSavingManager.shared.isEcoActive else { continue }
                let currentIndex: Int
                if let cur = currentEntryID, let idx = displayEntries.firstIndex(where: { $0.id == cur }) {
                    currentIndex = idx
                } else {
                    currentIndex = 0
                    currentEntryID = displayEntries.first?.id
                }
                let nextIndex = (currentIndex + 1) % displayEntries.count
                withAnimation(.easeInOut(duration: 0.45)) {
                    self.currentEntryID = displayEntries[nextIndex].id
                }
            }
        }
        .sheet(isPresented: $showingReorderSheet) {
            ReorderCarouselSheet(entries: originalEntries)
        }
    }

    @ViewBuilder
    private func carouselLink(for entry: FavoriteCarouselEntry) -> some View {
        if let item = entry.item {
            Button {
                onOpenItem(item)
            } label: {
                FavoriteCarouselCard(title: entry.title, artworkName: entry.artworkName)
            }
            .buttonStyle(.plain)
        } else if let device = entry.device {
            Button {
                onOpenDevice(device)
            } label: {
                FavoriteCarouselCard(title: entry.title, artworkName: entry.artworkName)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 轮播单卡展示
struct FavoriteCarouselCard: View {
    let title: String
    let artworkName: String

    private var hasArtwork: Bool {
#if canImport(UIKit)
        UIImage(named: artworkName) != nil
#elseif canImport(AppKit)
        NSImage(named: NSImage.Name(artworkName)) != nil
#else
        false
#endif
    }

    var body: some View {
        VStack(spacing: 8) {
            if hasArtwork {
                Image(artworkName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 170)
                    .clipped()
            } else {
                Text(appLocalized(title))
                    .font(.title2.weight(.medium))
                    .frame(height: 170)
            }
            Text(appLocalized(title))
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
