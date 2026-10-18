//
//  MacSingleItemInspectorView.swift
//  Pomme
//
//  全新苹果风格实时检查器，支持原位编辑与自由归档录入 (Mac Curator Workbench Inspector)
//

import SwiftUI

struct MacSingleItemInspectorView: View {
    let item: CollectionItem
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onToggleDailyDriver: () -> Void
    let onUpdate: (CollectionItem) -> Void
    let onDelete: (String) -> Void
    let onQuickLook: () -> Void
    
    @State private var isEditing = false
    @State private var draftItem: CollectionItem = CollectionItem(id: "", name: "", category: "")
    @State private var copiedSN = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Group {
            if isEditing {
                MacItemInlineEditorView(
                    draftItem: $draftItem,
                    onSave: {
                        onUpdate(draftItem)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing = false
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing = false
                        }
                    }
                )
            } else {
                inspectorReadOnlyView
            }
        }
        .compositingGroup()
        .onAppear {
            draftItem = item
        }
        .onChange(of: item.id) { _ in
            draftItem = item
            isEditing = false
        }
    }
    
    // MARK: - 只读浏览态
    private var inspectorReadOnlyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. 顶部 Hero 展示展台
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(0.015),
                                    Color.primary.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 195)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    
                    // 居中硬件主图
                    Image(item.artworkAssetName)
                        .resizable()
                        .scaledToFit()
                        .padding((isAirPodsMax2Device(item) || isPowerbeatsProGlacierDevice(item)) ? 0 : 18)
                        .frame(maxWidth: .infinity, maxHeight: 195)
                        .scaleEffect((isAirPodsMax2Device(item) || isPowerbeatsProGlacierDevice(item)) ? 1.5 : 1.0)
                        .clipped()
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.10), radius: 10, y: 5)
                    
                    // 左上角品类胶囊
                    HStack(spacing: 4) {
                        Image(systemName: categorySymbol(item.category))
                            .font(.system(size: 10))
                        Text(itemRootCategory(item))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
                    
                    // 右上角浮动磨砂玻璃操作栏
                    HStack(spacing: 8) {
                        // Quick Look
                        Button(action: onQuickLook) {
                            Image(systemName: "eye")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help(isChineseLanguage ? "快速大图预览 (空格)" : "Quick Look (Space)")
                        
                        // Daily Driver
                        Button(action: onToggleDailyDriver) {
                            Image(systemName: item.isDailyDriver ? "bolt.badge.clock.fill" : "bolt.badge.clock")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(item.isDailyDriver ? .green : .secondary)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(item.isDailyDriver ? Color.green.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help(isChineseLanguage ? "设为/取消主力在用设备" : "Toggle Daily Driver")
                        
                        // Favorite
                        Button(action: onToggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isFavorite ? .yellow : .secondary)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(isFavorite ? Color.yellow.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .help(isChineseLanguage ? "加入/取消星标喜欢" : "Toggle Favorite")
                        
                        // Category Cover
                        Menu {
                            let tiers = categoryHierarchyTiers(name: item.name, category: item.category)
                            CategoryCoverMenuContent(artworkAssetName: item.artworkAssetName, tiers: tiers)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help(isChineseLanguage ? "设为分类主图" : "Set as Category Cover")
                    }
                    .padding(10)
                }
                
                // 2. 标题与型号信息头
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 6) {
                        Text(item.resolvedProductName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if let model = item.model, !model.isEmpty {
                            Text(model)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }
                    
                    // 官方标准配色标签行（点击即时切换颜色与渲染图并自动保存）
                    let officialColors = officialColorOptions(for: item)
                    if !officialColors.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(officialColors, id: \.self) { opt in
                                    let isSelected = (item.color == opt || deviceColorToken(item.color) == deviceColorToken(opt))
                                    Button {
                                        var updated = item
                                        updated.color = opt
                                        onUpdate(updated)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(colorSwatch(opt))
                                                .frame(width: 9, height: 9)
                                                .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
                                            Text(deviceColorLabel(opt))
                                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4.5)
                                        .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04)))
                                        .overlay(Capsule().stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.4 : 0.8))
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(isChineseLanguage ? "切换并保存此配色" : "Switch to this color")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } else if let col = item.color, !col.isEmpty {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(colorSwatch(col))
                                .frame(width: 8, height: 8)
                            Text(deviceColorLabel(col))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04), in: Capsule())
                    }
                }
                
                // 3. 序列号卡片 (带复制反馈)
                if let sn = item.serialNumber, !sn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(isChineseLanguage ? "机身序列号" : "SERIAL NUMBER")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(sn)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        
                        Spacer()
                        
                        Button {
                            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(sn, forType: .string)
                            #elseif canImport(UIKit)
                            UIPasteboard.general.string = sn
                            #endif
                            
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                copiedSN = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation { copiedSN = false }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedSN ? "checkmark" : "doc.on.doc")
                                Text(copiedSN ? (isChineseLanguage ? "已复制" : "Copied") : (isChineseLanguage ? "复制" : "Copy"))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(copiedSN ? .green : .primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(copiedSN ? Color.green.opacity(0.12) : Color.primary.opacity(0.05), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(macCardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                
                // 4. 硬件规格卡片 (系统信息级双列布局，使用英文标签规范，支持 Model Number、Model Identifier、Internal Model)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "cpu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text(isChineseLanguage ? "硬件配置与规格" : "HARDWARE SPECIFICATIONS")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        inspectorAppleSpecTile(icon: "cpu", title: "CPU", value: item.processor ?? "-")
                        inspectorAppleSpecTile(icon: "memorychip", title: "Memory", value: item.memory ?? "-")
                        inspectorAppleSpecTile(icon: "internaldrive", title: "Storage", value: item.storage ?? "-")
                        inspectorAppleSpecTile(icon: "display", title: "Display", value: item.screenSize ?? "-")
                        inspectorAppleSpecTile(icon: "calendar", title: "Release Year", value: item.releaseYear ?? "-")
                        inspectorAppleSpecTile(icon: "number.square", title: "Model Number", value: item.model ?? "-")
                        inspectorAppleSpecTile(icon: "macbook.and.iphone", title: "Model Identifier", value: item.productIdentifier ?? "-")
                        inspectorAppleSpecTile(icon: "tag", title: "Internal Model", value: item.modelVersion ?? "-")
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(macCardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                
                // 5. 资产归档与成色 (清爽只读卡片，去除预设标签干扰)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "banknote")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(isChineseLanguage ? "资产归档与成色" : "ACQUISITION DOSSIER")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    
                    VStack(spacing: 8) {
                        inspectorDossierRow(
                            title: isChineseLanguage ? "购入价格" : "Purchase Price",
                            value: (item.price?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? "¥ \(item.price!)" : (isChineseLanguage ? "未录入" : "Not recorded"),
                            isHighlight: item.price?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        )
                        Divider()
                        inspectorDossierRow(
                            title: isChineseLanguage ? "入手渠道" : "Source Channel",
                            value: (item.purchaseSource?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? item.purchaseSource! : (isChineseLanguage ? "未录入" : "Not recorded"),
                            isHighlight: false
                        )
                        Divider()
                        inspectorDossierRow(
                            title: isChineseLanguage ? "成色与保存备注" : "Condition & Notes",
                            value: (item.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? item.notes! : (isChineseLanguage ? "未录入" : "Not recorded"),
                            isHighlight: false
                        )
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(macCardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                
                // 6. 电池快速巡检卡片
                if BatteryMaintenanceManager.deviceHasRechargeableBattery(item) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "battery.100.bolt")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.teal)
                            Text(isChineseLanguage ? "电池养护状态" : "BATTERY MAINTENANCE")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                        
                        let curCycle = BatteryMaintenanceManager.cycleDays(for: item)
                        let elapsed = BatteryMaintenanceManager.daysSinceLastCharged(item) ?? 0
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isChineseLanguage ? "距离上次养护 \(elapsed) 天" : "\(elapsed) days since check")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(isChineseLanguage ? "健康巡检周期：每 \(curCycle) 天" : "Target cycle: \(curCycle) days")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(isChineseLanguage ? "记录巡检 (≥70%)" : "Log Check (≥70%)") {
                                BatteryMaintenanceManager.logNoChargeNeeded(for: item) { onUpdate($0) }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.teal.opacity(0.15), in: Capsule())
                            .foregroundStyle(.teal)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(macCardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                
                // 7. 底部操作按钮 (点击直接在原界面就地编辑，不再弹窗)
                VStack(spacing: 10) {
                    Button {
                        draftItem = item
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.line")
                            Text(isChineseLanguage ? "编辑全套硬件规格与资产参数..." : "Edit Complete Specs & Info...")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    
                    Button(role: .destructive) {
                        onDelete(item.id)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text(isChineseLanguage ? "从藏品馆中移除此设备" : "Delete from Collection")
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - 辅助组件
    private func inspectorAppleSpecTile(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue.opacity(0.85))
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(9)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.05), lineWidth: 0.8))
    }
    
    private func inspectorDossierRow(title: String, value: String, isHighlight: Bool) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: isHighlight ? .semibold : .regular, design: isHighlight ? .rounded : .default))
                .foregroundStyle(isHighlight ? Color.primary : (value == "未录入" || value == "Not recorded" ? Color.secondary.opacity(0.6) : Color.primary))
                .multilineTextAlignment(.trailing)
        }
    }
}
