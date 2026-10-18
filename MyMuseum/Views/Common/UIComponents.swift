//
//  UIComponents.swift
//  Pomme
//
//  通用基础 UI 组件 (Common UI Components)
//  包含搜索框、设备卡片、图样渲染 (DeviceArtwork)、颜色选择器等。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 跨平台导航栏内联标题修饰器
extension View {
    @ViewBuilder
    func platformInlineTitleMode() -> some View {
#if os(macOS)
        // macOS 没有 iPhone 风格的导航栏标题模式，直接保留原视图
        self
#else
        self.navigationBarTitleDisplayMode(.inline)
#endif
    }

    @ViewBuilder
    func platformHideTabBar() -> some View {
#if !os(macOS)
        self.toolbar(.hidden, for: .tabBar)
#else
        self
#endif
    }

    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
#if os(visionOS)
        self
#else
        self.scrollDismissesKeyboard(.interactively)
#endif
    }
}

// MARK: - 跨平台 ToolbarItemPlacement 适配
extension ToolbarItemPlacement {
    static var appTopBarTrailing: ToolbarItemPlacement {
#if os(macOS)
        return .primaryAction
#else
        return .topBarTrailing
#endif
    }
    
    static var appTopBarLeading: ToolbarItemPlacement {
#if os(macOS)
        return .navigation
#else
        return .topBarLeading
#endif
    }
}

#if canImport(UIKit)
import UIKit
#endif

