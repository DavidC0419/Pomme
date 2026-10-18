//
//  MacCuratorWorkbenchView.swift
//  Pomme
//
//  Mac 策展人工作台 (Curator Workbench)
//  专为 macOS 桌面与宽屏打造的三栏式全能建档与资产管理工作台：
//  边栏分类 → 中间网格/表格 → 右侧实时检查器，具备批量编辑、数据健康体检、全键盘流与 PDF 导出能力。
//

import SwiftUI
import UniformTypeIdentifiers

struct MacCuratorWorkbenchView: View {
    @Binding var collectionItems: [CollectionItem]
    @Binding var ownedIDsData: Data
    @Binding var wantedIDsData: Data
    @Binding var favoriteIDsData: Data
    let onUpdate: (CollectionItem) -> Void
    let onBatchUpdate: ([CollectionItem]) -> Void
    let onDelete: (String) -> Void
    
    @State private var sidebarSelection: MacSidebarSelection? = .all
    @State private var selectedItemID: String? = nil
    @State private var selectedItemIDs: Set<String> = []
    @State private var isMultiSelectMode: Bool = false
    
    @State private var searchText: String = ""
    @State private var viewMode: MacViewMode = .grid
    @State private var sortOption: MacSortOption = .category
    @State private var activeHealthFilter: DataHealthFilter? = nil
    @State private var batteryStatusFilter: MacBatteryStatusFilter = .all
    @State private var selectedBatteryCategory: String? = nil
    
    // 多级硬件小标签与层级导航状态 (Hierarchical Category Navigation)
    @State private var categoryNavRoot: String? = nil
    @State private var categoryNavBranch: String? = nil
    @State private var categoryNavFamily: String? = nil
    @State private var categoryNavShowAll: Bool = true
    
    @State private var showingAddDevice = false
    @State private var showingEditSheet = false
    @State private var showingBatchChargeSheet = false
    @State private var isInspectorPresented = true
    @State private var showingCloudSync = false
    @State private var showingSpacebarPreview = false
    @State private var previewItem: CollectionItem? = nil
    @State private var itemToEdit: CollectionItem? = nil
    
    // PDF 导出状态
    @State private var isExportingPDF = false
    @State private var pdfExportData: Data? = nil
    @State private var showingPDFExportSuccess = false
    
    // CSV 导入导出
    @State private var importingCSV = false
    @State private var exportingCSV = false
    @State private var csvDocument = MuseumCSVDocument(data: Data())
    @State private var showingClearSampleAlert = false
    
    @FocusState private var isSearchFocused: Bool
    @AppStorage("museumTitle") private var museumTitle = ""
    @ObservedObject private var syncManager = CloudVaultSyncManager.shared
    
    private var favoriteIDs: Binding<Set<String>> {
        Binding(
            get: { decodeIDs(from: favoriteIDsData) },
            set: { favoriteIDsData = encodeIDs($0) }
        )
    }
    
    private var ownedIDs: Binding<Set<String>> {
        Binding(get: { decodeIDs(from: ownedIDsData) }, set: { ownedIDsData = encodeIDs($0) })
    }
    
    private var wantedIDs: Binding<Set<String>> {
        Binding(get: { decodeIDs(from: wantedIDsData) }, set: { wantedIDsData = encodeIDs($0) })
    }
    
