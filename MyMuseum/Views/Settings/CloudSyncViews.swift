//
//  CloudSyncViews.swift
//  Pomme
//
//  iCloud Drive 文件夹多端自动同步设置视图与交互面板 (Cloud Sync Settings & Views)
//  默认全英文，支持系统本地化语言切换 (English by default, localized into Chinese on Chinese system).
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit) && !os(watchOS)
import UIKit

// MARK: - iOS / visionOS 文件夹选择器
struct FolderPickerRepresentable: UIViewControllerRepresentable {
    var onFolderPicked: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FolderPickerRepresentable
        init(_ parent: FolderPickerRepresentable) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onFolderPicked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
#endif

// MARK: - iCloud 多端同步设置主面板 (Cloud Sync Settings Sheet)
struct CloudSyncSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var syncManager = CloudVaultSyncManager.shared
    @ObservedObject private var powerSaving = PowerSavingManager.shared

    @State private var showingFolderPicker = false
    @State private var showingDisconnectAlert = false
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert = false

    private var cardBackground: Color {
        #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color.secondary.opacity(0.1)
        #endif
    }

    private var sheetBackground: Color {
        #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color.clear
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 顶部状态主卡片 (Hero Status Card)
                    statusHeroCard

                    // 2. 外观模式与智能省电设置 (Appearance & Power Saver)
                    appearanceAndPowerSection

                    // 3. 同步操作快捷区 (Quick Actions)
                    syncActionsSection

                    // 4. 藏品与同步统计 (Sync & Data Stats)
                    statsSection

                    // 5. 多端同步操作指引 (Multi-Device Step Guide)
                    setupGuideSection

                    // 6. Apple Watch 协同与安全说明 (Watch & Privacy Notes)
                    securityAndWatchNotes
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(sheetBackground.ignoresSafeArea())
            .navigationTitle("Preferences & Cloud Sync")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
            #if canImport(UIKit) && !os(watchOS)
            .sheet(isPresented: $showingFolderPicker) {
                FolderPickerRepresentable { url in
                    showingFolderPicker = false
                    handleFolderSelection(url: url)
                } onCancel: {
                    showingFolderPicker = false
                }
                .ignoresSafeArea()
            }
            #endif
            .alert("Disconnect Sync?", isPresented: $showingDisconnectAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    syncManager.disconnectSyncFolder()
                }
            } message: {
                Text("Disconnecting will not delete local devices, but changes will no longer sync until reconnected.")
            }
            .alert("Sync Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - 状态卡片 (Hero Status Card)
    private var statusHeroCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(syncManager.isConfigured ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: syncManager.isConfigured ? "icloud.and.arrow.up.fill" : "icloud.slash.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(syncManager.isConfigured ? Color.cyan : Color.secondary)
            }

            VStack(spacing: 4) {
                Text(syncManager.isConfigured ? "iCloud Drive Real-Time Sync" : "No iCloud Folder Connected")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                if syncManager.isConfigured {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(syncManager.currentFolderName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cyan)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.12), in: Capsule())
                } else {
                    Text("Select an iCloud Drive folder to enable multi-device sync")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // 状态徽章与上次同步时间
            HStack(spacing: 8) {
                Circle()
                    .fill(statusIndicatorColor)
                    .frame(width: 8, height: 8)

                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(syncManager.isConfigured ? Color.cyan.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - 外观模式与智能省电设置 (Appearance & Power Saving)
    private var appearanceAndPowerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance & Eco Mode")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            // 外观模式调节卡片
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("App Theme", systemImage: "circle.righthalf.filled")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    AppleAppearanceSegmentedControl()
                }

                Text("Choose between Light, Dark, or automatically match your Apple device's system appearance.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))

            // 智能省电优化卡片
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Eco Power Saver", systemImage: "leaf.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(powerSaving.isEcoActive ? Color.green : Color.primary)

                    Spacer()

                    Toggle("", isOn: $powerSaving.userEcoMode)
                        .labelsHidden()
                }

                if powerSaving.isSystemLowPowerMode {
                    HStack(spacing: 6) {
                        Image(systemName: "battery.50percent")
                            .foregroundStyle(.yellow)
                        Text("System Low Power Mode is currently active.")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Throttles 3D model frame rate to 30 FPS and pauses idle rendering", systemImage: "checkmark.circle.fill")
                    Label("Pauses automatic home carousel scrolling", systemImage: "checkmark.circle.fill")
                    Label("Caches news feeds to minimize cellular & Wi-Fi antenna wakeups", systemImage: "checkmark.circle.fill")
                    Label("Throttles background Apple Watch Bluetooth file transfers", systemImage: "checkmark.circle.fill")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var statusIndicatorColor: Color {
        if syncManager.isSyncing { return .blue }
        if !syncManager.isConfigured { return .secondary }
        return .green
    }

    private var statusSubtitle: String {
        if syncManager.isSyncing {
            return "Syncing with cloud vault..."
        }
        if let last = syncManager.lastSyncDate {
            return "Last synced: \(formattedDate(last)) · Device: \(syncManager.deviceName)"
        }
        return "Tap below to select a sync folder"
    }

    // MARK: - 操作快捷区 (Quick Actions)
    private var syncActionsSection: some View {
        VStack(spacing: 12) {
            if syncManager.isConfigured {
                // 立即同步按钮
                Button {
                    Task {
                        await syncManager.syncNow(trigger: "Manual Sync")
                    }
                } label: {
                    HStack(spacing: 8) {
                        if syncManager.isSyncing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.body.weight(.semibold))
                        }
                        Text(syncManager.isSyncing ? "Syncing..." : "Sync Now")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(syncManager.isSyncing)

                HStack(spacing: 12) {
                    Button {
                        promptFolderPicker()
                    } label: {
                        Label("Change Folder", systemImage: "folder.badge.gearshape")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingDisconnectAlert = true
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                // 自动同步开关
                Toggle(isOn: $syncManager.autoSyncEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Background Sync")
                            .font(.subheadline.weight(.semibold))
                        Text("Sync automatically on launch and local data changes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.cyan)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 14))
            } else {
                // 尚未配置时的醒目主按钮
                Button {
                    promptFolderPicker()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.body.weight(.semibold))
                        Text("Select iCloud Drive Folder")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 数据统计
    private var statsSection: some View {
        let items = loadCollection()
        let wantedIDs = decodeIDs(from: UserDefaults.standard.data(forKey: "wantedDeviceIDs") ?? Data())
        let inUseCount = items.filter { $0.isDailyDriver }.count
        let batteryTracked = items.filter { BatteryMaintenanceManager.deviceHasRechargeableBattery($0) && !$0.batteryTrackingIgnored }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Sync Statistics")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCard(title: "Collection Items", value: "\(items.count)", icon: "square.grid.2x2.fill", color: .blue)
                statCard(title: "In-Use Devices", value: "\(inUseCount)", icon: "iphone.badge.play", color: .indigo)
                statCard(title: "Wishlist", value: "\(wantedIDs.count)", icon: "dollarsign.circle.fill", color: .orange)
                statCard(title: "Battery Tracked", value: "\(batteryTracked.count)", icon: "battery.100percent.bolt", color: .green)
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 多端配置指引 (Setup Guide)
    private var setupGuideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Multi-Device Setup Guide (No Developer Account Required)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 12) {
                guideStepRow(
                    step: "1",
                    title: "Select or Create an iCloud Folder",
                    desc: "Tap above to create or select a dedicated folder in iCloud Drive (e.g. named 'PommeVault')."
                )
                Divider().background(Color.primary.opacity(0.08))
                guideStepRow(
                    step: "2",
                    title: "Select Same Folder on Other Devices",
                    desc: "Open Pomme on your Mac, iPad, or another iPhone/Vision Pro, and choose the exact same folder."
                )
                Divider().background(Color.primary.opacity(0.08))
                guideStepRow(
                    step: "3",
                    title: "Bidirectional Incremental Merge",
                    desc: "Adding devices, updating notes, or logging battery charges on any device merges seamlessly across all devices."
                )
            }
            .padding(14)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func guideStepRow(step: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Color.cyan, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 安全与 Apple Watch 协同
    private var securityAndWatchNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .font(.body)
                    .foregroundStyle(.cyan)
                Text("Apple Watch Collaboration")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            Text("When iPhone completes cloud vault sync and merges collection updates, latest snapshots and battery health are automatically pushed to Apple Watch and complications via WatchConnectivity.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Divider().background(Color.primary.opacity(0.08))

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.body)
                    .foregroundStyle(.green)
                Text("Privacy & Security")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            Text("Vault data is stored directly in your personal iCloud Drive (PommeSync_Vault.json) without third-party servers, completely private and offline capable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 文件夹选取触发 (Cross-Platform Folder Picker)
    private func promptFolderPicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Sync Folder"
        panel.message = "Choose an iCloud Drive folder to store Pomme multi-device sync data"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                handleFolderSelection(url: url)
            }
        }
        #elseif canImport(UIKit) && !os(watchOS)
        showingFolderPicker = true
        #endif
    }

    private func handleFolderSelection(url: URL) {
        do {
            try syncManager.setSyncFolder(url: url)
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
