//
//  AppearanceControls.swift
//  Pomme
//
//  苹果风明暗外观与省电模式控制套件 (Apple-style Appearance & Eco Mode Controls)
//  支持 [明 / 自动 / 暗] 分段切换与菜单、系统低电量模式智能协同。
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 外观模式枚举 (App Appearance Mode)
enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case light = "light"
    case auto = "auto"
    case dark = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return isChineseLanguage ? "浅色" : "Light"
        case .auto: return isChineseLanguage ? "自动" : "Auto"
        case .dark: return isChineseLanguage ? "深色" : "Dark"
        }
    }

    var fullLabel: String {
        switch self {
        case .light: return isChineseLanguage ? "浅色外观" : "Light Appearance"
        case .auto: return isChineseLanguage ? "自动 (跟随系统)" : "Auto (System)"
        case .dark: return isChineseLanguage ? "深色外观" : "Dark Appearance"
        }
    }

    var iconName: String {
        switch self {
        case .light: return "sun.max.fill"
        case .auto: return "circle.righthalf.filled"
        case .dark: return "moon.fill"
        }
    }

    var activeTint: Color {
        switch self {
        case .light: return Color.orange
        case .auto: return Color.accentColor
        case .dark: return Color.indigo
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .auto: return nil
        case .dark: return .dark
        }
    }
}

// MARK: - 智能省电管理中心 (Power Saving Manager)
@MainActor
final class PowerSavingManager: ObservableObject {
    static let shared = PowerSavingManager()

    @Published var isSystemLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @AppStorage("ecoPowerSaverEnabled") var userEcoMode: Bool = false

    /// 当前是否处于任何省电模式下（系统低电量或用户主动开启省电优化）
    var isEcoActive: Bool {
        isSystemLowPowerMode || userEcoMode
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSystemLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.objectWillChange.send()
            }
        }
    }
}

// MARK: - 苹果风明暗分段选择器 (Apple-style Segmented Capsule Button)
struct AppleAppearanceSegmentedControl: View {
    @AppStorage("appAppearanceMode") private var currentRawMode: String = AppAppearanceMode.auto.rawValue
    @Namespace private var animationNamespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppAppearanceMode.allCases) { mode in
                let isSelected = (currentRawMode == mode.rawValue)
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        currentRawMode = mode.rawValue
                    }
                } label: {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? mode.activeTint : .secondary)
                        .frame(width: 32, height: 28)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "activeAppearancePill", in: animationNamespace)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(mode.fullLabel)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance mode")
    }
}

// MARK: - 苹果风单按钮明暗菜单 (Apple-style Appearance Menu Button)
struct AppleAppearanceMenuButton: View {
    @AppStorage("appAppearanceMode") private var currentRawMode: String = AppAppearanceMode.auto.rawValue

    private var currentMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: currentRawMode) ?? .auto
    }

    var body: some View {
        Menu {
            Picker("Appearance", selection: $currentRawMode) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Label(mode.fullLabel, systemImage: mode.iconName)
                        .tag(mode.rawValue)
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                Image(systemName: currentMode.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(currentMode.activeTint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Appearance: \(currentMode.label)")
    }
}
