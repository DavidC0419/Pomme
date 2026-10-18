//
//  InUseDevicesView.swift
//  Pomme
//
//  常用 / 在用设备视图 (In-Use / Daily Drivers View)
//  集中展示用户当前日常高频使用的所有设备。
//  特点：不设首页外露轮播、设备统一平铺展示（无需按品类二次分类），且自动免除防饿死补电维护周期。
//

import SwiftUI

struct InUseDevicesView: View {
    let items: [CollectionItem]
    let onUpdate: (CollectionItem) -> Void
    var onBatchUpdate: (([CollectionItem]) -> Void)? = nil
    let onDelete: (String) -> Void
    @Binding var favoriteIDs: Set<String>

    @State private var searchText: String = ""
    @State private var showingAddSheet: Bool = false
    @State private var selectedItemForDetail: CollectionItem? = nil

    /// 当前被标记为“常用 / 在用”的藏品
    private var inUseItems: [CollectionItem] {
        items.filter { $0.isDailyDriver }
    }

    /// 经过搜索过滤后的常用设备列表
    private var filteredItems: [CollectionItem] {
        let clean = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return inUseItems }
        return inUseItems.filter { item in
            item.displayName.localizedCaseInsensitiveContains(clean) ||
            item.name.localizedCaseInsensitiveContains(clean) ||
            item.category.localizedCaseInsensitiveContains(clean) ||
            (item.model?.localizedCaseInsensitiveContains(clean) ?? false) ||
            (item.serialNumber?.localizedCaseInsensitiveContains(clean) ?? false) ||
            (item.processor?.localizedCaseInsensitiveContains(clean) ?? false) ||
            (item.color?.localizedCaseInsensitiveContains(clean) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 吸顶搜索栏
            PinnedSearchField(
                text: $searchText,
                prompt: "Search daily drivers (model, color, chip, serial)"
            )

            if inUseItems.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 顶部状态横幅
                        headerBanner

                        // 常用设备列表（无需按品类多层折叠，直观呈现）
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165, maximum: 220), spacing: 14)], spacing: 14) {
                            ForEach(filteredItems) { item in
                                InUseDeviceCard(
                                    item: item,
                                    isFavorite: favoriteIDs.contains(item.favoriteKey),
                                    onTap: {
                                        selectedItemForDetail = item
                                    },
                                    onToggleFavorite: {
                                        if favoriteIDs.contains(item.favoriteKey) {
                                            favoriteIDs.remove(item.favoriteKey)
                                        } else {
                                            favoriteIDs.insert(item.favoriteKey)
                                        }
                                    },
                                    onRemoveFromDailyDriver: {
                                        BatteryMaintenanceManager.toggleDailyDriver(for: item, onUpdate: onUpdate)
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                }
                .dismissKeyboardOnScroll()
            }
        }
        .navigationTitle("Daily Drivers")
        .platformInlineTitleMode()
        .toolbar {
            ToolbarItem(placement: .appTopBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Daily Driver", systemImage: "plus")
                }
            }
        }
        .sheet(item: $selectedItemForDetail) { item in
            NavigationStack {
                CollectionDetailView(
                    item: item,
                    favoriteIDs: $favoriteIDs,
                    onSave: { updated in
                        onUpdate(updated)
                        selectedItemForDetail = updated
                    },
                    onDelete: { id in
                        onDelete(id)
                        selectedItemForDetail = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddDailyDriverSheet(
                items: items,
                onToggle: { item in
                    BatteryMaintenanceManager.toggleDailyDriver(for: item, onUpdate: onUpdate)
                }
            )
        }
    }

    // MARK: - 顶部说明条
    private var headerBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(inUseItems.count) Active Hardware Devices")
                    .font(.subheadline.weight(.semibold))
                Text("These devices are in daily rotation and exempt from quarterly battery starvation checks.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles.tv")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("No Daily Drivers Yet")
                    .font(.title3.bold())
                Text("Tag the devices you use every day. They will be highlighted here and automatically excluded from quarterly battery charge alerts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                showingAddSheet = true
            } label: {
                Label("Choose Daily Drivers", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - 常用设备卡片
struct InUseDeviceCard: View {
    let item: CollectionItem
    let isFavorite: Bool
    var onTap: () -> Void
    var onToggleFavorite: () -> Void
    var onRemoveFromDailyDriver: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 设备图片与右上角状态胶囊
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.04))
                        .aspectRatio(1.15, contentMode: .fit)
                        .overlay(
                            Image(item.artworkAssetName)
                                .resizable()
                                .scaledToFit()
                                .padding(isAirPodsMax2Device(item) ? 0 : 12)
                                .scaleEffect(isAirPodsMax2Device(item) ? 1.5 : 1.0)
                                .clipped()
                        )

                    // 在用标签
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("In Use")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
                }

                // 名称与硬件信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let model = item.model, !model.isEmpty {
                        Text(model)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(item.category)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    // 颜色与关键规格
                    HStack(spacing: 4) {
                        if let color = item.color, !color.isEmpty {
                            Circle()
                                .fill(colorSwatch(color))
                                .frame(width: 7, height: 7)
                            Text(deviceColorLabel(color))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let proc = item.processor, !proc.isEmpty {
                            Text("· " + proc)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 2)

                    if BatteryMaintenanceManager.isAirTag(item) {
                        HStack(spacing: 4) {
                            if let engraving = BatteryMaintenanceManager.airTagEngravingDescription(item) {
                                Text(engraving)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            Text(isChineseLanguage ? "CR2032 纽扣电池" : "CR2032 Coin Cell")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    onRemoveFromDailyDriver()
                }
            } label: {
                Label("Remove from Daily Drivers", systemImage: "sparkles.slash")
            }

            Button {
                onToggleFavorite()
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
        }
    }
}

// MARK: - 添加常用设备选择面板
struct AddDailyDriverSheet: View {
    let items: [CollectionItem]
    var onToggle: (CollectionItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var availableItems: [CollectionItem] {
        let clean = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return items }
        return items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(clean) ||
            item.category.localizedCaseInsensitiveContains(clean) ||
            (item.model?.localizedCaseInsensitiveContains(clean) ?? false) ||
            (item.serialNumber?.localizedCaseInsensitiveContains(clean) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select devices you actively use every day. Daily drivers are exempt from the quarterly battery maintenance cycle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("All Owned Hardware") {
                    ForEach(availableItems) { item in
                        HStack(spacing: 12) {
                            Image(item.artworkAssetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.subheadline.weight(.semibold))
                                HStack(spacing: 4) {
                                    Text(item.category)
                                    if let model = item.model {
                                        Text("· \(model)")
                                    }
                                    if let sn = item.serialNumber {
                                        Text("· \(sn)")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    onToggle(item)
                                }
                            } label: {
                                Image(systemName: item.isDailyDriver ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(item.isDailyDriver ? Color.blue : Color.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search hardware to tag as daily driver")
            .navigationTitle("Select Daily Drivers")
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
    }
}
