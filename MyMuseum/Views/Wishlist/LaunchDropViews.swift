//
//  LaunchDropViews.swift
//  Pomme
//
//  热门单品发售与抢购日程专属界面组件 (Apple Launch Drops & Countdown UI)
//  提供倒计时看板、开售预警阶段、渠道直达与感兴趣订阅开关。
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 发售单品详情展示弹窗
struct LaunchDropDetailSheet: View {
    let drop: LaunchDropItem
    @ObservedObject var dropManager = LaunchDropManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 顶部长条封面与状态标识
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black, Color.blue.opacity(0.35), Color.purple.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 220)

                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text(drop.category)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())

                                    StatusBadge(status: drop.status)
                                }

                                Text(drop.name)
                                    .font(.title.weight(.bold))
                                    .foregroundStyle(.white)

                                Text(drop.startingPrice)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            Spacer()

                            if !drop.imageAssetName.isEmpty, imageAssetExists(drop.imageAssetName) {
                                Image(drop.imageAssetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 130, height: 160)
                                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                            }
                        }
                        .padding(20)
                    }
                    .padding(.horizontal)

                    // 核心倒计时看板
                    LaunchCountdownCard(drop: drop)
                        .padding(.horizontal)

                    // 亮点规格特色
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Highlights & Specs")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(drop.highlightSpecs, id: \.self) { spec in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                    Text(spec)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .padding(.horizontal)

                    // 官方与授权渠道直通入口
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Official Purchase Channels")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        VStack(spacing: 8) {
                            ForEach(drop.channels) { channel in
                                if let url = channel.url {
                                    Link(destination: url) {
                                        HStack(spacing: 12) {
                                            Image(systemName: channel.iconSystemName)
                                                .font(.title3)
                                                .foregroundStyle(Color.accentColor)
                                                .frame(width: 32)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(channel.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                if let subtitle = channel.subtitle {
                                                    Text(subtitle)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            Spacer()

                                            Image(systemName: "arrow.up.right.square")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(14)
                                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // 智能提醒规则说明
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(Color.orange)
                            Text("Launch Alert Protocol")
                                .font(.subheadline.weight(.semibold))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("• 1 Day Before: Head start alert to verify payment and delivery details.")
                            Text("• 30 Mins Before: Final prep alert before doors open.")
                            Text("• Star Drop: High-priority 5-minute rush alert to get in line first.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 12)
            }
            .navigationTitle(drop.name)
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLocalized("Done")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 12) {
                        Menu {
                            Button(role: .destructive) {
                                dropManager.dismissDrop(drop)
                                dismiss()
                            } label: {
                                Label(appLocalized("Hide from Drops"), systemImage: "eye.slash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }

                        Button {
                            dropManager.toggleInterested(in: drop)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: dropManager.isInterested(in: drop) ? "star.fill" : "star")
                                Text(appLocalized(dropManager.isInterested(in: drop) ? "Starred" : "Star"))
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 倒计时看板卡片
struct LaunchCountdownCard: View {
    let drop: LaunchDropItem
    @State private var now = Date()
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let (days, hours, minutes, seconds, isPast) = drop.countdownComponents(from: now)

        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(Color.accentColor)
                    Text(isPast ? "Live Now" : "Countdown to Drop")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(drop.releaseDateFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isPast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pre-orders Are Live")
                            .font(.headline.weight(.bold))
                        Text("Tap channels below to order now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 10) {
                    CountdownDigitBlock(value: days, unit: "Days")
                    Text(":").font(.title2.bold()).foregroundStyle(.secondary)
                    CountdownDigitBlock(value: hours, unit: "Hours")
                    Text(":").font(.title2.bold()).foregroundStyle(.secondary)
                    CountdownDigitBlock(value: minutes, unit: "Mins")
                    Text(":").font(.title2.bold()).foregroundStyle(.secondary)
                    CountdownDigitBlock(value: seconds, unit: "Secs")
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .task(id: isVisible) {
            guard isVisible else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, scenePhase == .active else { continue }
                now = Date()
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

// MARK: - 倒计时单格数字块
struct CountdownDigitBlock: View {
    let value: Int
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", max(0, value)))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 54, minHeight: 48)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 状态指示标签
struct StatusBadge: View {
    let status: LaunchDropStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(status.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .upcoming: return Color.blue
        case .starting: return Color.orange
        case .imminent: return Color.red
        case .live: return Color.green
        case .ended: return Color.secondary
        }
    }
}

// MARK: - 发售列表单项卡片
struct LaunchDropRowCard: View {
    let drop: LaunchDropItem
    @ObservedObject var dropManager = LaunchDropManager.shared
    var onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 14) {
                // 产品图片
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 64, height: 64)

                    if !drop.imageAssetName.isEmpty, imageAssetExists(drop.imageAssetName) {
                        Image(drop.imageAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                    } else {
                        Image(systemName: "cube.transparent")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                // 标题与发售时间
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drop.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        StatusBadge(status: drop.status)
                    }

                    Text(drop.localizedHeadline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(drop.releaseDateFormatted)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(drop.isLive ? Color.green : Color.orange)

                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(drop.startingPrice)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // 感兴趣开关按钮
                Button {
                    dropManager.toggleInterested(in: drop)
                } label: {
                    Image(systemName: dropManager.isInterested(in: drop) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(dropManager.isInterested(in: drop) ? Color.yellow : Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 36)
                        .background(dropManager.isInterested(in: drop) ? Color.yellow.opacity(0.12) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                dropManager.toggleInterested(in: drop)
            } label: {
                Label(
                    appLocalized(dropManager.isInterested(in: drop) ? "Remove Star" : "Star Drop"),
                    systemImage: dropManager.isInterested(in: drop) ? "star.slash" : "star.fill"
                )
            }

            Button(role: .destructive) {
                dropManager.dismissDrop(drop)
            } label: {
                Label(appLocalized("Hide from Drops"), systemImage: "eye.slash")
            }
        }
    }
}

// MARK: - 自定义新品录入表单
struct AddCustomDropSheet: View {
    @ObservedObject var dropManager = LaunchDropManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var headline = ""
    @State private var category = "iPhone"
    @State private var releaseDate = Date().addingTimeInterval(3600 * 5)
    @State private var price = "$ "
    @State private var specsText = ""

    private let categories = ["iPhone", "Mac", "iPad", "Watch", "AirPods", "Home", "Vision", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Product Information") {
                    TextField("Product Name (e.g. iPhone Duo)", text: $name)
                    TextField("Drop Headline (e.g. Pre-orders start tonight)", text: $headline)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) {
                            Text($0)
                        }
                    }
                    TextField("Starting Price (e.g. $1,999)", text: $price)
                }

                Section("Launch Schedule") {
                    DatePicker("Drop Time", selection: $releaseDate, in: Date()...)
                }

                Section("Key Highlights (comma separated)") {
                    TextField("e.g. A20 Pro chip, Titanium frame, Foldable display", text: $specsText)
                }
            }
            .navigationTitle("Add Custom Drop")
            .platformInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLocalized("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add & Star Drop") {
                        let specs = specsText.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "，" }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        dropManager.addCustomDrop(
                            name: name.isEmpty ? "Apple Product" : name,
                            headline: headline.isEmpty ? "Releasing Soon" : headline,
                            category: category,
                            releaseDate: releaseDate,
                            price: price.isEmpty ? "TBD" : price,
                            specs: specs.isEmpty ? ["Official Apple Product", "Premier Release"] : specs,
                            channels: [.officialStore, .appleStoreApp]
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
