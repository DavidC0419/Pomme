//
//  SpatialMuseumView.swift
//  Pomme
//
//  Vision Pro 空间展厅主模块视图 (Spatial AR Museum Module)
//  提供产品线分类归并、颜色标签选择、真实房间透视摆放、沉浸空间开关与空间手势控制。
//

import SwiftUI
import RealityKit

struct SpatialMuseumView: View {
    var isActive: Bool = true
    @State private var store = SpatialMuseumStore.shared
    
    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    #else
    enum MuseumBrowseMode: String, CaseIterable {
        case stage = "Stage"
        case catalog = "Catalog"
    }

    struct ARQuickLookTarget: Identifiable {
        var id: String { url.absoluteString }
        let url: URL
    }

    @State private var activeQuickLookTarget: ARQuickLookTarget? = nil
    @State private var browseMode: MuseumBrowseMode = .stage
    @State private var searchText: String = ""
    @State private var inspectingItem: ARDeviceItem? = nil
    #endif

    var body: some View {
        #if os(visionOS)
        ZStack {
            if !isActive {
                Color.clear
            } else if store.isImmersiveActive {
                // 沉浸空间已在物理房间中激活：中央通透，保留轻巧精致的浮动状态指示
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "visionpro")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Room Placement Active")
                                .font(.subheadline.weight(.semibold))
                            Text("\(store.placedDevices.count) device\(store.placedDevices.count == 1 ? "" : "s") placed · Tap dock below to place more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Divider().frame(height: 20)

                        // 一键就地正面朝向用户视线回正
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                store.reorientAllFacingUser()
                            }
                        } label: {
                            Label("Face Me", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(store.placedDevices.isEmpty)
                        .font(.caption.weight(.medium))

                        // 全局总锁开关
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.toggleAllLocked()
                            }
                        } label: {
                            Label(
                                store.isAllLocked ? "Unlock All" : "Lock All",
                                systemImage: store.isAllLocked ? "lock.fill" : "lock.open"
                            )
                        }
                        .foregroundStyle(store.isAllLocked ? Color.orange : .primary)
                        .font(.caption.weight(.medium))

                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                store.arrangeInShowcaseRow()
                            }
                        } label: {
                            Label("Showcase Line", systemImage: "circle.grid.cross")
                        }
                        .disabled(store.placedDevices.isEmpty)
                        .font(.caption.weight(.medium))

                        Button(role: .destructive) {
                            toggleImmersiveSpace()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.vertical, 16)
                .frame(maxWidth: 580)
            } else {
                // 展厅发射台 (Launchpad) 超轻量紧凑版：面积大幅压缩，保持启动操作与完整信息，不遮挡真实物理空间
                VStack(spacing: 12) {
                    VStack(spacing: 3) {
                        Text("Spatial Museum")
                            .font(.title3.weight(.bold))
                        Text("Place 1:1 true scale Apple hardware into your physical room.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        // 沉浸空间核心启动按钮
                        Button {
                            toggleImmersiveSpace()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "door.left.hand.open")
                                    .font(.subheadline)
                                Text("Enter Room Placement")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        // 选中产品概览微卡片
                        if let selectedProduct = store.currentSelectedProduct {
                            let activeModel = store.activeVariant(for: selectedProduct)
                            HStack(spacing: 8) {
                                Image(systemName: categorySymbol(selectedProduct.category))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(selectedProduct.name)
                                        .font(.caption.weight(.bold))
                                    HStack(spacing: 4) {
                                        if let year = selectedProduct.year {
                                            Text(year)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        if let color = activeModel.colorLabel {
                                            Text("· \(color)")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("· 1:1 Scale")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 520)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // 顶部控制栏 (Top Ornament)
        // 使用 contentAlignment: .bottom 悬浮于窗口外上方，并添加 16pt 间隙，彻底杜绝与窗口顶部内容/标题发生重叠
        .ornament(attachmentAnchor: .scene(.top), contentAlignment: .bottom) {
            HStack(spacing: 12) {
                // 设备计数器
                Label("\(store.placedDevices.count) Placed", systemImage: "square.3.layers.3d.down.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 6)

                Divider().frame(height: 18)

                // 全局总锁开关：一键锁定全部模型，冻结手势防误操作 (Global Lock Toggle)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.toggleAllLocked()
                    }
                } label: {
                    Label(
                        store.isAllLocked ? "Unlock All" : "Lock All",
                        systemImage: store.isAllLocked ? "lock.fill" : "lock.open"
                    )
                }
                .foregroundStyle(store.isAllLocked ? Color.orange : .primary)
                .help(store.isAllLocked ? "All models locked: tap to enable gestures" : "Lock all models to freeze movements & prevent accidental touches")

                // 一键就地正面朝向用户视线回正 (Face Me All)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        store.reorientAllFacingUser()
                    }
                } label: {
                    Label("Face Me", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.placedDevices.isEmpty)
                .help("Reorient all models in-place to face you")

                // 一键弧形展台对齐
                Button {
                    withAnimation(.spring) {
                        store.arrangeInShowcaseRow()
                    }
                } label: {
                    Label("Showcase Line", systemImage: "circle.grid.cross")
                }
                .disabled(store.placedDevices.isEmpty)

                // 还原 1:1 尺寸
                Button {
                    withAnimation {
                        for d in store.placedDevices { d.scale = 1.0 }
                    }
                } label: {
                    Label("1:1 Scale", systemImage: "ruler")
                }
                .disabled(store.placedDevices.isEmpty)

                // 展台底座微光开关
                Button {
                    withAnimation {
                        store.showMuseumPedestals.toggle()
                    }
                } label: {
                    Label("Stand", systemImage: store.showMuseumPedestals ? "circle.inset.filled" : "circle")
                }
                .help("Toggle Museum Acrylic Stand")

                // 桌面水平防漂移开关：锁定 Y 轴高度 (Lock Height / Y-Axis)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.isYAxisLocked.toggle()
                        for d in store.placedDevices {
                            d.isYAxisLocked = store.isYAxisLocked
                        }
                    }
                } label: {
                    Label(
                        store.isYAxisLocked ? "Lock Height" : "Free Height",
                        systemImage: store.isYAxisLocked ? "arrow.up.and.down.slash" : "arrow.up.and.down"
                    )
                }
                .foregroundStyle(store.isYAxisLocked ? Color.accentColor : .primary)
                .help(store.isYAxisLocked ? "Height locked: moving objects stays flat on desk without vertical drift" : "Height free: can drag up and down in 3D")

                // 浮空标牌与菜单全局总开关 (Toggle All Floating Badges)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.showAllBadges.toggle()
                    }
                } label: {
                    Label(
                        store.showAllBadges ? "Badges" : "Hidden",
                        systemImage: store.showAllBadges ? "eye" : "eye.slash"
                    )
                }
                .help(store.showAllBadges ? "Hide all overhead badges & controls" : "Show all overhead badges & controls")

                // 沉浸空间开关
                Button {
                    toggleImmersiveSpace()
                } label: {
                    Label(
                        store.isImmersiveActive ? "Exit Room" : "Enter Room",
                        systemImage: store.isImmersiveActive ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus"
                    )
                }

                // 清空场景
                if !store.placedDevices.isEmpty {
                    Button(role: .destructive) {
                        withAnimation {
                            store.clearAll()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 16)
        }
        // 底部选品坞：按产品归类与颜色标签收纳 (Bottom Ornament: Product Group & Color Tag Dock)
        // 使用 contentAlignment: .top 并添加 20pt 间隙，彻底杜绝与上方主虚拟窗体发生重合
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            VStack(spacing: 10) {
                // 1. 分类胶囊切换栏
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.categories, id: \.self) { cat in
                            Button {
                                store.selectedCategory = cat
                            } label: {
                                Text(cat)
                                    .font(.caption.weight(store.selectedCategory == cat ? .bold : .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(store.selectedCategory == cat ? Color.accentColor : Color.white.opacity(0.1), in: Capsule())
                                    .foregroundStyle(store.selectedCategory == cat ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // 2. 归类整理后的产品卡片横向滚动列表（带颜色标签选择器）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(store.groupedProducts) { product in
                            ProductGroupSpatialCardView(product: product, store: store) { variant in
                                placeVariant(variant)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .frame(height: 148)
            }
            .padding(14)
            .frame(maxWidth: 920)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.top, 20)
        }
        #else
        // iOS / iPadOS / macOS 原生交互式 3D 展台与 AR Quick Look 空间分类展馆
        VStack(spacing: 0) {
            // 1. 吸顶搜索框 (支持按型号、年份、芯片、颜色模糊检索 3D 模型)
            PinnedSearchField(
                text: $searchText,
                prompt: "Search 3D models (e.g. iPhone 17, Mac mini, AirPods)"
            )

            // 2. 精选品类切换胶囊栏 (带各分类专属图标与数量徽标，点击即刻换展)
            categoryPillBar

            // 3. 主浏览展示区：支持“3D 展台舞台模式”与“全景分类目录网格”自由切换
            Group {
                if !isActive {
                    Color.clear
                } else if browseMode == .stage && searchText.isEmpty {
                    stageView
                } else {
                    catalogGridView
                }
            }
        }
        .navigationTitle("3D & AR Museum")
        .platformInlineTitleMode()
        .toolbar {
            ToolbarItem(placement: .appTopBarTrailing) {
                HStack(spacing: 2) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            browseMode = .stage
                        }
                    } label: {
                        Image(systemName: "cube.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(browseMode == .stage ? Color.primary : Color.secondary)
                            .frame(width: 36, height: 28)
                            .background {
                                if browseMode == .stage {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        #if canImport(UIKit)
                                        .fill(Color(uiColor: .systemBackground))
                                        #else
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        #endif
                                        .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stage Mode")

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            browseMode = .catalog
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(browseMode == .catalog ? Color.primary : Color.secondary)
                            .frame(width: 36, height: 28)
                            .background {
                                if browseMode == .catalog {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        #if canImport(UIKit)
                                        .fill(Color(uiColor: .systemBackground))
                                        #else
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        #endif
                                        .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Grid Catalog Mode")
                }
                .padding(2)
                #if canImport(UIKit)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                #else
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                #endif
            }
        }
        .sheet(item: $inspectingItem) { item in
            Device3DInspectorSheet(item: item)
        }
        #if os(iOS)
        .fullScreenCover(item: $activeQuickLookTarget) { target in
            ARQuickLookContainerView(url: target.url) {
                activeQuickLookTarget = nil
            }
            .ignoresSafeArea()
        }
        #endif
        #endif
    }

    #if os(visionOS)
    private func placeVariant(_ variant: ARDeviceItem) {
        withAnimation(.spring) {
            store.spawn(model: variant)
        }
        // 如果当前尚未进入沉浸模式，轻量开启沉浸空间
        if !store.isImmersiveActive {
            Task {
                let result = await openImmersiveSpace(id: "SpatialMuseumImmersiveSpace")
                if case .opened = result {
                    store.isImmersiveActive = true
                }
            }
        }
    }

    private func toggleImmersiveSpace() {
        Task {
            if store.isImmersiveActive {
                await dismissImmersiveSpace()
                store.isImmersiveActive = false
            } else {
                let result = await openImmersiveSpace(id: "SpatialMuseumImmersiveSpace")
                if case .opened = result {
                    store.isImmersiveActive = true
                }
            }
        }
    }
    #endif

    #if !os(visionOS)
    // MARK: - 分类胶囊选择栏 (Curated Category Pills)
    @ViewBuilder
    private var categoryPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.categories, id: \.self) { cat in
                    let isSelected = store.selectedCategory == cat
                    let count = categoryCount(cat)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.selectedCategory = cat
                            if let first = store.groupedProducts.first {
                                store.selectedProductID = first.id
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: categorySymbol(cat))
                                .font(.caption.weight(.semibold))
                            Text(categoryTitle(cat))
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.08), in: Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.background)
    }

    // MARK: - 展台舞台模式 (Stage View: Turntable + Quick Shelf)
    @ViewBuilder
    private var stageView: some View {
        VStack(spacing: 0) {
            // 3D 核心展台
            ZStack(alignment: .bottom) {
                let activeProduct = store.currentSelectedProduct ?? displayedProducts.first
                let activeModel = activeProduct.map { store.activeVariant(for: $0) }

                if let activeModel, let url = activeModel.resolvedURL, isActive {
                    Model3DTurntableView(url: url, isTabActive: isActive)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No 3D Models",
                        systemImage: "cube.transparent",
                        description: Text("Try adjusting your search or category filter.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // 展台浮动信息卡
                if let activeProduct, let activeModel {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activeProduct.name)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                if let year = activeProduct.year {
                                    Text(year)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let color = activeModel.colorLabel {
                                    Text("· \(color)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("· 1:1 Scale")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        Spacer()

                        // 颜色快速选择
                        if activeProduct.availableColors.count > 1 {
                            HStack(spacing: 6) {
                                ForEach(activeProduct.availableColors, id: \.self) { color in
                                    let isSelected = (activeModel.colorLabel == color || deviceColorToken(activeModel.colorLabel) == deviceColorToken(color))
                                    Button {
                                        store.selectColor(color, for: activeProduct)
                                    } label: {
                                        Circle()
                                            .fill(colorSwatch(color))
                                            .frame(width: 18, height: 18)
                                            .overlay(
                                                Circle()
                                                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                                            )
                                            .scaleEffect(isSelected ? 1.15 : 1.0)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        #if os(iOS)
                        if let url = activeModel.resolvedURL {
                            Button {
                                store.selectedProductID = activeProduct.id
                                activeQuickLookTarget = ARQuickLookTarget(url: url)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arkit")
                                    Text("AR")
                                        .font(.caption.weight(.bold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        #endif
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

            // 底部横向快捷货架 (Quick Shelf)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(categoryTitle(store.selectedCategory)) Shelf (\(displayedProducts.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation { browseMode = .catalog }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Browse All Grid")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 16)

                if displayedProducts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(height: 146)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(displayedProducts) { product in
                                ProductGroupSpatialCardView(product: product, store: store) { variant in
                                    store.selectedProductID = product.id
                                    #if os(iOS)
                                    if let url = variant.resolvedURL {
                                        activeQuickLookTarget = ARQuickLookTarget(url: url)
                                    }
                                    #endif
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .frame(height: 146)
                }
            }
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
        }
    }

    // MARK: - 全景分类目录网格模式 (Catalog Grid View: Categorized Sections)
    @ViewBuilder
    private var catalogGridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if displayedProducts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 40)
                } else if store.selectedCategory != "All" || !searchText.isEmpty {
                    // 单个分类或搜索结果
                    HStack {
                        Label(
                            searchText.isEmpty ? categoryTitle(store.selectedCategory) : "Search Results",
                            systemImage: searchText.isEmpty ? categorySymbol(store.selectedCategory) : "magnifyingglass"
                        )
                        .font(.title3.weight(.bold))
                        Spacer()
                        Text("\(displayedProducts.count) items")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    LazyVGrid(columns: appCategoryGridColumns, spacing: 14) {
                        ForEach(displayedProducts) { product in
                            ProductGroupGridCardView(product: product, store: store) { variant in
                                #if os(iOS)
                                store.selectedProductID = product.id
                                if let url = variant.resolvedURL {
                                    activeQuickLookTarget = ARQuickLookTarget(url: url)
                                }
                                #endif
                            } onInspect: { variant in
                                inspectingItem = variant
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    // 完整的按品类分节纵向展示 (Clean Categorized Sections)
                    ForEach(store.categories.filter { $0 != "All" }, id: \.self) { cat in
                        let catProducts = store.groupedProducts.filter {
                            $0.category == cat ||
                            (($0.category == "Home" || $0.category == "HomePod") && (cat == "Home" || cat == "HomePod")) ||
                            ($0.category == "Vision" && cat == "Vision Pro")
                        }
                        if !catProducts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label(categoryTitle(cat), systemImage: categorySymbol(cat))
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Text("\(catProducts.count) models")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)

                                LazyVGrid(columns: appCategoryGridColumns, spacing: 14) {
                                    ForEach(catProducts) { product in
                                        ProductGroupGridCardView(product: product, store: store) { variant in
                                            #if os(iOS)
                                            store.selectedProductID = product.id
                                            if let url = variant.resolvedURL {
                                                activeQuickLookTarget = ARQuickLookTarget(url: url)
                                            }
                                            #endif
                                        } onInspect: { variant in
                                            inspectingItem = variant
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func categoryCount(_ category: String) -> Int {
        if category == "All" {
            return store.groupedProducts.count
        }
        return store.groupedProducts.filter {
            $0.category == category ||
            (($0.category == "Home" || $0.category == "HomePod") && (category == "Home" || category == "HomePod")) ||
            ($0.category == "Vision" && category == "Vision Pro")
        }.count
    }

    private var displayedProducts: [ARProductGroup] {
        let base = store.groupedProducts
        let clean = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return base }
        return base.filter { p in
            p.name.localizedCaseInsensitiveContains(clean) ||
            p.category.localizedCaseInsensitiveContains(clean) ||
            (p.year?.localizedCaseInsensitiveContains(clean) ?? false) ||
            p.variants.contains {
                $0.fileName.localizedCaseInsensitiveContains(clean) ||
                ($0.colorLabel?.localizedCaseInsensitiveContains(clean) ?? false)
            }
        }
    }

    private func categoryTitle(_ category: String) -> String {
        switch category {
        case "All": return "All"
        case "iPhone": return "iPhone"
        case "Mac": return "Mac"
        case "iPad": return "iPad"
        case "Watch": return "Apple Watch"
        case "AirPods": return "AirPods"
        case "Home", "HomePod": return "Home"
        case "Display": return "Displays"
        case "Vision", "Vision Pro": return "Vision"
        case "Accessories": return "Accessories"
        case "Apple Park": return "Apple Park"
        default: return category
        }
    }
    #endif

    private func categorySymbol(_ category: String) -> String {
        switch category {
        case "Mac": return "macbook"
        case "iPhone": return "iphone"
        case "iPad": return "ipad"
        case "Watch": return "applewatch"
        case "AirPods": return "airpodspro"
        case "Vision", "Vision Pro": return "visionpro"
        case "HomePod", "Home": return "homepod.fill"
        case "Display": return "display"
        case "Accessories": return "cable.connector"
        case "Apple Park": return "leaf.circle"
        default: return "sparkles"
        }
    }
}

// MARK: - 单款产品聚合卡片视图（集成颜色标签选择器，告别重复卡片）
struct ProductGroupSpatialCardView: View {
    let product: ARProductGroup
    @Bindable var store: SpatialMuseumStore
    var onPlace: (ARDeviceItem) -> Void

    var body: some View {
        let activeVariant = store.activeVariant(for: product)
        let colors = product.availableColors

        VStack(alignment: .leading, spacing: 6) {
            // 顶栏：品类图标与年份
            HStack {
                Image(systemName: categorySymbol(product.category))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if let year = product.year {
                    Text(year)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // 产品全称
            Text(product.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 当前选中的颜色名称
            if let activeColor = activeVariant.colorLabel {
                Text(activeColor)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Standard")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // 颜色选择标签栏（支持多颜色横向点选，与 iOS 端设计完美一致）
            if colors.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(colors, id: \.self) { color in
                            let isSelected = (activeVariant.colorLabel == color || deviceColorToken(activeVariant.colorLabel) == deviceColorToken(color))
                            Button {
                                store.selectedProductID = product.id
                                store.selectColor(color, for: product)
                            } label: {
                                Circle()
                                    .fill(colorSwatch(color))
                                    .frame(width: 13, height: 13)
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.35), lineWidth: isSelected ? 2 : 1)
                                    )
                                    .scaleEffect(isSelected ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 20)
            } else {
                Spacer().frame(height: 20)
            }

            // 底部一键摆放到空间按钮
            Button {
                store.selectedProductID = product.id
                onPlace(activeVariant)
            } label: {
                HStack(spacing: 4) {
                    #if os(visionOS)
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    Text("Place in Room")
                        .font(.system(size: 11, weight: .semibold))
                    #elseif os(iOS)
                    Image(systemName: "arkit")
                        .font(.caption)
                    Text("View in AR")
                        .font(.system(size: 11, weight: .semibold))
                    #else
                    Image(systemName: "cube.transparent")
                        .font(.caption)
                    Text("Inspect 3D")
                        .font(.system(size: 11, weight: .semibold))
                    #endif
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 172, height: 136)
        .background(store.selectedProductID == product.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(store.selectedProductID == product.id ? Color.accentColor : Color.white.opacity(0.12), lineWidth: store.selectedProductID == product.id ? 2 : 1)
        )
        .onTapGesture {
            store.selectedProductID = product.id
        }
    }

    private func categorySymbol(_ category: String) -> String {
        switch category {
        case "Mac": return "macbook"
        case "iPhone": return "iphone"
        case "iPad": return "ipad"
        case "Watch": return "applewatch"
        case "AirPods": return "airpodspro"
        case "Vision", "Vision Pro": return "visionpro"
        case "HomePod", "Home": return "homepod.fill"
        case "Display": return "display"
        case "Accessories": return "cable.connector"
        case "Apple Park": return "leaf.circle"
        default: return "cube.transparent"
        }
    }
}

#if !os(visionOS)
// MARK: - 3D 展馆网格目录卡片 (Product Group Grid Card)
struct ProductGroupGridCardView: View {
    let product: ARProductGroup
    @Bindable var store: SpatialMuseumStore
    var onAR: (ARDeviceItem) -> Void
    var onInspect: (ARDeviceItem) -> Void

    var body: some View {
        let activeVariant = store.activeVariant(for: product)
        let colors = product.availableColors

        VStack(alignment: .leading, spacing: 8) {
            // 顶栏：品类图标与年份
            HStack {
                Image(systemName: categorySymbol(product.category))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)

                Spacer()

                if let year = product.year {
                    Text(year)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // 产品全称
            Text(product.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44, alignment: .topLeading)

            // 变体信息与颜色数量
            HStack(spacing: 6) {
                if let activeColor = activeVariant.colorLabel {
                    Text(activeColor)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(product.variants.count) \(product.variants.count == 1 ? "color" : "colors")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            // 颜色选择圆点
            if colors.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(colors, id: \.self) { color in
                            let isSelected = (activeVariant.colorLabel == color || deviceColorToken(activeVariant.colorLabel) == deviceColorToken(color))
                            Button {
                                store.selectColor(color, for: product)
                            } label: {
                                Circle()
                                    .fill(colorSwatch(color))
                                    .frame(width: 13, height: 13)
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.35), lineWidth: isSelected ? 2 : 1)
                                    )
                                    .scaleEffect(isSelected ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 20)
            } else {
                Spacer().frame(height: 20)
            }

            // 底部操作按钮栏
            HStack(spacing: 8) {
                Button {
                    onInspect(activeVariant)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cube.transparent")
                        Text("3D")
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                #if os(iOS)
                Button {
                    onAR(activeVariant)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arkit")
                        Text("AR")
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func categorySymbol(_ category: String) -> String {
        switch category {
        case "Mac": return "macbook"
        case "iPhone": return "iphone"
        case "iPad": return "ipad"
        case "Watch": return "applewatch"
        case "AirPods": return "airpodspro"
        case "Vision", "Vision Pro": return "visionpro"
        case "HomePod", "Home": return "homepod.fill"
        case "Display": return "display"
        case "Accessories": return "cable.connector"
        case "Apple Park": return "leaf.circle"
        default: return "cube.transparent"
        }
    }
}
#endif