    // MARK: - 过滤与排序后的数据
    private var filteredItems: [CollectionItem] {
        var baseList = collectionItems
        
        // 1. 侧边栏与多级硬件小分类过滤 (Hierarchical Subcategory Filter)
        switch sidebarSelection {
        case .all, .none, .category:
            if let root = categoryNavRoot {
                baseList = baseList.filter {
                    MacCategoryHierarchyHelper.matches(
                        item: $0,
                        rootCategory: root,
                        branch: categoryNavBranch,
                        family: categoryNavShowAll ? nil : categoryNavFamily
                    )
                }
            }
        case .inUse:
            baseList = baseList.filter { $0.isDailyDriver }
        case .battery:
            baseList = baseList.filter {
                (BatteryMaintenanceManager.deviceHasRechargeableBattery($0) || BatteryMaintenanceManager.isAirTag($0)) && !$0.batteryTrackingIgnored
            }
            if let cat = selectedBatteryCategory {
                baseList = baseList.filter { itemRootCategory($0) == cat }
            }
            switch batteryStatusFilter {
            case .all:
                break
            case .overdue:
                baseList = baseList.filter {
                    !BatteryMaintenanceManager.isAirTagInsulated($0) &&
                    BatteryMaintenanceManager.evaluateMaintenance(for: $0)?.status == .overdue
                }
            case .dueSoon:
                baseList = baseList.filter {
                    !BatteryMaintenanceManager.isAirTagInsulated($0) &&
                    BatteryMaintenanceManager.evaluateMaintenance(for: $0)?.status == .dueSoon
                }
            case .healthy:
                baseList = baseList.filter {
                    !BatteryMaintenanceManager.isAirTagInsulated($0) &&
                    (BatteryMaintenanceManager.evaluateMaintenance(for: $0)?.status == .healthy || ($0.isDailyDriver && !BatteryMaintenanceManager.isAirTag($0)))
                }
            case .untracked:
                baseList = baseList.filter {
                    !BatteryMaintenanceManager.isAirTagInsulated($0) &&
                    (BatteryMaintenanceManager.evaluateMaintenance(for: $0)?.status == .untracked ||
                     (BatteryMaintenanceManager.deviceHasRechargeableBattery($0) && $0.lastCharged == nil && !$0.isDailyDriver))
                }
            case .unactivatedAirTags:
                baseList = baseList.filter {
                    BatteryMaintenanceManager.isAirTag($0) && BatteryMaintenanceManager.isAirTagInsulated($0)
                }
            }
        case .favorites:
            let favs = favoriteIDs.wrappedValue
            baseList = baseList.filter { favs.contains($0.favoriteKey) }
        case .dataHealth:
            // 数据健康面板自定义过滤
            if let filter = activeHealthFilter {
                baseList = MacWorkbenchSortHelpers.applyHealthFilter(filter, on: baseList)
            }
        case .encyclopedia, .wishlist, .rumors, .spatialMuseum:
            return []
        }
        
        // 2. 关键词搜索过滤 (支持名称/机型/序列号/处理器/备注)
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            baseList = baseList.filter { item in
                let combined = "\(item.displayName) \(item.name) \(item.model ?? "") \(item.serialNumber ?? "") \(item.processor ?? "") \(item.notes ?? "") \(item.color ?? "") \(itemRootCategory(item))".lowercased()
                return combined.contains(q)
            }
        }
        
