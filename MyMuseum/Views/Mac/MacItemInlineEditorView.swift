//
//  MacItemInlineEditorView.swift
//  Pomme
//
//  Mac 策展人工作台单品原位编辑器 (In-place Editor, 流畅上下滑动，无弹窗)
//

import SwiftUI

struct MacItemInlineEditorView: View {
    @Binding var draftItem: CollectionItem
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部保存/取消状态条
            HStack {
                Button(isChineseLanguage ? "取消" : "Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(isChineseLanguage ? "编辑规格与资产信息" : "Edit Specifications")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button(isChineseLanguage ? "完成" : "Done") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // 0. 实时硬件外观与配色联动展台 (跟随所选配色即时变换真机渲染图)
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.primary.opacity(0.015), Color.primary.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 160)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        
                        Image(draftItem.artworkAssetName)
                            .resizable()
                            .scaledToFit()
                            .padding((isAirPodsMax2Device(draftItem) || isPowerbeatsProGlacierDevice(draftItem)) ? 0 : 14)
                            .frame(maxWidth: .infinity, maxHeight: 160)
                            .scaleEffect((isAirPodsMax2Device(draftItem) || isPowerbeatsProGlacierDevice(draftItem)) ? 1.5 : 1.0)
                            .clipped()
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 8, y: 4)
                            .id(draftItem.artworkAssetName)
                            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: draftItem.artworkAssetName)
                        
                        if let col = draftItem.color, !col.isEmpty {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(colorSwatch(col))
                                    .frame(width: 8, height: 8)
                                Text(deviceColorLabel(col))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                            .padding(10)
                        }
                    }
                    
                    // 1. 基本档案
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.blue)
                            Text(isChineseLanguage ? "基本档案" : "BASIC INFORMATION")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        
                        inspectorEditField(
                            label: isChineseLanguage ? "自定义昵称" : "Custom Name",
                            placeholder: isChineseLanguage ? "如：我的主力机、老乔黑苹果" : "e.g. My Daily Driver",
                            text: Binding(
                                get: { draftItem.customName ?? "" },
                                set: { draftItem.customName = $0 }
                            )
                        )
                        
                        inspectorEditField(
                            label: isChineseLanguage ? "官方全称" : "Product Name",
                            placeholder: isChineseLanguage ? "官方名称" : "Official product name",
                            text: Binding(
                                get: { draftItem.productName ?? draftItem.name },
                                set: { draftItem.productName = $0 }
                            )
                        )
                        
                        inspectorEditField(
                            label: isChineseLanguage ? "机身序列号 (SN)" : "Serial Number",
                            placeholder: isChineseLanguage ? "机身序列号" : "Hardware serial number",
                            text: Binding(
                                get: { draftItem.serialNumber ?? "" },
                                set: { draftItem.serialNumber = $0 }
                            )
                        )
                        
                        // 外观配色编辑（常规官方配色为快捷标签 + 自定义输入框自由录入限定色）
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(isChineseLanguage ? "外观配色" : "Color / Finish")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                if let col = draftItem.color, !col.isEmpty {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(colorSwatch(col))
                                            .frame(width: 7, height: 7)
                                        Text(deviceColorLabel(col))
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            
                            // 常规官方颜色标签选项
                            let officialColors = officialColorOptions(for: draftItem)
                            if !officialColors.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(officialColors, id: \.self) { opt in
                                            let isSelected = (draftItem.color == opt || deviceColorToken(draftItem.color) == deviceColorToken(opt))
                                            Button {
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                                    draftItem.color = opt
                                                }
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
                                                .background(
                                                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                                                )
                                                .overlay(
                                                    Capsule().stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.4 : 0.8)
                                                )
                                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            
                            // 自定义配色自由输入框（支持 Beats 限定色、联名款等任何名称）
                            TextField(
                                isChineseLanguage ? "输入配色，如：深空灰 / Siren Red / Mickey 90th" : "e.g. Space Gray, Siren Red",
                                text: Binding(
                                    get: { draftItem.color ?? "" },
                                    set: { draftItem.color = $0 }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(macCardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    
                    // 2. 硬件规格与标识符 (支持 Model Number、Model Identifier、Internal Model)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "cpu")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.indigo)
                            Text(isChineseLanguage ? "硬件配置与标识符" : "HARDWARE SPECIFICATIONS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        
                        inspectorEditField(label: "CPU", placeholder: "e.g. Apple M3 Max, A17 Pro", text: Binding(
                            get: { draftItem.processor ?? "" },
                            set: { draftItem.processor = $0 }
                        ))
                        
                        HStack(spacing: 10) {
                            inspectorEditField(label: "Memory", placeholder: "e.g. 16GB, 36GB", text: Binding(
                                get: { draftItem.memory ?? "" },
                                set: { draftItem.memory = $0 }
                            ))
                            inspectorEditField(label: "Storage", placeholder: "e.g. 512GB, 1TB SSD", text: Binding(
                                get: { draftItem.storage ?? "" },
                                set: { draftItem.storage = $0 }
                            ))
                        }
                        
                        HStack(spacing: 10) {
                            inspectorEditField(label: "Display", placeholder: "e.g. 14-inch XDR, 6.7-inch", text: Binding(
                                get: { draftItem.screenSize ?? "" },
                                set: { draftItem.screenSize = $0 }
                            ))
                            inspectorEditField(label: "Release Year", placeholder: "e.g. 2024", text: Binding(
                                get: { draftItem.releaseYear ?? "" },
                                set: { draftItem.releaseYear = $0 }
                            ))
                        }
                        
                        inspectorEditField(label: "Model Number", placeholder: "e.g. A2187, A1639, A3454", text: Binding(
                            get: { draftItem.model ?? "" },
                            set: { draftItem.model = $0 }
                        ))
                        
                        HStack(spacing: 10) {
                            inspectorEditField(label: "Model Identifier", placeholder: "e.g. Macmini2,1, Mac16,5", text: Binding(
                                get: { draftItem.productIdentifier ?? "" },
                                set: { draftItem.productIdentifier = $0 }
                            ))
                            inspectorEditField(label: "Internal Model", placeholder: "e.g. MNYF2CH/A, MX313LL/A", text: Binding(
                                get: { draftItem.modelVersion ?? "" },
                                set: { draftItem.modelVersion = $0 }
                            ))
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(macCardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    
                    // 3. 资产归档与成色 (自由输入，没有任何预设标签限制)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "banknote")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text(isChineseLanguage ? "资产归档与成色 (自由输入)" : "ACQUISITION DOSSIER")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        
                        // 购入价格
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChineseLanguage ? "购入价格" : "Purchase Price")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 4) {
                                Text("¥")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.secondary)
                                TextField(isChineseLanguage ? "输入购入金额，如 3200" : "0.00", text: Binding(
                                    get: { draftItem.price ?? "" },
                                    set: { draftItem.price = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                        
                        // 入手渠道 (用户自由输入)
                        inspectorEditField(
                            label: isChineseLanguage ? "入手渠道" : "Source Channel",
                            placeholder: isChineseLanguage ? "自由输入，如：闲鱼 / Apple Store / 拍机堂 / 朋友送的" : "e.g. Apple Store, eBay, flea market",
                            text: Binding(
                                get: { draftItem.purchaseSource ?? "" },
                                set: { draftItem.purchaseSource = $0 }
                            )
                        )
                        
                        // 成色与保存备注 (用户自由多行输入)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChineseLanguage ? "成色与保存备注" : "Condition & Notes")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            TextField(
                                isChineseLanguage ? "自由记录成色与细节，如：箱说全充新、轻微磕碰、原装电池" : "e.g. Mint in box, minor scratches",
                                text: Binding(
                                    get: { draftItem.notes ?? "" },
                                    set: { draftItem.notes = $0 }
                                ),
                                axis: .vertical
                            )
                            .lineLimit(2...5)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(macCardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    
                    // 4. 状态与养护
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "bolt.badge.clock")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                            Text(isChineseLanguage ? "使用状态与电池" : "STATUS & MAINTENANCE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        
                        Toggle(isChineseLanguage ? "日常主力在用设备 (豁免定期补电巡检)" : "Daily Driver (Exempt from periodic charging)", isOn: $draftItem.isDailyDriver)
                            .font(.system(size: 12.5))
                        
                        HStack(spacing: 10) {
                            inspectorEditField(
                                label: isChineseLanguage ? "上次保养/补电日期" : "Last Checked",
                                placeholder: "YYYY.MM.DD",
                                text: Binding(
                                    get: { draftItem.lastCharged ?? "" },
                                    set: { draftItem.lastCharged = $0 }
                                )
                            )
                            
                            inspectorEditField(
                                label: isChineseLanguage ? "巡检周期天数" : "Cycle Days",
                                placeholder: "180",
                                text: Binding(
                                    get: { draftItem.customCycleDays != nil ? "\(draftItem.customCycleDays!)" : "" },
                                    set: { draftItem.customCycleDays = Int($0) }
                                )
                            )
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(macCardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                }
                .padding(16)
            }
        }
    }
    
    private func inspectorEditField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}
