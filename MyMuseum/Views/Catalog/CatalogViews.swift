//
//  CatalogViews.swift
//  Pomme
//
//  苹果百科图鉴视图模块 (Catalog / Encyclopedia Views)
//  包含百科主视图 (CatalogView)、产品家族分类 (CatalogGroupPickerView)、
//  搜索列表 (SearchCatalogListView)、设备详情 (DeviceDetailView) 等。
//

import SwiftUI

// MARK: - 百科主页面 (Apple Encyclopedia Catalog View)
struct CatalogView: View {
    let collectionItems: [CollectionItem]
    let onAddOwned: (CollectionItem) -> Void
    let onRemoveOwned: (String) -> Void
    let records = SearchCatalogProductIndex.records
    let products = SearchCatalogProductIndex.products
    @State private var searchText = ""
    @AppStorage("ownedDeviceIDs") private var ownedIDsData = Data()
    @AppStorage("wantedDeviceIDs") private var wantedIDsData = Data()
    @AppStorage("favoriteDeviceIDs") private var favoriteIDsData = Data()

    init(collectionItems: [CollectionItem], onAddOwned: @escaping (CollectionItem) -> Void, onRemoveOwned: @escaping (String) -> Void) {
        self.collectionItems = collectionItems
        self.onAddOwned = onAddOwned
        self.onRemoveOwned = onRemoveOwned
    }

    private var ownedIDs: Binding<Set<String>> {
        Binding(
            get: { decodeIDs(from: ownedIDsData) },
            set: { ownedIDsData = encodeIDs($0) }
        )
    }

    private var wantedIDs: Binding<Set<String>> {
        Binding(
            get: { decodeIDs(from: wantedIDsData) },
            set: { wantedIDsData = encodeIDs($0) }
        )
    }

    private var favoriteIDs: Binding<Set<String>> {
        Binding(
            get: { decodeIDs(from: favoriteIDsData) },
            set: { favoriteIDsData = encodeIDs($0) }
        )
    }

enum CatalogNavigationRoute: Hashable {
    case category(String)
}

    @State private var showingReorderSheet = false
    @State private var catalogNavigationPath: [CatalogNavigationRoute] = []
    @ObservedObject private var rootOrderStore = RootCategoryOrderStore.shared

    // 百科展示完整苹果产品目录，分类数量代表目录中收录的产品数量（使用静态缓存避免重复计算）
    private var defaultCategories: [String] {
        CatalogCategoryIndex.defaultCategories
    }

    private var categories: [String] {
        rootOrderStore.orderedCategories(from: defaultCategories, isEncyclopedia: true)
    }

    private var filteredRecords: [CatalogDisplayProduct] {
        guard !searchText.isEmpty else { return [] }
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        return groupedCatalogProducts(records.filter { record in
            terms.allSatisfy { record.searchText.localizedCaseInsensitiveContains($0) }
        })
    }