        // 3. 排序
        return MacWorkbenchSortHelpers.sortItems(baseList, by: sortOption)
    }
    
    // MARK: - 按小分类聚合的数据结构 (Grouped Sections for Display)
    private var displayGroups: [MacCollectionSectionGroup] {
        MacCategoryHierarchyHelper.groupItems(
            items: filteredItems,
            rootCategory: categoryNavRoot,
            branch: categoryNavBranch,
            family: categoryNavShowAll ? nil : categoryNavFamily
        )
    }
    
    private var currentSelectedItem: CollectionItem? {
        if let id = selectedItemID {
            return collectionItems.first(where: { $0.id == id })
        }
        return filteredItems.first
    }
    
    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            HStack(spacing: 0) {
                contentMiddleView
                
                if isInspectorPresented {
                    Divider()
                    detailInspectorView
                        .frame(minWidth: 320, idealWidth: 350, maxWidth: 400)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, minHeight: 560)
        .toolbar {
            workbenchToolbar
        }
        .sheet(isPresented: $showingAddDevice) {
            AddDeviceCatalogView(onAdd: onUpdate)
                .frame(minWidth: 500, minHeight: 480)
        }
        .sheet(isPresented: $showingCloudSync) {
            CloudSyncSettingsSheet()
                .frame(minWidth: 420, minHeight: 380)
        }
        .sheet(isPresented: $showingBatchChargeSheet) {
            let queue = collectionItems.filter {
                BatteryMaintenanceManager.deviceHasRechargeableBattery($0) && !$0.batteryTrackingIgnored && !BatteryMaintenanceManager.isAirTagInsulated($0)
            }
            BatchChargeLogSheet(
                items: queue,
                onBatchLog: { selectedItems, date, level, rawBatt in
                    BatteryMaintenanceManager.batchLogCharge(
                        for: selectedItems,
                        date: date,
                        remainingLevel: level,
                        batteryLevel: rawBatt,
                        onBatchUpdate: onBatchUpdate,
                        onUpdate: onUpdate
                    )
                }
            )
            .frame(minWidth: 540, minHeight: 480)
        }
        .sheet(isPresented: $showingSpacebarPreview) {
            if let preview = previewItem ?? currentSelectedItem {
                spacebarQuickLookSheet(preview)
            }
        }
        .fileExporter(
            isPresented: $exportingCSV,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Pomme-Collection-Export"
        ) { _ in }
        .fileImporter(
            isPresented: $importingCSV,
            allowedContentTypes: [.commaSeparatedText, .text, .plainText]
        ) { result in
            handleCSVImport(result)
        }
        .alert(isChineseLanguage ? "清空演示示例数据" : "Clear Sample Devices", isPresented: $showingClearSampleAlert) {
            Button(isChineseLanguage ? "取消" : "Cancel", role: .cancel) { }
            Button(isChineseLanguage ? "确认清空" : "Clear", role: .destructive) {
                NotificationCenter.default.post(name: .clearSampleDevices, object: nil)
            }
        } message: {
            Text(isChineseLanguage ? "确定要清空全部 6 件功能演示示例设备吗？清空后将恢复空白博物馆，您可以开始自由录入自己的真实设备。" : "Are you sure you want to remove all 6 sample demonstration devices? You can start adding your own hardware.")
        }
        .onAppear {
            if selectedItemID == nil, let first = collectionItems.first {
                selectedItemID = first.id
            }
        }
        .onChange(of: sidebarSelection) { _, newSel in
            switch newSel {
            case .all, .none:
                categoryNavRoot = nil
                categoryNavBranch = nil
                categoryNavFamily = nil
                categoryNavShowAll = true
            case .category(let cat):
                categoryNavRoot = cat
                categoryNavBranch = nil
                categoryNavFamily = nil
                categoryNavShowAll = true
            default:
                break
            }
        }
    }
    
    // MARK: - 1. 左侧边栏 (Sidebar)
    private var sidebarView: some View {
        MacWorkbenchSidebarView(
            sidebarSelection: $sidebarSelection,
            collectionItems: collectionItems,
            favoriteIDs: favoriteIDs.wrappedValue,
            museumTitle: museumTitle
        )
    }
    
    // MARK: - 2. 中间内容区 (Content Column)
    private var contentMiddleView: some View {
        Group {
            switch sidebarSelection {
            case .encyclopedia:
                CatalogView(collectionItems: collectionItems, onAddOwned: onUpdate, onRemoveOwned: { _ in })
            case .wishlist:
                WishlistView(onAddOwned: onUpdate, onRemoveOwned: { _ in })
            case .rumors:
                RumorView()
            case .spatialMuseum:
                #if DEBUG
                SpatialMuseumView(isActive: true)
                #else
                collectionBrowserView
                #endif
            default:
                collectionBrowserView
            }
        }
        .navigationTitle(middleColumnTitle)
    }
    
    private var collectionBrowserView: some View {
        VStack(spacing: 0) {
            // 顶部搜索与过滤工具条
            HStack(spacing: 12) {
                // Spotlight 风格胶囊搜索框 (支持 ⌘K)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(isChineseLanguage ? "搜索藏品、型号、SN码、芯片、成色 (⌘K)..." : "Search items, SN, specs (⌘K)...", text: $searchText)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("⌘K")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.07), lineWidth: 0.8))
                
                // 多选模式切换
                Button {
                    isMultiSelectMode.toggle()
                    if !isMultiSelectMode {
                        selectedItemIDs.removeAll()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                        Text(isChineseLanguage ? "多选" : "Select")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isMultiSelectMode ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05), in: Capsule())
                    .foregroundStyle(isMultiSelectMode ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                
                if isMultiSelectMode {
                    Button(isChineseLanguage ? "全选 (⌘A)" : "All (⌘A)") {
                        selectedItemIDs = Set(filteredItems.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
                
                // 排序菜单
                Menu {
                    Picker(selection: $sortOption, label: Text("Sort")) {
                        ForEach(MacSortOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                        Text(sortOption.title)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // 视图模式切换 (Grid vs Table)
                Picker("", selection: $viewMode) {
                    ForEach(MacViewMode.allCases) { m in
                        Image(systemName: m.icon).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 72)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(macWindowBackground)
            
            Divider()
            
            // 顶部硬件品类快捷胶囊栏 或 电池巡检双层快速检索控制栏
            if sidebarSelection == .battery {
                MacWorkbenchBatterySectionView(
                    collectionItems: collectionItems,
                    selectedBatteryCategory: $selectedBatteryCategory,
                    batteryStatusFilter: $batteryStatusFilter,
                    onBatchCharge: { showingBatchChargeSheet = true }
                )
            } else {
                MacWorkbenchTopCategoryBar(
                    sidebarSelection: $sidebarSelection,
                    categoryNavRoot: $categoryNavRoot,
                    categoryNavBranch: $categoryNavBranch,
                    categoryNavFamily: $categoryNavFamily,
                    categoryNavShowAll: $categoryNavShowAll,
                    collectionItems: collectionItems
                )
            }
            
            Divider()
            
            if SampleDataManager.hasSampleItems(in: collectionItems) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                        .font(.system(size: 13, weight: .semibold))
                    Text(isChineseLanguage ? "当前为功能演示示例数据 (共 6 件) · 体验完毕后可随时一键清空" : "Viewing Sample Data (6 items) · Clear anytime to start your museum")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showingClearSampleAlert = true
                    } label: {
                        Text(isChineseLanguage ? "快速清空示例数据" : "Clear Sample Data")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.12), in: Capsule())
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.08))
                Divider()
            }
            
            // 列表或网格展示 (按小分类聚合或单叶子平铺)
            ZStack {
                macCanvasColor
                
                if filteredItems.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: collectionItems.isEmpty ? "sparkles.rectangle.stack" : "shippingbox")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(collectionItems.isEmpty ? (isChineseLanguage ? "博物馆暂无藏品" : "Museum is Empty") : (isChineseLanguage ? "暂无匹配藏品" : "No Matching Items"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(collectionItems.isEmpty ? (isChineseLanguage ? "可一键载入功能演示示例数据，快速体验全部功能" : "Load sample demonstration devices to explore all features.") : (isChineseLanguage ? "尝试调整搜索词，或从左侧边栏切换其他品类" : "Try searching differently or change sidebar category."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if collectionItems.isEmpty {
                            Button {
                                NotificationCenter.default.post(name: .loadSampleDevices, object: nil)
                            } label: {
                                Label(isChineseLanguage ? "载入功能演示数据" : "Load Sample Devices", systemImage: "sparkles")
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MacCuratorGroupedGridView(
                        groups: displayGroups,
                        viewMode: viewMode,
                        isMultiSelectMode: isMultiSelectMode,
                        selectedItemID: $selectedItemID,
                        selectedItemIDs: $selectedItemIDs,
                        favoriteIDs: favoriteIDs,
                        isBatteryMode: sidebarSelection == .battery,
                        onSelect: { item in
                            if isMultiSelectMode {
                                if selectedItemIDs.contains(item.id) {
                                    selectedItemIDs.remove(item.id)
                                } else {
                                    selectedItemIDs.insert(item.id)
                                }
                            } else {
                                selectedItemID = item.id
                            }
                        },
                        onToggleFavorite: { item in
                            var favs = favoriteIDs.wrappedValue
                            if favs.contains(item.favoriteKey) {
                                favs.remove(item.favoriteKey)
                            } else {
                                favs.insert(item.favoriteKey)
                            }
                            favoriteIDs.wrappedValue = favs
                        },
                        onToggleDailyDriver: { item in
                            var m = item
                            m.isDailyDriver.toggle()
                            onUpdate(m)
                        },
                        onLogCharge: { item in
                            BatteryMaintenanceManager.logCharge(for: item, date: Date(), remainingLevel: .from80to100) { updated in
                                onUpdate(updated)
                            }
                        },
                        onQuickLook: { item in
                            previewItem = item
                            showingSpacebarPreview = true
                        },
                        onUpdate: onUpdate
                    )
                }
            }
            
            Divider()
            
            // 底部状态栏
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(isChineseLanguage ? "共 \(filteredItems.count) 件藏品" : "\(filteredItems.count) items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    if !selectedItemIDs.isEmpty {
                        Text(isChineseLanguage ? "· 已选 \(selectedItemIDs.count) 件" : "· \(selectedItemIDs.count) selected")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    statusKeyboardPill(label: isChineseLanguage ? "方向键 导航" : "↑↓ Navigate")
                    statusKeyboardPill(label: isChineseLanguage ? "空格 预览" : "Space Preview")
                    statusKeyboardPill(label: isChineseLanguage ? "⌘K 搜索" : "⌘K Search")
                    statusKeyboardPill(label: isChineseLanguage ? "⌘A 全选" : "⌘A All")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))
        }
        // 键盘监听 (禁用系统高亮蓝框，避免分界线出现不和谐蓝线)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            if let target = currentSelectedItem {
                previewItem = target
                showingSpacebarPreview = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(KeyEquivalent("k"), phases: .down) { press in
            if press.modifiers.contains(.command) {
                isSearchFocused = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(KeyEquivalent("a"), phases: .down) { press in
            if press.modifiers.contains(.command) {
                isMultiSelectMode = true
                selectedItemIDs = Set(filteredItems.map(\.id))
                return .handled
            }
            return .ignored
        }
    }
    
    private func statusKeyboardPill(label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Color.primary.opacity(0.04), in: Capsule())
    }
    
    // MARK: - 3. 右侧检查器 (Inspector Column)
    private var detailInspectorView: some View {
        MacCuratorDetailInspectorView(
            sidebarSelection: sidebarSelection,
            collectionItems: collectionItems,
            activeHealthFilter: $activeHealthFilter,
            isMultiSelectMode: isMultiSelectMode,
            selectedItemIDs: $selectedItemIDs,
            currentSelectedItem: currentSelectedItem,
            favoriteIDs: favoriteIDs,
            onBatchUpdate: onBatchUpdate,
            onUpdate: onUpdate,
            onDelete: onDelete,
            onQuickLook: { item in
                previewItem = item
                showingSpacebarPreview = true
            }
        )
    }
    
    // MARK: - 空格键 QuickLook 预览大窗
    private func spacebarQuickLookSheet(_ item: CollectionItem) -> some View {
        MacWorkbenchQuickLookView(item: item, onClose: { showingSpacebarPreview = false })
    }
    
    // MARK: - 4. 顶部工作台 Toolbar
    @ToolbarContentBuilder
    private var workbenchToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // 切换右侧详情面板显示/隐藏 (macOS 原生 Inspector 平滑收展)
            Button {
                isInspectorPresented.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .foregroundStyle(isInspectorPresented ? Color.accentColor : Color.secondary)
            }
            .help(isChineseLanguage ? (isInspectorPresented ? "隐藏右侧详情面板" : "显示右侧详情面板") : (isInspectorPresented ? "Hide Inspector" : "Show Inspector"))
            
            // 添加新设备 (仅在藏品策展视图下展示，在百科/心愿单等详情页不展示)
            if isCollectionSection {
                Button {
                    showingAddDevice = true
                } label: {
                    Label(isChineseLanguage ? "添加藏品" : "Add Device", systemImage: "plus")
                }
                .help(isChineseLanguage ? "新增一件设备到藏品馆" : "Add a device to collection")
            }
            
            // 导出策展人 PDF 画册 (仅在藏品视图下展示)
            if isCollectionSection {
                Button {
                    exportPDFCatalog()
                } label: {
                    Label(isChineseLanguage ? "导出画册 PDF" : "Export PDF Catalog", systemImage: "arrow.down.doc.fill")
                }
                .help(isChineseLanguage ? "生成带图、带价、带序列号的完整藏品保全画册 PDF" : "Export high-res PDF collection catalog with specs and valuation")
            }
            
            // CSV 导入与导出 (支持导入自定义清单、导出备份与模板下载)
            if isCollectionSection {
                Menu {
                    Button {
                        importingCSV = true
                    } label: {
                        Label(isChineseLanguage ? "导入 CSV 藏品清单..." : "Import Collection CSV...", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        let data = MuseumCSV.export(collectionItems)
                        csvDocument = MuseumCSVDocument(data: data)
                        exportingCSV = true
                    } label: {
                        Label(isChineseLanguage ? "导出 CSV 藏品清单..." : "Export Collection CSV...", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        let data = MuseumCSV.blankTemplate()
                        csvDocument = MuseumCSVDocument(data: data)
                        exportingCSV = true
                    } label: {
                        Label(isChineseLanguage ? "下载 CSV 导入模板..." : "Download CSV Template...", systemImage: "doc.text")
                    }
                } label: {
                    Label(isChineseLanguage ? "CSV" : "CSV", systemImage: "tablecells")
                }
                .help(isChineseLanguage ? "CSV 导入与导出" : "CSV Import & Export")
            }
            
            // 云端同步设置
            Button {
                showingCloudSync = true
            } label: {
                Image(systemName: syncManager.isSyncing ? "arrow.triangle.2.circlepath" : "icloud")
                    .symbolEffect(.bounce, value: syncManager.isSyncing)
            }
            .help(isChineseLanguage ? "云端同步设置" : "Cloud Sync")
        }
    }
    
    // MARK: - 辅助方法
    private var isCollectionSection: Bool {
        switch sidebarSelection {
        case .all, .none, .inUse, .battery, .favorites, .dataHealth, .category:
            return true
        case .encyclopedia, .wishlist, .rumors, .spatialMuseum:
            return false
        }
    }
    
    private var middleColumnTitle: String {
        switch sidebarSelection {
        case .all, .none:
            if let fam = categoryNavFamily {
                return appLocalized(fam)
            } else if let br = categoryNavBranch {
                return appLocalized(br)
            } else if let root = categoryNavRoot {
                return categoryTitle(root)
            }
            return isChineseLanguage ? "全部藏品" : "All Collection"
        case .category(let cat):
            if let fam = categoryNavFamily {
                return appLocalized(fam)
            } else if let br = categoryNavBranch {
                return appLocalized(br)
            }
            return categoryTitle(cat)
        case .inUse: return isChineseLanguage ? "在用主力机" : "Daily Drivers"
        case .battery: return isChineseLanguage ? "电池巡检" : "Battery Maintenance"
        case .favorites: return isChineseLanguage ? "星标收藏" : "Favorites"
        case .dataHealth: return isChineseLanguage ? "数据健康体检" : "Data Health"
        case .encyclopedia: return isChineseLanguage ? "硬件百科" : "Encyclopedia"
        case .wishlist: return isChineseLanguage ? "愿望单" : "Wishlist"
        case .rumors: return isChineseLanguage ? "传闻动态" : "Rumors"
        case .spatialMuseum: return isChineseLanguage ? "3D 空间展厅" : "3D Gallery"
        }
    }
    
    private func badgeCount(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
    
    // MARK: - 导出 PDF 清单 (Feature 5)
    private func exportPDFCatalog() {
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "Pomme-Curator-Collection-\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).pdf"
        let items = self.collectionItems
        let title = self.museumTitle
        let onSave: (URL) -> Void = { url in
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let pdfData = CuratorCatalogPDFExporter.generatePDF(for: items, museumTitle: title)
            try? pdfData.write(to: url)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            savePanel.beginSheetModal(for: window) { result in
                if result == .OK, let url = savePanel.url { onSave(url) }
            }
        } else {
            savePanel.begin { result in
                if result == .OK, let url = savePanel.url { onSave(url) }
            }
        }
        #endif
    }
    
    private func handleCSVImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            let imported = (try? MuseumCSV.importing(data, filename: filename))?.items ?? []
            if !imported.isEmpty {
                onBatchUpdate(imported)
            }
        } catch { }
    }
}

