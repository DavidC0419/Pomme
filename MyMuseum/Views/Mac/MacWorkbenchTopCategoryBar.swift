//
//  MacWorkbenchTopCategoryBar.swift
//  Pomme
//
//  Mac 策展人工作台顶部多级硬件分类与小标签快速检索栏 (Hierarchical Category Navigation Bar)
//

import SwiftUI

struct MacWorkbenchTopCategoryBar: View {
    @Binding var sidebarSelection: MacSidebarSelection?
    @Binding var categoryNavRoot: String?
    @Binding var categoryNavBranch: String?
    @Binding var categoryNavFamily: String?
    @Binding var categoryNavShowAll: Bool
    let collectionItems: [CollectionItem]
    
    @ObservedObject private var coverStore = CategoryCoverStore.shared
    @Environment(\.locale) private var locale
    private var isChineseLanguage: Bool {
        locale.identifier.hasPrefix("zh") || Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }
    
    // 当前层级可点击的标签集合
    private var currentTags: [MacCategoryTagItem] {
        MacCategoryHierarchyHelper.generateTags(
            items: collectionItems,
            rootCategory: categoryNavRoot,
            branch: categoryNavBranch,
            family: categoryNavFamily,
            isShowAll: categoryNavShowAll
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. 面包屑导航指示条 (仅在进入子层级时优雅展示)
            if categoryNavRoot != nil {
                breadcrumbBar
                Divider()
                    .opacity(0.35)
                    .padding(.horizontal, 16)
            }
            
            // 2. 横向滚动芯片标签栏
            tagsScrollView
        }
        .background(macWindowBackground)
    }
    
    // MARK: - 面包屑导航条 (Breadcrumb Path)
    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            // 快速返回上一级按钮
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    goBackOneLevel()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isChineseLanguage ? "返回" : "Back")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 12)
                .padding(.horizontal, 2)
            
            // 路径：全部
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    resetToAll()
                }
            } label: {
                Text(isChineseLanguage ? "全部藏品" : "All Collection")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(categoryNavRoot == nil ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            
            if let root = categoryNavRoot {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        categoryNavBranch = nil
                        categoryNavFamily = nil
                        categoryNavShowAll = true
                    }
                } label: {
                    Text(categoryTitle(root))
                        .font(.system(size: 11, weight: categoryNavBranch == nil ? .bold : .medium))
                        .foregroundStyle(categoryNavBranch == nil ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let branch = categoryNavBranch {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        categoryNavFamily = nil
                        categoryNavShowAll = true
                    }
                } label: {
                    Text(appLocalized(branch))
                        .font(.system(size: 11, weight: categoryNavFamily == nil ? .bold : .medium))
                        .foregroundStyle(categoryNavFamily == nil ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let family = categoryNavFamily {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                
                Text(appLocalized(family))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
    
    // MARK: - 芯片滚动栏 (Tags Bar)
    private var tagsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(currentTags) { tag in
                    let isSelected = isTagSelected(tag)
                    categoryTagPill(tag: tag, isSelected: isSelected) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            handleTagTap(tag)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }
    
    // MARK: - 单个芯片 Pill (支持显示官方/自定义封面图系统)
    private func categoryTagPill(tag: MacCategoryTagItem, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // 封面图视觉系统：若已为该分类配置封面图，优先展示封面小微缩，否则展示 SF Symbol
                if let coverName = tag.coverAssetName, imageAssetExists(coverName) {
                    Image(coverName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: tag.symbol)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                
                Text(tag.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                
                // 拥有子分类指示箭头
                if tag.hasChildren {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.5))
                }
                
                // 数量胶囊角标
                Text("\(tag.count)")
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.2 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 点击交互逻辑 (Drill-down & Show All)
    private func handleTagTap(_ tag: MacCategoryTagItem) {
        if tag.isShowAll {
            if tag.key == "__ALL__" {
                resetToAll()
            } else if tag.key == "__SHOW_ALL_ROOT__" {
                categoryNavBranch = nil
                categoryNavFamily = nil
                categoryNavShowAll = true
            } else if tag.key == "__SHOW_ALL_BRANCH__" {
                categoryNavFamily = nil
                categoryNavShowAll = true
            }
            return
        }
        
        // 1. 如果处于 Root 级别，点击大类标签 (如 Mac, iPhone)
        if categoryNavRoot == nil {
            categoryNavRoot = tag.key
            categoryNavBranch = nil
            categoryNavFamily = nil
            categoryNavShowAll = true
            sidebarSelection = .category(tag.key)
            return
        }
        
        // 2. 如果处于某大类下 (如 Mac)，点击子标签
        if categoryNavRoot != nil && categoryNavBranch == nil {
            if tag.hasChildren {
                // 如 MacBook 或 Mac 台式机，下钻到 Level 2
                categoryNavBranch = tag.key
                categoryNavFamily = nil
                categoryNavShowAll = true
            } else {
                // 无下级（如 iPhone Pro），直接选中该叶子分类
                categoryNavFamily = tag.key
                categoryNavShowAll = false
            }
            return
        }
        
        // 3. 如果处于分支下 (如 Mac -> MacBook)，点击三级分类 (如 MacBook Pro)
        if categoryNavBranch != nil {
            categoryNavFamily = tag.key
            categoryNavShowAll = false
            return
        }
    }
    
    private func isTagSelected(_ tag: MacCategoryTagItem) -> Bool {
        if tag.isShowAll {
            if tag.key == "__ALL__" {
                return categoryNavRoot == nil
            }
            if tag.key == "__SHOW_ALL_ROOT__" {
                return categoryNavRoot != nil && categoryNavBranch == nil && categoryNavShowAll
            }
            if tag.key == "__SHOW_ALL_BRANCH__" {
                return categoryNavBranch != nil && categoryNavFamily == nil && categoryNavShowAll
            }
            return false
        }
        
        if categoryNavRoot == nil {
            return false
        }
        
        if categoryNavBranch == nil {
            return categoryNavFamily == tag.key || (categoryNavBranch == tag.key && !categoryNavShowAll)
        }
        
        return categoryNavFamily == tag.key
    }
    
    private func goBackOneLevel() {
        if categoryNavFamily != nil {
            categoryNavFamily = nil
            categoryNavShowAll = true
        } else if categoryNavBranch != nil {
            categoryNavBranch = nil
            categoryNavShowAll = true
        } else if categoryNavRoot != nil {
            resetToAll()
        }
    }
    
    private func resetToAll() {
        categoryNavRoot = nil
        categoryNavBranch = nil
        categoryNavFamily = nil
        categoryNavShowAll = true
        sidebarSelection = .all
    }
}