    var body: some View {
        NavigationStack(path: $catalogNavigationPath) {
            VStack(spacing: 0) {
                // 搜索框与分类/列表分开布局，滚动时不会消失
                PinnedSearchField(text: $searchText, prompt: "Search by name, model, CPU, or category")
                Group {
                    if searchText.isEmpty {
                        ScrollView {
                            VStack(spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Categories")
                                            .font(.title2.bold())
                                        Text(appLocalized("Browse Apple devices by lineup"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        showingReorderSheet = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.up.arrow.down")
                                            Text(appLocalized("Reorder"))
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal)
                                .padding(.top, 4)

                                MagneticCategoryGridView(
                                    categories: categories,
                                    isEncyclopedia: true,
                                    categoryCount: { CatalogCategoryIndex.productCountByCategory[$0] ?? 0 },
                                    fallbackArtwork: { CatalogCategoryIndex.fallbackArtworkByCategory[$0] },
                                    onSelect: { category in
                                        catalogNavigationPath.append(.category(category))
                                    }
                                )
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                        }
                        .dismissKeyboardOnScroll()
                    } else {
                        SearchCatalogListView(products: filteredRecords, ownedIDs: ownedIDs, wantedIDs: wantedIDs, favoriteIDs: favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Encyclopedia")
            .navigationDestination(for: CatalogNavigationRoute.self) { route in
                switch route {
                case .category(let category):
                    CatalogGroupPickerView(
                        category: category,
                        records: CatalogCategoryIndex.recordsByCategory[category] ?? [],
                        products: CatalogCategoryIndex.productsByCategory[category],
                        ownedIDs: ownedIDs,
                        wantedIDs: wantedIDs,
                        favoriteIDs: favoriteIDs,
                        onAddOwned: onAddOwned,
                        onRemoveOwned: onRemoveOwned
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingReorderSheet = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(appLocalized("Rearrange Categories"))
                }
            }
            .sheet(isPresented: $showingReorderSheet) {
                ReorderCategoriesSheet(isEncyclopedia: true, defaultCategories: defaultCategories)
            }
            .safeAreaInset(edge: .bottom) {
                Text("Full catalog · \(categories.count) categories")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
    }
}

// MARK: - 百科分组中间选择页 (Catalog Group Picker View)

struct CatalogGroupPickerView: View {
    let category: String
    let records: [SearchCatalogRecord]
    private let products: [CatalogDisplayProduct]
    @Binding var ownedIDs: Set<String>
    @Binding var wantedIDs: Set<String>
    @Binding var favoriteIDs: Set<String>
    let onAddOwned: (CollectionItem) -> Void
    let onRemoveOwned: (String) -> Void
    @State private var searchText = ""
    let macBranch: String?

    init(
        category: String,
        records: [SearchCatalogRecord],
        products: [CatalogDisplayProduct]? = nil,
        ownedIDs: Binding<Set<String>>,
        wantedIDs: Binding<Set<String>>,
        favoriteIDs: Binding<Set<String>>,
        onAddOwned: @escaping (CollectionItem) -> Void,
        onRemoveOwned: @escaping (String) -> Void,
        macBranch: String? = nil
    ) {
        self.category = category
        self.records = records
        self.products = products ?? groupedCatalogProducts(records)
        self._ownedIDs = ownedIDs
        self._wantedIDs = wantedIDs
        self._favoriteIDs = favoriteIDs
        self.onAddOwned = onAddOwned
        self.onRemoveOwned = onRemoveOwned
        self.macBranch = macBranch
    }

    private var groups: [CatalogProductGroup] {
        if category == "Mac", macBranch == nil {
            return ["MacBook", "Mac 台式机"].compactMap { branch in
                let branchProducts = products.filter { macProductBranch(for: $0) == branch }
                return branchProducts.isEmpty ? nil : CatalogProductGroup(title: branch, products: branchProducts)
            }
        }
        let filteredProducts = products.filter { product in
            guard let macBranch else { return true }
            return macProductBranch(for: product) == macBranch
        }
        let grouped = Dictionary(grouping: filteredProducts) { catalogFamily($0, root: category) }
        return grouped.map { CatalogProductGroup(title: $0.key, products: $0.value) }
            .sorted { catalogFamilyOrder($0.title, root: category) < catalogFamilyOrder($1.title, root: category) }
    }

    private var filteredRecords: [SearchCatalogRecord] {
        guard !searchText.isEmpty else { return [] }
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        return records.filter { record in terms.allSatisfy { record.searchText.localizedCaseInsensitiveContains($0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedSearchField(text: $searchText, prompt: String(format: appLocalized("Search %@ devices or series"), categoryTitle(category)))
            if !searchText.isEmpty {
                let searchProducts = groupedCatalogProducts(filteredRecords).filter {
                    macBranch == nil || macProductBranch(for: $0) == macBranch
                }
                SearchCatalogListView(products: searchProducts, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
            } else if category == "Vision Pro" || category == "Apple Vision Pro" || (groups.count == 1 && (groups[0].title == categoryTitle(category) || groups[0].title == category || groups[0].title == "Vision Pro" || groups[0].title == "Apple Vision Pro" || groups[0].title == "Headset")) {
                SearchCatalogListView(products: groups.flatMap(\.products), ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
            } else {
                ScrollView {
                    LazyVGrid(columns: appCategoryGridColumns, spacing: 14) {
                        ForEach(groups) { group in
                            if category == "Mac", macBranch == nil {
                                NavigationLink {
                                    CatalogGroupPickerView(category: category, records: records, products: products, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned, macBranch: group.title)
                                } label: {
                                    CategoryCard(
                                        title: group.title,
                                        count: group.products.count,
                                        symbol: group.title == "MacBook" ? "laptopcomputer" : "desktopcomputer",
                                        categoryKey: group.title,
                                        fallbackArtwork: group.products.first?.artworkNames.first
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if (category == "配件" || category == "Accessories"), group.title == "Cases & Storage" {
                                NavigationLink {
                                    CasesGroupPickerView(records: group.products.flatMap(\.records), ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                                } label: {
                                    CategoryCard(
                                        title: group.title,
                                        count: group.products.count,
                                        symbol: categorySymbol(group.title),
                                        categoryKey: group.title,
                                        fallbackArtwork: group.products.first?.artworkNames.first
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if (category == "配件" || category == "Accessories"), group.title == "Power & Charging" {
                                NavigationLink {
                                    PowerGroupPickerView(records: group.products.flatMap(\.records), ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                                } label: {
                                    CategoryCard(
                                        title: group.title,
                                        count: group.products.count,
                                        symbol: categorySymbol(group.title),
                                        categoryKey: group.title,
                                        fallbackArtwork: group.products.first?.artworkNames.first
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if (category == "Home" || category == "家庭"), group.title == "HomePod" {
                                NavigationLink {
                                    HomePodGroupPickerView(records: group.products.flatMap(\.records), ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                                } label: {
                                    CategoryCard(
                                        title: group.title,
                                        count: group.products.count,
                                        symbol: categorySymbol(group.title),
                                        categoryKey: group.title,
                                        fallbackArtwork: group.products.first?.artworkNames.first
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    SearchCatalogListView(products: group.products, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                                } label: {
                                    CategoryCard(
                                        title: group.title,
                                        count: group.products.count,
                                        symbol: categorySymbol(group.title),
                                        categoryKey: group.title,
                                        fallbackArtwork: group.products.first?.artworkNames.first
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
                .dismissKeyboardOnScroll()
            }
        }
        .navigationTitle(appLocalized(macBranch ?? categoryTitle(category)))
        .platformInlineTitleMode()
    }
}

// MARK: - 保护壳与收纳二级分类视图 (Cases Group Picker View)
struct CasesGroupPickerView: View {
    let records: [SearchCatalogRecord]
    private let products: [CatalogDisplayProduct]
    @Binding var ownedIDs: Set<String>
    @Binding var wantedIDs: Set<String>
    @Binding var favoriteIDs: Set<String>
    let onAddOwned: (CollectionItem) -> Void
    let onRemoveOwned: (String) -> Void
    @State private var searchText = ""

    init(
        records: [SearchCatalogRecord],
        ownedIDs: Binding<Set<String>>,
        wantedIDs: Binding<Set<String>>,
        favoriteIDs: Binding<Set<String>>,
        onAddOwned: @escaping (CollectionItem) -> Void,
        onRemoveOwned: @escaping (String) -> Void
    ) {
        self.records = records
        self.products = groupedCatalogProducts(records)
        self._ownedIDs = ownedIDs
        self._wantedIDs = wantedIDs
        self._favoriteIDs = favoriteIDs
        self.onAddOwned = onAddOwned
        self.onRemoveOwned = onRemoveOwned
    }

    private var groups: [CatalogProductGroup] {
        let grouped = Dictionary(grouping: products) { caseSubfamily(name: $0.name, category: $0.category) }
        let order = ["MagSafe Cases", "Battery Cases", "Cases", "Other Cases & Storage"]
        return order.compactMap { title in
            guard let prods = grouped[title], !prods.isEmpty else { return nil }
            return CatalogProductGroup(title: title, products: prods)
        }
    }

    private var filteredRecords: [SearchCatalogRecord] {
        guard !searchText.isEmpty else { return [] }
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        return records.filter { record in terms.allSatisfy { record.searchText.localizedCaseInsensitiveContains($0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedSearchField(text: $searchText, prompt: "Search cases & storage")
            if !searchText.isEmpty {
                SearchCatalogListView(products: groupedCatalogProducts(filteredRecords), ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
            } else {
                ScrollView {
                    LazyVGrid(columns: appCategoryGridColumns, spacing: 14) {
                        ForEach(groups) { group in
                            NavigationLink {
                                SearchCatalogListView(products: group.products, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                                    .navigationTitle(appLocalized(group.title))
                                    .platformInlineTitleMode()
                            } label: {
                                CategoryCard(
                                    title: group.title,
                                    count: group.products.count,
                                    symbol: categorySymbol(group.title),
                                    categoryKey: group.title,
                                    fallbackArtwork: group.products.first?.artworkNames.first
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .dismissKeyboardOnScroll()
            }
        }
        .navigationTitle(appLocalized("Cases & Storage"))
        .platformInlineTitleMode()
    }
}

// MARK: - 电源与充电二级分类视图 (Power Group Picker View)
struct PowerGroupPickerView: View {
    let records: [SearchCatalogRecord]
    private let products: [CatalogDisplayProduct]
    @Binding var ownedIDs: Set<String>
    @Binding var wantedIDs: Set<String>
    @Binding var favoriteIDs: Set<String>
    let onAddOwned: (CollectionItem) -> Void
    let onRemoveOwned: (String) -> Void
    @State private var searchText = ""

    init(
        records: [SearchCatalogRecord],
        ownedIDs: Binding<Set<String>>,
        wantedIDs: Binding<Set<String>>,
        favoriteIDs: Binding<Set<String>>,
        onAddOwned: @escaping (CollectionItem) -> Void,
        onRemoveOwned: @escaping (String) -> Void
    ) {
        self.records = records
        self.products = groupedCatalogProducts(records)
        self._ownedIDs = ownedIDs
        self._wantedIDs = wantedIDs
        self._favoriteIDs = favoriteIDs
        self.onAddOwned = onAddOwned
        self.onRemoveOwned = onRemoveOwned
    }

    private var groups: [CatalogProductGroup] {
        let grouped = Dictionary(grouping: products) { powerSubfamily(name: $0.name, category: $0.category) }
        let order = ["Adapters", "Cables", "MagSafe", "Other"]
        return order.compactMap { title in
            guard let prods = grouped[title], !prods.isEmpty else { return nil }
            return CatalogProductGroup(title: title, products: prods)
        }
    }

    private var filteredRecords: [SearchCatalogRecord] {
        guard !searchText.isEmpty else { return [] }
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        return records.filter { record in terms.allSatisfy { record.searchText.localizedCaseInsensitiveContains($0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedSearchField(text: $searchText, prompt: "Search power & charging")
            if !searchText.isEmpty {
                SearchCatalogListView(products: groupedCatalogProducts(filteredRecords), ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
            } else {
                ScrollView {
                    LazyVGrid(columns: appCategoryGridColumns, spacing: 14) {
                        ForEach(groups) { group in
                            NavigationLink {
                                SearchCatalogListView(products: group.products, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                                    .navigationTitle(appLocalized(group.title))
                                    .platformInlineTitleMode()
                            } label: {
                                CategoryCard(
                                    title: group.title,
                                    count: group.products.count,
                                    symbol: categorySymbol(group.title),
                                    categoryKey: group.title,
                                    fallbackArtwork: group.products.first?.artworkNames.first
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .dismissKeyboardOnScroll()
            }
        }
        .navigationTitle(appLocalized("Power & Charging"))
        .platformInlineTitleMode()
    }
}

// MARK: - HomePod 分组选择视图 (HomePod Group Picker View)
struct HomePodGroupPickerView: View {
    let records: [SearchCatalogRecord]
    private let products: [CatalogDisplayProduct]
    @Binding var ownedIDs: Set<String>
    @Binding var wantedIDs: Set<String>
    @Binding var favoriteIDs: Set<String>
    let onAddOwned: (CollectionItem) -> Void
    let onRemoveOwned: (String) -> Void
    @State private var searchText = ""

    init(
        records: [SearchCatalogRecord],
        ownedIDs: Binding<Set<String>>,
        wantedIDs: Binding<Set<String>>,
        favoriteIDs: Binding<Set<String>>,
        onAddOwned: @escaping (CollectionItem) -> Void,
        onRemoveOwned: @escaping (String) -> Void
    ) {
        self.records = records
        self.products = groupedCatalogProducts(records)
        self._ownedIDs = ownedIDs
        self._wantedIDs = wantedIDs
        self._favoriteIDs = favoriteIDs
        self.onAddOwned = onAddOwned
        self.onRemoveOwned = onRemoveOwned
    }

    private var groups: [CatalogProductGroup] {
        let grouped = Dictionary(grouping: products) { homepodSubfamily(name: $0.name, category: $0.category) }
        let order = ["HomePod Standard", "HomePod mini"]
        return order.compactMap { title in
            guard let prods = grouped[title], !prods.isEmpty else { return nil }
            return CatalogProductGroup(title: title, products: prods)
        }
    }

    private var filteredRecords: [SearchCatalogRecord] {
        guard !searchText.isEmpty else { return [] }
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        return records.filter { record in terms.allSatisfy { record.searchText.localizedCaseInsensitiveContains($0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedSearchField(text: $searchText, prompt: "Search HomePod")
            if !searchText.isEmpty {
                SearchCatalogListView(products: groupedCatalogProducts(filteredRecords), ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
            } else {
                ScrollView {
                    LazyVGrid(columns: appCategoryGridColumns, spacing: 14) {
                        ForEach(groups) { group in
                            NavigationLink {
                                SearchCatalogListView(products: group.products, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                                    .navigationTitle(appLocalized(group.title))
                                    .platformInlineTitleMode()
                            } label: {
                                CategoryCard(
                                    title: group.title,
                                    count: group.products.count,
                                    symbol: categorySymbol(group.title),
                                    categoryKey: group.title,
                                    fallbackArtwork: group.products.first?.artworkNames.first
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .dismissKeyboardOnScroll()
            }
        }
        .navigationTitle(appLocalized("HomePod"))
        .platformInlineTitleMode()
    }
}

// MARK: - 百科搜索与列表展示 (Search Catalog List View)
struct SearchCatalogListView: View {
    let products: [CatalogDisplayProduct]
    @Binding var ownedIDs: Set<String>
    @Binding var wantedIDs: Set<String>
    @Binding var favoriteIDs: Set<String>
    let onAddOwned: (CollectionItem) -> Void
    var onRemoveOwned: ((String) -> Void)? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(products) { product in
                    let device = product.catalogDevice
                    NavigationLink {
                        DeviceDetailView(device: device, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs, product: product, onAddOwned: onAddOwned, onRemoveOwned: onRemoveOwned)
                    } label: {
                        HStack(spacing: 12) {
                            CatalogDisplayArtwork(product: product)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(product.name).font(.headline)
                                    if SpatialMuseumStore.shared.hasModel(for: device.id, name: product.name) {
                                        Image(systemName: "cube.transparent")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text([appLocalized(product.isAirPodsSet ? "Left & Right Earbuds with Case" : categoryTitle(product.category)), product.model, product.year]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            if ownedIDs.contains(device.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if wantedIDs.contains(device.id) {
                                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.orange)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider().padding(.leading, 68)
                }
            }
        }
        .dismissKeyboardOnScroll()
        .overlay {
            if products.isEmpty { ContentUnavailableView.search(text: "") }
        }
    }
}

// MARK: - 旧版或备用简单设备分类与列表视图
struct DeviceCategoryView: View {
    let category: String
    let devices: [Device]
    @Binding var ownedIDs: Set<String>
    @Binding var wantedIDs: Set<String>
    @Binding var favoriteIDs: Set<String>
    @State private var searchText = ""

    private var filteredDevices: [Device] {
        guard !searchText.isEmpty else { return devices }
        return devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.model.localizedCaseInsensitiveContains(searchText) ||
            $0.year.localizedCaseInsensitiveContains(searchText) ||
            $0.color.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedSearchField(text: $searchText, prompt: String(format: appLocalized("Search in %@"), categoryTitle(category)))
            DeviceListView(devices: filteredDevices, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs)
        }
        .navigationTitle(categoryTitle(category))
        .platformInlineTitleMode()
    }
}

struct DeviceListView: View {
    let devices: [Device]
    @Binding var ownedIDs: Set<String>
    @Binding var wantedIDs: Set<String>
    @Binding var favoriteIDs: Set<String>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(devices, id: \.id) { device in
                    NavigationLink {
                        DeviceDetailView(device: device, ownedIDs: $ownedIDs, wantedIDs: $wantedIDs, favoriteIDs: $favoriteIDs)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name)
                                Text([device.model, device.year].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if ownedIDs.contains(device.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if wantedIDs.contains(device.id) {
                                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.orange)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider().padding(.leading, 16)
                }
            }
        }
        .dismissKeyboardOnScroll()
        .overlay {
            if devices.isEmpty {
                ContentUnavailableView.search(text: "")
            }
        }
    }
}

// MARK: - 图鉴单品详情视图 (Device Detail View)
struct DeviceDetailView: View {
    let device: Device
    @Binding var ownedIDs: Set<String>    // 连着列表页的已有集合
    @Binding var wantedIDs: Set<String>   // 连着列表页的想要集合
    @Binding var favoriteIDs: Set<String> // 连着列表页的喜欢集合
    let product: CatalogDisplayProduct?
    let onAddOwned: ((CollectionItem) -> Void)?
    let onRemoveOwned: ((String) -> Void)?
    @State private var isAddingOwned = false
    @State private var showingShareSheet = false
    @State private var showingSpatialGallery = false
    @State private var selectedColor: String? = nil
    @State private var coverToastMessage: String? = nil
    
    @AppStorage("wantedDeviceIDs") private var wantedIDsData = Data()
    @AppStorage("favoriteDeviceIDs") private var favoriteIDsData = Data()
    @State private var isWantedLocal: Bool? = nil
    @State private var isFavoriteLocal: Bool? = nil

    init(
        device: Device,
        ownedIDs: Binding<Set<String>>,
        wantedIDs: Binding<Set<String>>,
        favoriteIDs: Binding<Set<String>>,
        product: CatalogDisplayProduct? = nil,
        onAddOwned: ((CollectionItem) -> Void)? = nil,
        onRemoveOwned: ((String) -> Void)? = nil
    ) {
        self.device = device
        self._ownedIDs = ownedIDs
        self._wantedIDs = wantedIDs
        self._favoriteIDs = favoriteIDs
        self.product = product
        self.onAddOwned = onAddOwned
        self.onRemoveOwned = onRemoveOwned
        self._selectedColor = State(initialValue: device.color.isEmpty ? nil : device.color)
    }

    var body: some View {
        let currentColor = selectedColor ?? (device.color.isEmpty ? nil : device.color)
        let currentDevice = Device(
            id: device.id,
            name: device.name,
            model: device.model,
            category: device.category,
            year: device.year,
            color: currentColor ?? ""
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DeviceArtwork(device: currentDevice, product: product ?? CatalogImportMatcher.productsByID[device.id], compact: false)
                VStack(alignment: .leading, spacing: 8) {
                    Text(device.name).font(.largeTitle.bold())
                    Label(categoryTitle(device.category), systemImage: categorySymbol(device.category))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statusActionButton(
                        ownedButtonTitle,
                        symbol: "checkmark.circle.fill",
                        inactiveSymbol: "circle",
                        isActive: isOwnedActive,
                        tint: .green
                    ) {
                        isAddingOwned = true
                    }
                    
                    statusActionButton(
                        appLocalized("Want"),
                        symbol: "dollarsign.circle.fill",
                        inactiveSymbol: "dollarsign.circle",
                        isActive: isWantedActive,
                        tint: .orange
                    ) {
                        toggleWantedDevice()
                    }
                    
                    statusActionButton(
                        appLocalized("Favorite"),
                        symbol: "heart.fill",
                        inactiveSymbol: "heart",
                        isActive: isFavoriteActive,
                        tint: .pink
                    ) {
                        toggleFavoriteDevice()
                    }
                }

                if let spatialModel = SpatialMuseumStore.shared.model(for: device.id, name: device.name, color: currentColor) {
                    Button {
                        #if os(visionOS)
                        SpatialMuseumStore.shared.spawn(model: spatialModel)
                        #endif
                        showingSpatialGallery = true
                    } label: {
                        HStack(spacing: 12) {
                            #if os(visionOS)
                            Image(systemName: "visionpro")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                            #elseif os(iOS)
                            Image(systemName: "arkit")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                            #else
                            Image(systemName: "cube.transparent")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                            #endif
                            VStack(alignment: .leading, spacing: 2) {
                                #if os(visionOS)
                                Text(appLocalized("View in Space"))
                                    .font(.headline)
                                #elseif os(iOS)
                                Text("View in 3D & AR")
                                    .font(.headline)
                                #else
                                Text("View in 3D")
                                    .font(.headline)
                                #endif
                                Text("1:1 Scale\(spatialModel.colorLabel != nil ? " · " + (spatialModel.colorLabel!) : "")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showingSpatialGallery) {
                        #if os(visionOS)
                        NavigationStack {
                            SpatialMuseumView()
                        }
                        #else
                        Device3DInspectorSheet(item: spatialModel)
                        #endif
                    }
                }

                if let colors = deviceColors(for: device.id) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Device Color").font(.headline)
                        DeviceColorSelector(colors: colors, selection: currentColor) { color in
                            selectedColor = color
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Product Profile", systemImage: "info.circle")
                        .font(.headline)
                    VStack(spacing: 0) {
                        infoRow("Model Number", device.model.isEmpty ? String(localized: "Not recorded") : device.model)
                        Divider()
                        infoRow("Release Year", device.year.isEmpty ? String(localized: "Not recorded") : device.year)
                        Divider()
                        infoRow("Color", (currentColor ?? device.color).isEmpty ? String(localized: "Not recorded") : deviceColorLabel(currentColor ?? device.color))
                    }
                    .padding(.horizontal, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }

                if let product {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Product Specs", systemImage: "cpu")
                            .font(.headline)
                        VStack(spacing: 0) {
                            infoRow("CPU", product.processor.isEmpty ? String(localized: "Not recorded") : product.processor)
                            Divider()
                            infoRow("Product Identifier", product.identifiers.isEmpty ? String(localized: "Not recorded") : product.identifiers)
                        }
                        .padding(.horizontal, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }

            }
            .padding(20)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(device.name)
        .platformInlineTitleMode()
        .platformHideTabBar()
        .toolbar {
            ToolbarItemGroup(placement: .appTopBarTrailing) {
                ShareLink(item: deviceShareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(appLocalized("Share Device"))

                Button {
                    isAddingOwned = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel(appLocalized("Add to Collection"))
                .help(isChineseLanguage ? "登记入库 / 添加一件到藏品" : "Add to Collection")

                Menu {
                    let currentColor = selectedColor ?? (device.color.isEmpty ? nil : device.color)
                    let targetArtwork: String = {
                        if let currentColor, !currentColor.isEmpty {
                            let colorArt = deviceArtworkAssetName(device.id, color: currentColor)
                            if imageAssetExists(colorArt) && (colorArt.contains("_color_") || colorArt != deviceArtworkAssetName(device.id, color: nil)) {
                                return colorArt
                            }
                        }
                        return product?.artworkNames.first(where: { imageAssetExists($0) })
                            ?? product?.artworkNames.first
                            ?? deviceArtworkAssetName(device.id, color: currentColor)
                    }()
                    let tiers = categoryHierarchyTiers(name: device.name, category: device.category, product: product)
                    CategoryCoverMenuContent(artworkAssetName: targetArtwork, tiers: tiers) { updatedTitle in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            coverToastMessage = String(format: appLocalized("Cover updated for %@"), updatedTitle)
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            withAnimation { coverToastMessage = nil }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(appLocalized("More Actions"))
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(activityItems: [deviceShareText])
        }
        .overlay(alignment: .top) {
            if let msg = coverToastMessage {
                Text(msg)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.85), in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $isAddingOwned) {
            if let targetProduct = effectiveProduct {
                NavigationStack {
                    AddCollectionDetailsView(product: targetProduct, initialColor: selectedColor) { newItem in
                        var itemToSave = newItem
                        if (itemToSave.color?.isEmpty ?? true), let sel = selectedColor, !sel.isEmpty {
                            itemToSave.color = sel
                        }
                        if let onAddOwned {
                            onAddOwned(itemToSave)
                        } else {
                            var current = loadCollection()
                            current.insert(itemToSave, at: 0)
                            saveCollection(current)
                        }
                        ownedIDs.insert(targetProduct.catalogDevice.id)
                        ownedIDs.insert(device.id)
                        refreshOwnedCount()
                    }
                }
            }
        }
        .dismissKeyboardOnScroll()
        .onAppear { refreshOwnedCount() }
    }

    private var effectiveProduct: CatalogDisplayProduct? {
        if let product { return product }
        if let matched = CatalogImportMatcher.productsByID[device.id] { return matched }
        if let found = SearchCatalogProductIndex.products.first(where: { $0.id == device.id || $0.catalogDevice.id == device.id }) {
            return found
        }
        return CatalogDisplayProduct(
            id: device.id,
            name: device.name,
            category: device.category,
            model: device.model,
            year: device.year,
            records: [],
            artworkNames: [deviceArtworkAssetName(device.id, color: device.color)]
        )
    }

    @State private var ownedCount: Int = 0

    private func refreshOwnedCount() {
        let items = loadCollection()
        let targetID = device.id
        let linkedIDs: Set<String>
        if let eff = effectiveProduct {
            linkedIDs = Set(eff.records.flatMap { [$0.id, $0.legacyCatalogID] }.filter { !$0.isEmpty } + [eff.catalogDevice.id, eff.id, targetID])
        } else {
            linkedIDs = [targetID]
        }
        ownedCount = items.filter { item in
            if let catID = item.catalogID, linkedIDs.contains(catID) { return true }
            return linkedIDs.contains(item.id)
        }.count
    }

    private var isOwnedActive: Bool {
        ownedIDs.contains(device.id) || ownedCount > 0
    }

    private var ownedButtonTitle: String {
        if ownedCount > 1 {
            return "\(appLocalized("Owned")) (\(ownedCount))"
        }
        return appLocalized("Owned")
    }

    private var allDeviceKeys: Set<String> {
        var keys: Set<String> = [device.id]
        if let eff = effectiveProduct {
            keys.insert(eff.id)
            keys.insert(eff.catalogDevice.id)
            for r in eff.records {
                if !r.id.isEmpty { keys.insert(r.id) }
                if !r.legacyCatalogID.isEmpty { keys.insert(r.legacyCatalogID) }
            }
        }
        return keys
    }

    private var isWantedActive: Bool {
        if let isWantedLocal { return isWantedLocal }
        let keys = allDeviceKeys
        let currentWanted = decodeIDs(from: wantedIDsData).union(wantedIDs)
        return keys.contains(where: currentWanted.contains)
    }

    private func toggleWantedDevice() {
        let keys = allDeviceKeys
        var ids = decodeIDs(from: wantedIDsData).union(wantedIDs)
        let currentlyActive = isWantedActive
        let nextState = !currentlyActive
        isWantedLocal = nextState

        if currentlyActive {
            for k in keys {
                ids.remove(k)
            }
            CloudVaultSyncManager.shared.recordWantedRemoval(ids: keys)
        } else {
            ids.insert(device.id)
            CloudVaultSyncManager.shared.recordWantedAddition(id: device.id)
        }
        wantedIDs = ids
        wantedIDsData = encodeIDs(ids)
    }

    private var isFavoriteActive: Bool {
        if let isFavoriteLocal { return isFavoriteLocal }
        let keys = allDeviceKeys
        let currentFav = decodeIDs(from: favoriteIDsData).union(favoriteIDs)
        if keys.contains(where: currentFav.contains) { return true }
        let items = loadCollection()
        return items.contains { item in
            let matches = (item.catalogID != nil && keys.contains(item.catalogID!)) || keys.contains(item.id)
            return matches && currentFav.contains(item.id)
        }
    }

    private func toggleFavoriteDevice() {
        let keys = allDeviceKeys
        var ids = decodeIDs(from: favoriteIDsData).union(favoriteIDs)
        let items = loadCollection()
        let matchingItemIDs = items.compactMap { item -> String? in
            let matches = (item.catalogID != nil && keys.contains(item.catalogID!)) || keys.contains(item.id)
            return matches ? item.id : nil
        }
        let allPossibleIDs = keys.union(matchingItemIDs)
        let currentlyActive = isFavoriteActive
        let nextState = !currentlyActive
        isFavoriteLocal = nextState

        if currentlyActive {
            for k in allPossibleIDs {
                ids.remove(k)
            }
            CloudVaultSyncManager.shared.recordFavoriteRemoval(ids: allPossibleIDs)
        } else {
            let targetID: String
            if let firstItem = items.first(where: { item in
                (item.catalogID != nil && keys.contains(item.catalogID!)) || keys.contains(item.id)
            }) {
                targetID = firstItem.id
            } else {
                targetID = device.id
            }
            ids.insert(targetID)
            CloudVaultSyncManager.shared.recordFavoriteAddition(id: targetID)
        }
        favoriteIDs = ids
        favoriteIDsData = encodeIDs(ids)
    }

    private var deviceShareText: String {
        [
            device.name,
            "\(appLocalized("Model Number")): \(device.model)",
            "\(appLocalized("Release Year")): \(device.year)",
            product.flatMap { $0.processor.isEmpty ? nil : "\(appLocalized("CPU")): \($0.processor)" },
            product.flatMap { $0.identifiers.isEmpty ? nil : "\(appLocalized("Product Identifier")): \($0.identifiers)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func statusActionButton(
        _ title: String,
        symbol: String,
        inactiveSymbol: String,
        isActive: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                action()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isActive ? symbol : inactiveSymbol)
                    .font(.system(size: 15, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? tint : .secondary)
                
                Text(title)
                    .font(.system(size: 13.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? (tint == .green ? Color.primary : tint) : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? tint.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isActive ? tint.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: isActive ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }


    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 16) {
            Text(appLocalized(title)).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            Text(value == "Not recorded" ? appLocalized(value) : value).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .padding(.vertical, 11)
    }
}
