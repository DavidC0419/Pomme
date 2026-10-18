//
//  WishlistView.swift
//  Pomme
//
//  愿望清单视图 (Wishlist View)
//  管理心愿单中想购买的苹果设备，支持搜索与多选批量移出，防止误触。
//

import SwiftUI
import UserNotifications

// MARK: - 心愿单主视图 (Wishlist View)
struct WishlistView: View {
    let onAddOwned: (CollectionItem) -> Void
    var onRemoveOwned: ((String) -> Void)? = nil
    private let records = SearchCatalogProductIndex.records
    private let products = SearchCatalogProductIndex.products
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedProductIDs = Set<String>()
    @State private var showingBatchRemoveAlert = false
    @State private var productToRemove: CatalogDisplayProduct? = nil
    @State private var showingSingleRemoveAlert = false

    @AppStorage("wantedDeviceIDs") private var wantedIDsData = Data()
    @AppStorage("ownedDeviceIDs") private var ownedIDsData = Data()
    @AppStorage("favoriteDeviceIDs") private var favoriteIDsData = Data()

    private var wantedIDs: Binding<Set<String>> {
        Binding(get: { decodeIDs(from: wantedIDsData) }, set: { wantedIDsData = encodeIDs($0) })
    }

    private var ownedIDs: Binding<Set<String>> {
        Binding(get: { decodeIDs(from: ownedIDsData) }, set: { ownedIDsData = encodeIDs($0) })
    }

    private var favoriteIDs: Binding<Set<String>> {
        Binding(get: { decodeIDs(from: favoriteIDsData) }, set: { favoriteIDsData = encodeIDs($0) })
    }

