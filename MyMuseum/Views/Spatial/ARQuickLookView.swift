//
//  ARQuickLookView.swift
//  Pomme
//
//  原生 3D 与 AR 预览控制器 (Native 3D & AR Quick Look Viewer)
//  支持 iOS / iPadOS 原生系统级 AR QuickLook (支持真实空间 1:1 投影)、
//  前台唤醒防白屏自动恢复机制、单按钮便捷退出机制、
//  全平台 SceneKit 交互式 3D 展台、光影材质与触控/鼠标自由旋转缩放。
//

import SwiftUI
import QuickLook
#if canImport(SceneKit)
import SceneKit
#endif

// MARK: - iOS / iPadOS 原生 AR Quick Look 宿主控制器 (带防白屏恢复与退出回调)
#if os(iOS)
final class ARQuickLookHostController: UIViewController, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private var url: URL
    var onDismiss: (() -> Void)?
    private let previewController = QLPreviewController()

    init(url: URL, onDismiss: (() -> Void)? = nil) {
        self.url = url
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        previewController.dataSource = self
        previewController.delegate = self

        addChild(previewController)
        view.addSubview(previewController.view)
        previewController.view.frame = view.bounds
        previewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        previewController.didMove(toParent: self)

        // 监听进入前台通知：当用户中途切出 App 再返回时，主动刷新数据源，杜绝白屏/卡顿
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func updateURL(_ newURL: URL) {
        if self.url != newURL {
            self.url = newURL
            previewController.reloadData()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.previewController.refreshCurrentPreviewItem()
            self.previewController.reloadData()
        }
    }

    // MARK: - QLPreviewControllerDataSource
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        url as NSURL
    }

    // MARK: - QLPreviewControllerDelegate
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        onDismiss?()
    }
}

struct ARQuickLookView: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> ARQuickLookHostController {
        ARQuickLookHostController(url: url, onDismiss: onDismiss)
    }

    func updateUIViewController(_ controller: ARQuickLookHostController, context: Context) {
        controller.onDismiss = onDismiss
        controller.updateURL(url)
    }
}

// MARK: - AR Quick Look 容器视图 (集成单按钮退出机制与前台唤醒双重保护)
struct ARQuickLookContainerView: View {
    let url: URL
    var onDismiss: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var reloadToken = UUID()

    var body: some View {
        GeometryReader { geo in
            // 避让灵动岛与系统状态栏（顶部安全距离 + 12pt 下移），彻底解决点不动问题
            let topInset = max(geo.safeAreaInsets.top, 54) + 12
            let trailingInset = max(geo.safeAreaInsets.trailing, 16) + 4

            ZStack(alignment: .topTrailing) {
                ARQuickLookView(url: url, onDismiss: onDismiss)
                    .id(reloadToken)
                    .ignoresSafeArea()

                // 悬浮单按钮退出机制 (下移至状态栏与灵动岛下方，扩大点击热区至 54x54)
                Button {
                    onDismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.65))
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.2))
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)

                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 54, height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, topInset)
                .padding(.trailing, trailingInset)
                .accessibilityLabel("Dismiss AR")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // 中途切出 App 再返回时，刷新重构视图，彻底解决 AR 渲染管线丢失导致的白屏问题
                reloadToken = UUID()
            }
        }
    }
}
#endif

// MARK: - 全平台交互式 3D 展台 (Interactive 3D Turntable Stage)
#if canImport(SceneKit)
struct Model3DTurntableView: View {
    let url: URL
    var isTabActive: Bool = true
    @State private var scene: SCNScene?
    @State private var isLoading = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if isTabActive && scenePhase == .active, let scene {
                SceneView(
                    scene: scene,
                    options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
                .background(Color.clear)
            } else if isLoading && isTabActive {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading 3D Model…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("3D Model Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: url) {
            guard isTabActive else { return }
            loadScene()
        }
        .onChange(of: isTabActive) { _, active in
            if active {
                if scene == nil { loadScene() }
            } else {
                scene = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && isTabActive && scene == nil {
                loadScene()
            } else if newPhase != .active {
                scene = nil
            }
        }
    }

    private func loadScene() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            // 使用 SceneKit 加载 USDZ
            let loadedScene = try? SCNScene(url: url, options: [
                .checkConsistency: false
            ])
            if let loadedScene {
                // 如果场景缺少环境光，添加柔和环境光，保证各角度材质呈现
                if loadedScene.rootNode.childNode(withName: "pomme_ambient_light", recursively: true) == nil {
                    let ambientNode = SCNNode()
                    ambientNode.name = "pomme_ambient_light"
                    ambientNode.light = SCNLight()
                    ambientNode.light?.type = .ambient
                    ambientNode.light?.intensity = 600
                    loadedScene.rootNode.addChildNode(ambientNode)
                }
            }
            DispatchQueue.main.async {
                self.scene = loadedScene
                self.isLoading = false
            }
        }
    }
}
#endif

// MARK: - 3D 模型专属全屏/弹窗检查器 (Device 3D & AR Inspector Sheet)
struct Device3DInspectorSheet: View {
    let item: ARDeviceItem
    @Environment(\.dismiss) private var dismiss
    @State private var showingARQuickLook = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 3D 核心舞台
                if let url = item.resolvedURL {
                    Model3DTurntableView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Model Unavailable",
                        systemImage: "cube.transparent",
                        description: Text("The 3D model file for this device could not be found.")
                    )
                }

                // 底部操作与规格浮动卡
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)

                            HStack(spacing: 6) {
                                if let year = item.year {
                                    Text(year)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                if let color = item.colorLabel {
                                    Text("· \(color)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Text("· 1:1 Scale")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        Spacer()

                        #if os(iOS)
                        if item.resolvedURL != nil {
                            Button {
                                showingARQuickLook = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arkit")
                                        .font(.subheadline)
                                    Text("View in AR")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                            }
                        }
                        #endif
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(item.displayName)
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLocalized("Done")) { dismiss() }
                }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showingARQuickLook) {
                if let url = item.resolvedURL {
                    ARQuickLookContainerView(url: url) {
                        showingARQuickLook = false
                    }
                    .ignoresSafeArea()
                }
            }
            #endif
        }
    }
}
