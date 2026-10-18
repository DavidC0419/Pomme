//
//  MagneticCategoryGridView.swift
//  Pomme
//
//  分类网格视图 (Category Grid View)
//  提供稳定、顺滑的原生卡片展示与轻点跳转，已移除卡片长按与晃动动效。
//  如需调整分类显示顺序，请点击各模块标题旁的“排序 (Reorder)”按钮进入专属排序面板。
//

import SwiftUI

struct MagneticCategoryGridView: View {
    let categories: [String]
    var isEncyclopedia: Bool = false
    var isEditing: Binding<Bool>? = nil
    let categoryCount: (String) -> Int
    let fallbackArtwork: (String) -> String?
    let onSelect: (String) -> Void
    var onOrderChanged: (([String]) -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: appCategoryGridColumns, spacing: 14) {
            ForEach(categories, id: \.self) { category in
                CategoryCard(
                    title: categoryTitle(category),
                    count: categoryCount(category),
                    symbol: categorySymbol(category),
                    categoryKey: category,
                    fallbackArtwork: fallbackArtwork(category)
                )
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture {
                    onSelect(category)
                }
            }
        }
    }
}