    private var displayedProducts: [CatalogDisplayProduct] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return products.filter(isWanted)
        }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return groupedCatalogProducts(records.filter { record in
            terms.allSatisfy { record.searchText.localizedCaseInsensitiveContains($0) }
        }).filter(isWanted)
    }

    private var wantedCount: Int {
        products.filter(isWanted).count
    }

    @StateObject private var dropManager = LaunchDropManager.shared
    @State private var selectedTab: WishlistSegment = .wishlist
    @State private var selectedDropForDetail: LaunchDropItem? = nil
    @State private var showingAddCustomDrop = false
    @State private var showingPermissionAlert = false

    enum WishlistSegment: String, CaseIterable, Identifiable {
        case wishlist = "My Wishlist"
        case drops = "Launch Drops"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部果味胶囊切换：心愿单 (Wishlist) 在前 vs 抢购日程 (Drops) 在后
                Picker("", selection: $selectedTab) {
                    ForEach(WishlistSegment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.background)

                if selectedTab == .wishlist {
                    wishlistContentView
                } else {
                    dropsContentView
                }
            }
            .navigationTitle(selectedTab == .wishlist ? "My Wishlist" : "Launch Drops")
            .platformInlineTitleMode()
            .toolbar {
                if selectedTab == .drops {
                    ToolbarItem(placement: .appTopBarLeading) {
                        Button {
                            Task {
                                await dropManager.syncDropsFromNetwork()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(dropManager.isRefreshing)
                        .accessibilityLabel("Refresh launch drops")
                    }

                    ToolbarItem(placement: .appTopBarTrailing) {
                        Menu {
                            Button {
                                Task {
                                    let granted = await dropManager.requestNotificationPermission()
                                    if !granted {
                                        showingPermissionAlert = true
                                    }
                                }
                            } label: {
                                Label(
                                    dropManager.notificationPermissionStatus == .authorized ? "Notifications Enabled" : "Enable Launch Alerts",
                                    systemImage: dropManager.notificationPermissionStatus == .authorized ? "bell.badge.fill" : "bell"
                                )
                            }

                            Divider()

                            Button {
                                showingAddCustomDrop = true
                            } label: {
                                Label("Add Custom Drop", systemImage: "plus.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                } else {
                    if !displayedProducts.isEmpty {
                        ToolbarItem(placement: .appTopBarTrailing) {
                            Button(isSelecting ? appLocalized("Done") : appLocalized("Select")) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSelecting.toggle()
                                    if !isSelecting {
                                        selectedProductIDs.removeAll()
                                    }
                                }
                            }
                        }

                        if isSelecting {
                            ToolbarItem(placement: .appTopBarLeading) {
                                Button(selectedProductIDs.count == displayedProducts.count ? appLocalized("Deselect All") : appLocalized("Select All")) {
                                    if selectedProductIDs.count == displayedProducts.count {
                                        selectedProductIDs.removeAll()
                                    } else {
                                        selectedProductIDs = Set(displayedProducts.map(\.id))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedDropForDetail) { drop in
                LaunchDropDetailSheet(drop: drop)
            }
            .sheet(isPresented: $showingAddCustomDrop) {
                AddCustomDropSheet()
            }
            .alert("Notification Permission", isPresented: $showingPermissionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Enable notifications for Pomme in System Settings to get alerts 1 day, 30 minutes, and 5 minutes before drops go live.")
            }
            .safeAreaInset(edge: .bottom) {
                if selectedTab == .wishlist {
                    bottomBar
                }
            }
            .confirmationDialog(
                appLocalized("Remove from Wishlist"),
                isPresented: $showingBatchRemoveAlert,
                titleVisibility: .visible
            ) {
                Button(appLocalized("Remove from Wishlist"), role: .destructive) {
                    removeSelectedProducts()
                }
                Button(appLocalized("Cancel"), role: .cancel) { }
            } message: {
                Text(String(format: appLocalized("Remove %d item(s) from your wishlist? This only removes them from your wishlist; encyclopedia records remain untouched."), selectedProductIDs.count))
            }
            .confirmationDialog(
                appLocalized("Remove from Wishlist"),
                isPresented: $showingSingleRemoveAlert,
                titleVisibility: .visible
            ) {
                if let product = productToRemove {
                    Button(appLocalized("Remove from Wishlist"), role: .destructive) {
                        removeProduct(product)
                        productToRemove = nil
                    }
                }
                Button(appLocalized("Cancel"), role: .cancel) {
                    productToRemove = nil
                }
            } message: {
                if let product = productToRemove {
                    Text(String(format: appLocalized("Remove \"%@\" from your wishlist? Encyclopedia records will not be deleted."), product.name))
                }
            }
        }
    }

    // MARK: - 热门抢购主内容 (Hot Launch Drops View)
    @ViewBuilder
    private var dropsContentView: some View {
        let visibleDrops = dropManager.drops.filter { !dropManager.isDismissed($0) }
        let upcomingDrops = visibleDrops.filter { !$0.isLive }
        let liveOrRecentDrops = visibleDrops.filter { $0.isLive }
        let dismissedDrops = dropManager.drops.filter { dropManager.isDismissed($0) }

        ScrollView {
            VStack(spacing: 16) {
                // 1. 头条焦点看板：仅展示下一个即将发售的单品（已开售的历史单品不再霸占头条！）
                if let featuredDrop = upcomingDrops.first {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(appLocalized("Featured Upcoming Drop"), systemImage: "flame.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.12), in: Capsule())

                            Spacer()

                            Text(featuredDrop.status.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.orange)

                            // 允许用户直接取消/隐藏此头条单品
                            Button {
                                dropManager.dismissDrop(featuredDrop)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(appLocalized("Hide from Drops"))
                        }

                        // 单品大卡片
                        Button {
                            selectedDropForDetail = featuredDrop
                        } label: {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(featuredDrop.name)
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(.primary)

                                    Text(featuredDrop.localizedHeadline)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    Text(featuredDrop.startingPrice)
                                        .font(.headline)
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.top, 2)
                                }

                                Spacer()

                                if !featuredDrop.imageAssetName.isEmpty, imageAssetExists(featuredDrop.imageAssetName) {
                                    Image(featuredDrop.imageAssetName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 88, height: 100)
                                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                }
                            }
                            .padding(16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)

                        // 倒计时组件
                        LaunchCountdownCard(drop: featuredDrop)

                        // 快速感兴趣与通知按钮
                        HStack(spacing: 12) {
                            Button {
                                dropManager.toggleInterested(in: featuredDrop)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: dropManager.isInterested(in: featuredDrop) ? "star.fill" : "star")
                                    Text(appLocalized(dropManager.isInterested(in: featuredDrop) ? "Starred (5m Rush Alert Enabled)" : "Star Drop (Get 5m Rush Alert)"))
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(dropManager.isInterested(in: featuredDrop) ? Color.yellow.opacity(0.18) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(dropManager.isInterested(in: featuredDrop) ? Color.orange : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // 2. 即将发售单品列表
                if !upcomingDrops.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(appLocalized("Upcoming Drops"))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(String(format: appLocalized("%d Drops"), upcomingDrops.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 0) {
                            ForEach(upcomingDrops) { drop in
                                LaunchDropRowCard(drop: drop) {
                                    selectedDropForDetail = drop
                                }
                                .padding(.horizontal, 16)

                                if drop.id != upcomingDrops.last?.id {
                                    Divider().padding(.leading, 80)
                                }
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal)
                    }
                }

                // 3. 近期已开售单品列表 (如已首发的 iPhone Duo)
                if !liveOrRecentDrops.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(appLocalized("Recently Released"), systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(String(format: appLocalized("%d Live"), liveOrRecentDrops.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 0) {
                            ForEach(liveOrRecentDrops) { drop in
                                LaunchDropRowCard(drop: drop) {
                                    selectedDropForDetail = drop
                                }
                                .padding(.horizontal, 16)

                                if drop.id != liveOrRecentDrops.last?.id {
                                    Divider().padding(.leading, 80)
                                }
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal)
                    }
                }

                // 4. 已隐藏单品收纳盒（允许用户一键恢复）
                if !dismissedDrops.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        DisclosureGroup(String(format: appLocalized("Hidden Drops (%d)"), dismissedDrops.count)) {
                            VStack(spacing: 8) {
                                ForEach(dismissedDrops) { drop in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(drop.name)
                                                .font(.subheadline.weight(.medium))
                                            Text(drop.releaseDateFormatted)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button(appLocalized("Unhide")) {
                                            withAnimation(.snappy(duration: 0.25)) {
                                                dropManager.restoreDrop(drop)
                                            }
                                        }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.bordered)
                                    }
                                    .padding(.vertical, 4)
                                    if drop.id != dismissedDrops.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                }

                // 3. 官方预警规则与通知权限卡片
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(Color.orange)
                        Text("Drop Alert Protocol")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if dropManager.notificationPermissionStatus == .authorized {
                            Text("Ready")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        } else {
                            Button("Enable Alerts") {
                                Task {
                                    _ = await dropManager.requestNotificationPermission()
                                }
                            }
                            .font(.caption2.weight(.bold))
                        }
                    }

                    Text("Automatic alerts 1 day and 30 minutes before drop time. Star any item to receive a high-priority rush alert 5 minutes before pre-orders go live, with instant store direct links.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .refreshable {
            await dropManager.syncDropsFromNetwork()
        }
    }

    // MARK: - 原有心愿单主内容 (Classic Wishlist View)
    @ViewBuilder
    private var wishlistContentView: some View {
        VStack(spacing: 0) {
            PinnedSearchField(text: $searchText, prompt: "Search wanted devices, models, or CPUs")

            if displayedProducts.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? String(localized: "Your wishlist is empty") : String(localized: "No devices found"),
                    systemImage: searchText.isEmpty ? "dollarsign.circle" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? String(localized: "Search for a product in Apple Encyclopedia, then tap the Want button in details to add it to your wishlist.") : String(localized: "Try a product name, model number, or processor."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displayedProducts) { product in
                    rowView(for: product)
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isSelecting {
                                Button(role: .destructive) {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        removeProduct(product)
                                    }
                                } label: {
                                    Label(appLocalized("Remove"), systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !isSelecting {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        toggleFavorite(product)
                                    }
                                } label: {
                                    Label(
                                        appLocalized(isFavorite(product) ? "Unfavorite" : "Favorite"),
                                        systemImage: isFavorite(product) ? "heart.slash" : "heart.fill"
                                    )
                                }
                                .tint(.pink)
                            }
                        }
                }
                .listStyle(.plain)
                .dismissKeyboardOnScroll()
            }
        }
    }

    @ViewBuilder
    private func rowView(for product: CatalogDisplayProduct) -> some View {
        if isSelecting {
            Button {
                if selectedProductIDs.contains(product.id) {
                    selectedProductIDs.remove(product.id)
                } else {
                    selectedProductIDs.insert(product.id)
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: selectedProductIDs.contains(product.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedProductIDs.contains(product.id) ? Color.orange : Color.secondary)

                    CatalogDisplayArtwork(product: product)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name).font(.headline).foregroundStyle(.primary)
                        Text([appLocalized(product.isAirPodsSet ? "Left & Right Earbuds with Case" : categoryTitle(product.category)), product.model, product.year]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if !product.processor.isEmpty {
                            Text(product.processor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                DeviceDetailView(
                    device: product.catalogDevice,
                    ownedIDs: ownedIDs,
                    wantedIDs: wantedIDs,
                    favoriteIDs: favoriteIDs,
                    product: product,
                    onAddOwned: onAddOwned,
                    onRemoveOwned: onRemoveOwned
                )
            } label: {
                HStack(spacing: 12) {
                    CatalogDisplayArtwork(product: product)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name).font(.headline)
                        Text([appLocalized(product.isAirPodsSet ? "Left & Right Earbuds with Case" : categoryTitle(product.category)), product.model, product.year]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if !product.processor.isEmpty {
                            Text(product.processor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if isFavorite(product) {
                        Image(systemName: "heart.fill")
                            .font(.subheadline)
                            .foregroundStyle(.pink)
                    }
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .padding(.trailing, 2)
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            if isSelecting {
                HStack {
                    Text(String(format: appLocalized("Selected: %d"), selectedProductIDs.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showingBatchRemoveAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text(String(format: appLocalized("Remove (%d) from Wishlist"), selectedProductIDs.count))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedProductIDs.isEmpty ? Color.secondary : Color.red)
                    }
                    .disabled(selectedProductIDs.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            } else {
                Text("Wishlist · \(wantedCount) products")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10).background(.bar)
            }
        }
    }

    private func isWanted(_ record: SearchCatalogRecord) -> Bool {
        wantedIDs.wrappedValue.contains(record.id) ||
        (!record.legacyCatalogID.isEmpty && wantedIDs.wrappedValue.contains(record.legacyCatalogID))
    }

    private func isWanted(_ product: CatalogDisplayProduct) -> Bool {
        product.records.contains(where: isWanted) || wantedIDs.wrappedValue.contains(product.catalogDevice.id)
    }

    private func removeProduct(_ product: CatalogDisplayProduct) {
        var ids = wantedIDs.wrappedValue
        let linkedIDs = Set(product.records.flatMap { [$0.id, $0.legacyCatalogID] }.filter { !$0.isEmpty } + [product.catalogDevice.id, product.id])
        linkedIDs.forEach { ids.remove($0) }
        wantedIDs.wrappedValue = ids
        CloudVaultSyncManager.shared.recordWantedRemoval(ids: linkedIDs)
    }

    private func removeSelectedProducts() {
        var ids = wantedIDs.wrappedValue
        var allRemovedIDs: Set<String> = []
        for product in products where selectedProductIDs.contains(product.id) {
            let linkedIDs = Set(product.records.flatMap { [$0.id, $0.legacyCatalogID] }.filter { !$0.isEmpty } + [product.catalogDevice.id, product.id])
            linkedIDs.forEach { ids.remove($0) }
            allRemovedIDs.formUnion(linkedIDs)
        }
        wantedIDs.wrappedValue = ids
        CloudVaultSyncManager.shared.recordWantedRemoval(ids: allRemovedIDs)
        selectedProductIDs.removeAll()
        isSelecting = false
    }

    private func isFavorite(_ product: CatalogDisplayProduct) -> Bool {
        favoriteIDs.wrappedValue.contains(product.catalogDevice.id) ||
        product.records.contains { record in
            favoriteIDs.wrappedValue.contains(record.id) ||
            (!record.legacyCatalogID.isEmpty && favoriteIDs.wrappedValue.contains(record.legacyCatalogID))
        }
    }

    private func toggleFavorite(_ product: CatalogDisplayProduct) {
        let currentlyFavorite = isFavorite(product)
        var ids = favoriteIDs.wrappedValue
        let linkedIDs = Set(product.records.flatMap { [$0.id, $0.legacyCatalogID] }.filter { !$0.isEmpty } + [product.catalogDevice.id, product.id])
        if currentlyFavorite {
            linkedIDs.forEach { ids.remove($0) }
            CloudVaultSyncManager.shared.recordFavoriteRemoval(ids: linkedIDs)
        } else {
            ids.insert(product.catalogDevice.id)
            CloudVaultSyncManager.shared.recordFavoriteAddition(id: product.catalogDevice.id)
        }
        favoriteIDs.wrappedValue = ids
    }
}
