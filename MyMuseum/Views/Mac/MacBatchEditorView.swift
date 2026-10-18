//
//  MacBatchEditorView.swift
//  Pomme
//
//  Mac 策展人批量编辑器 (Batch Editor Inspector)
//  支持多选藏品批量打标签、设状态、改价格、调整成色渠道与批量电量巡检。
//

import SwiftUI

struct MacBatchEditorView: View {
    let selectedItems: [CollectionItem]
    @Binding var favoriteIDs: Set<String>
    let onBatchUpdate: ([CollectionItem]) -> Void
    let onBatchDelete: ([String]) -> Void
    let onClearSelection: () -> Void
    
    @State private var targetInUse: Bool? = nil
    @State private var targetFavorite: Bool? = nil
    @State private var targetPurchaseSource: String = ""
    @State private var targetConditionNote: String = ""
    @State private var targetPrice: String = ""
    @State private var applyPrice: Bool = false
    @State private var targetBatteryLevel: BatteryRemainingLevel? = nil
    @State private var showingDeleteConfirm = false
    @State private var showSuccessBanner = false
    
    private let commonSources = ["闲鱼", "拍机堂", "Apple Store 官网", "Apple 线下直营店", "淘宝", "京东", "转转", "线下二手", "亲友赠予"]
    private let commonConditions = ["箱说全 充新 (Mint)", "单机 95新 (Good)", "日常使用成色", "伊拉克/战损收藏", "已换新电池", "屏幕微瑕"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 顶部头图与选件计数
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "square.stack.3d.down.right.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text(isChineseLanguage ? "批量编辑策展" : "Batch Curator Editor")
                            .font(.title3.bold())
                        Spacer()
                        Button(isChineseLanguage ? "取消多选" : "Clear") {
                            onClearSelection()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Text(isChineseLanguage ? "已选中 \(selectedItems.count) 件藏品，修改将批量统一应用" : "\(selectedItems.count) items selected. Modifications will apply together.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
                
                // 1. 在用状态 (Daily Driver)
                MacBatchSectionCard(title: isChineseLanguage ? "在用 / 常用状态" : "Usage Status", icon: "bolt.badge.clock", iconColor: .green) {
                    HStack(spacing: 10) {
                        Button {
                            targetInUse = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: targetInUse == true ? "checkmark.circle.fill" : "circle")
                                Text(isChineseLanguage ? "设为在用主力" : "Set as Daily Driver")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(targetInUse == true ? Color.green.opacity(0.18) : Color.primary.opacity(0.04), in: Capsule())
                            .foregroundStyle(targetInUse == true ? .green : .primary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            targetInUse = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: targetInUse == false ? "archivebox.fill" : "archivebox")
                                Text(isChineseLanguage ? "设为闲置藏品" : "Set as Stored")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(targetInUse == false ? Color.orange.opacity(0.18) : Color.primary.opacity(0.04), in: Capsule())
                            .foregroundStyle(targetInUse == false ? .orange : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // 2. 喜欢星标 (Favorites)
                MacBatchSectionCard(title: isChineseLanguage ? "收藏标记" : "Favorite Status", icon: "star", iconColor: .yellow) {
                    HStack(spacing: 10) {
                        Button {
                            targetFavorite = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: targetFavorite == true ? "star.fill" : "star")
                                Text(isChineseLanguage ? "加入星标喜欢" : "Add to Favorites")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(targetFavorite == true ? Color.yellow.opacity(0.22) : Color.primary.opacity(0.04), in: Capsule())
                            .foregroundStyle(targetFavorite == true ? .yellow : .primary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            targetFavorite = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "star.slash")
                                Text(isChineseLanguage ? "取消收藏标记" : "Remove Favorites")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(targetFavorite == false ? Color.secondary.opacity(0.18) : Color.primary.opacity(0.04), in: Capsule())
                            .foregroundStyle(targetFavorite == false ? .secondary : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // 3. 购买渠道 (Purchase Source)
                MacBatchSectionCard(title: isChineseLanguage ? "采购渠道 / 来源" : "Purchase Channel", icon: "cart", iconColor: .blue) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(isChineseLanguage ? "输入或点击下方快速填充渠道" : "Enter or select purchase source", text: $targetPurchaseSource)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(commonSources, id: \.self) { src in
                                    Button(src) {
                                        targetPurchaseSource = src
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(targetPurchaseSource == src ? Color.blue.opacity(0.2) : Color.primary.opacity(0.04), in: Capsule())
                                    .foregroundStyle(targetPurchaseSource == src ? Color.blue : Color.primary)
                                }
                            }
                        }
                    }
                }
                
                // 4. 成色与保存备注 (Condition / Notes)
                MacBatchSectionCard(title: isChineseLanguage ? "成色与保存备注" : "Condition & Notes", icon: "sparkles", iconColor: .teal) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(isChineseLanguage ? "输入成色或箱说状态" : "Condition / Packaging note", text: $targetConditionNote)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(commonConditions, id: \.self) { c in
                                    Button(c) {
                                        targetConditionNote = c
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(targetConditionNote == c ? Color.teal.opacity(0.2) : Color.primary.opacity(0.04), in: Capsule())
                                    .foregroundStyle(targetConditionNote == c ? Color.teal : Color.primary)
                                }
                            }
                        }
                    }
                }
                
                // 5. 统一价格录入 (Uniform Price)
                MacBatchSectionCard(title: isChineseLanguage ? "统一设置购入价格" : "Uniform Price (Optional)", icon: "yensign.circle", iconColor: .orange) {
                    HStack(spacing: 10) {
                        Toggle(isChineseLanguage ? "修改价格" : "Update Price", isOn: $applyPrice)
                            .font(.system(size: 12))
                        
                        HStack(spacing: 3) {
                            Text("¥").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                            TextField(isChineseLanguage ? "例如 500" : "e.g. 500", text: $targetPrice)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .disabled(!applyPrice)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(applyPrice ? 0.04 : 0.02), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                }
                
                // 6. 批量电池巡检 (Batch Battery Log)
                MacBatchSectionCard(title: isChineseLanguage ? "批量电池养护记录" : "Batch Battery Maintenance", icon: "battery.100.bolt", iconColor: .teal) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChineseLanguage ? "一键对选中含锂电硬件批量完成巡检记录" : "Log maintenance inspection for selected battery devices")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            Button {
                                targetBatteryLevel = .noCharge
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "battery.75percent")
                                        .foregroundStyle(.teal)
                                    Text(isChineseLanguage ? "全部未充电 (≥70%充足)" : "No Charge (≥70%)")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(targetBatteryLevel == .noCharge ? Color.teal.opacity(0.2) : Color.primary.opacity(0.04), in: Capsule())
                                .foregroundStyle(targetBatteryLevel == .noCharge ? Color.teal : Color.primary)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                targetBatteryLevel = .from80to100
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(.green)
                                    Text(isChineseLanguage ? "已补电 100%" : "Full 100%")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(targetBatteryLevel == .from80to100 ? Color.green.opacity(0.2) : Color.primary.opacity(0.04), in: Capsule())
                                .foregroundStyle(targetBatteryLevel == .from80to100 ? Color.green : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // 7. 提交应用按钮
                Button {
                    applyBatchModifications()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(isChineseLanguage ? "应用修改至 \(selectedItems.count) 件藏品" : "Apply Changes to \(selectedItems.count) Items")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                
                // 8. 危险区：批量删除
                Divider().padding(.vertical, 2)
                
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                        Text(isChineseLanguage ? "批量删除选中的 \(selectedItems.count) 件藏品..." : "Batch Delete \(selectedItems.count) Items...")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .confirmationDialog(
            isChineseLanguage ? "确定要批量删除这 \(selectedItems.count) 件藏品吗？此操作不可逆。" : "Are you sure you want to delete \(selectedItems.count) items? This cannot be undone.",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(isChineseLanguage ? "确认删除" : "Delete", role: .destructive) {
                onBatchDelete(selectedItems.map(\.id))
                onClearSelection()
            }
            Button(isChineseLanguage ? "取消" : "Cancel", role: .cancel) { }
        }
    }
    
    private func applyBatchModifications() {
        var updatedList: [CollectionItem] = []
        let now = Date()
        
        for item in selectedItems {
            var m = item
            m.updatedAt = now
            
            // 在用
            if let inUse = targetInUse {
                m.isDailyDriver = inUse
            }
            
            // 喜欢
            if let fav = targetFavorite {
                if fav {
                    favoriteIDs.insert(m.favoriteKey)
                } else {
                    favoriteIDs.remove(m.favoriteKey)
                }
            }
            
            // 购买渠道
            if !targetPurchaseSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                m.purchaseSource = targetPurchaseSource.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // 成色
            if !targetConditionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                m.notes = targetConditionNote.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // 价格
            if applyPrice {
                m.price = targetPrice.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // 电池维护
            if let bLevel = targetBatteryLevel, BatteryMaintenanceManager.deviceHasRechargeableBattery(m) {
                BatteryMaintenanceManager.logCharge(for: m, date: now, remainingLevel: bLevel) { updated in
                    m = updated
                }
            }
            
            updatedList.append(m)
        }
        
        onBatchUpdate(updatedList)
        onClearSelection()
    }
}

// MARK: - MacBatchSectionCard (Apple Inset Card Container)
private struct MacBatchSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