/// 全局收起键盘快捷方法
func hideKeyboard() {
#if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
public let macControlBackground = Color(NSColor.controlBackgroundColor)
public let macWindowBackground = Color(NSColor.windowBackgroundColor)
public let macSeparatorColor = Color(NSColor.separatorColor)
#elseif canImport(UIKit)
import UIKit
public let macControlBackground = Color(UIColor.secondarySystemBackground)
public let macWindowBackground = Color(UIColor.systemBackground)
public let macSeparatorColor = Color(UIColor.separator)
#else
public let macControlBackground = Color.secondary.opacity(0.1)
public let macWindowBackground = Color.clear
public let macSeparatorColor = Color.secondary.opacity(0.2)
#endif

// MARK: - 固定吸顶搜索栏 (Pinned Search Field)
struct PinnedSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(appLocalized(prompt), text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        isFocused = false
                        hideKeyboard()
                    }
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))

            if isFocused || !text.isEmpty {
                Button(appLocalized("Cancel")) {
                    text = ""
                    isFocused = false
                    hideKeyboard()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .font(.subheadline.weight(.medium))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - 自适应网格列配置 (Category Grid Columns)
var appCategoryGridColumns: [GridItem] {
#if canImport(UIKit)
    let minWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 210 : 155
#else
    let minWidth: CGFloat = 210
#endif
    return [GridItem(.adaptive(minimum: minWidth), spacing: 14)]
}

#if canImport(UIKit)
// MARK: - 通用原生分享弹窗包装 (Activity View)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif canImport(AppKit)
struct ActivityView: NSViewRepresentable {
    let activityItems: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: activityItems)
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

// MARK: - 分类汇总卡片 (Category Card)
struct CategoryCard: View {
    let title: String
    let count: Int
    let symbol: String
    var artworkAssetName: String? = nil
    var categoryKey: String? = nil
    var fallbackArtwork: String? = nil
    
    @ObservedObject private var coverStore = CategoryCoverStore.shared

    private var resolvedArtwork: String? {
        if let artworkAssetName, imageAssetExists(artworkAssetName) {
            return artworkAssetName
        }
        let key = categoryKey ?? title
        return coverStore.coverAssetName(for: key, fallback: fallbackArtwork)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                
                Spacer(minLength: 12)
                
                Text(appLocalized(title))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                
                Text(String(format: appLocalized("%lld products"), Int64(count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let artwork = resolvedArtwork {
                Image(artwork)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 76)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - 图鉴单品卡片 (Catalog Item Card)
struct CatalogItemCard: View {
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            DeviceArtwork(device: device, compact: true)
            Text(device.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text([device.model, device.year].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 搜索与图鉴单品图片渲染 (Search Catalog Artwork)
// 有本地渲染图就显示产品外观；源站缺图时仍显示类别图标，不影响添加。
struct SearchCatalogArtwork: View {
    let assetName: String
    let category: String

    private var hasArtwork: Bool {
#if canImport(UIKit)
        UIImage(named: assetName) != nil
#elseif canImport(AppKit)
        NSImage(named: NSImage.Name(assetName)) != nil
#else
        false
#endif
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.65))
            if hasArtwork {
                Image(assetName).resizable().scaledToFit().padding(5)
            } else {
                Image(systemName: categorySymbol(category))
                    .font(.title2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 82, height: 74)
    }
}

// MARK: - 图鉴展示多图拼合视图 (Catalog Display Artwork)
struct CatalogDisplayArtwork: View {
    let product: CatalogDisplayProduct

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(product.artworkNames.prefix(product.isAirPodsSet ? 3 : 1)), id: \.self) { assetName in
                SearchCatalogArtwork(assetName: assetName, category: product.category)
                    .frame(width: 82)
            }
        }
        .frame(height: 78)
    }
}

// MARK: - 设备主视觉图渲染卡片 (Device Artwork)
struct DeviceArtwork: View {
    let category: String
    let year: String?
    let model: String?
    let compact: Bool
    let artworkAssetName: String

    init(item: CollectionItem, compact: Bool) {
        category = item.category
        year = item.releaseYear
        model = item.model
        artworkAssetName = item.artworkAssetName
        self.compact = compact
    }

    init(device: Device, product: CatalogDisplayProduct? = nil, compact: Bool = false) {
        category = device.category
        year = device.year
        model = device.model
        let candidateName = product?.artworkNames.first(where: { imageAssetExists($0) }) ?? product?.artworkNames.first
        let colorAssetName = deviceArtworkAssetName(device.id, color: device.color)
        if !device.color.isEmpty && colorAssetName.contains("_color_") && imageAssetExists(colorAssetName) {
            artworkAssetName = colorAssetName
        } else {
            artworkAssetName = candidateName ?? colorAssetName
        }
        self.compact = compact
    }

    init(device: Device, compact: Bool) {
        self.init(device: device, product: nil, compact: compact)
    }

    private var hasArtwork: Bool {
        // iOS/iPadOS 用 UIImage 查图片；Mac 用 NSImage 查图片。找不到时显示 SF Symbol。
#if canImport(UIKit)
        UIImage(named: artworkAssetName) != nil
#elseif canImport(AppKit)
        NSImage(named: NSImage.Name(artworkAssetName)) != nil
#else
        false
#endif
    }

    private var palette: [Color] {
        switch category {
        case "Mac": return [.black, .gray]
        case "iPhone": return [.blue, .indigo]
        case "iPad": return [.blue, .teal]
        case "iPod": return [.orange, .pink]
        case "Apple Vision Pro", "Vision Pro", "Vision pro", "Headset": return [.indigo, .cyan]
        case "Beats", "AirPods", "Airpods": return [.purple, .pink]
        case "Apple Watch", "Apple watch", "Watch": return [.teal, .blue]
        case "Home", "家庭", "Home Accessories", "家庭配件", "Apple TV", "HomePod": return [.orange, .red]
        case "Input Devices", "输入设备": return [.teal, .cyan]
        default: return [.teal, .indigo]
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 18 : 30)
                .fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: compact ? 130 : 250, height: compact ? 130 : 250)
                .blur(radius: 1)
                .offset(x: compact ? 50 : 100, y: compact ? -38 : -72)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(categoryTitle(category))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                    Spacer(minLength: 4)
                    if let year, !year.isEmpty {
                        Text(year)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                ZStack {
                    if hasArtwork {
                        let isMax2 = isAirPodsMax2(artworkName: artworkAssetName, model: model)
                        let isMax1 = isAirPodsMax1(artworkName: artworkAssetName, model: model)
                        let isGlacier = isPowerbeatsProGlacier(artworkName: artworkAssetName, model: model)
                        let pad: CGFloat = {
                            if compact {
                                return (isMax2 || isMax1) ? 0 : 2
                            } else {
                                return isGlacier ? 0 : 8
                            }
                        }()
                        let scale: CGFloat = {
                            if compact {
                                // 外层 icon 卡片：2代/USB-C款放大为 1.5x；1代适度放大至 1.5x；Glacier维持1.0x
                                if isMax2 { return 1.5 }
                                if isMax1 { return 1.5 }
                                return 1.0
                            } else {
                                // 产品详情图：2代与 USB-C 1代按用户需求放大为 1.5x；Powerbeats Pro Glacier 图片 1.5x
                                if isMax2 { return 1.5 }
                                if isGlacier { return 1.5 }
                                return 1.0
                            }
                        }()

                        Image(artworkAssetName)
                            .resizable()
                            .scaledToFit()
                            .padding(pad)
                            .scaleEffect(scale)
                    } else {
                        Image(systemName: categorySymbol(category))
                            .font(.system(size: compact ? 42 : 76, weight: .light))
                            .foregroundStyle(.white.opacity(0.94))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 76 : 160)
                Spacer(minLength: 2)
                if let model, !model.isEmpty {
                    Text(model)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.76))
                }
            }
            .padding(compact ? 13 : 22)
        }
        .frame(height: compact ? 170 : 300)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 30))
    }
}

// MARK: - 配色选择滚动胶囊栏 (Device Color Selector)
struct DeviceColorSelector: View {
    let colors: [String]
    let selection: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(colors, id: \.self) { color in
                    let swatch = colorSwatch(color)
                    let isSelected = (selection == color || (selection != nil && deviceColorToken(selection) == deviceColorToken(color)))
                    Button { onSelect(color) } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(swatch)
                                .frame(width: 17, height: 17)
                                .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                            Text(deviceColorLabel(color)).font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(isSelected ? swatch.opacity(0.22) : Color.secondary.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(isSelected ? swatch : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: appLocalized("Select %@"), deviceColorLabel(color)))
                }
            }
        }
    }
}
