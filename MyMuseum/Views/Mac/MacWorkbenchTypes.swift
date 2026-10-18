//
//  MacWorkbenchTypes.swift
//  Pomme
//
//  Mac 策展人工作台基础枚举与类型定义
//

import SwiftUI

enum MacSidebarSelection: Hashable {
    case all
    case inUse
    case battery
    case favorites
    case dataHealth
    case category(String)
    case encyclopedia
    case wishlist
    case rumors
    case spatialMuseum
}

enum MacViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case table = "Table"
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .table: return "list.bullet"
        }
    }
}

enum MacSortOption: String, CaseIterable, Identifiable {
    case category = "Category"
    case name = "Name"
    case priceDesc = "Price: High to Low"
    case priceAsc = "Price: Low to High"
    case releaseYear = "Release Year"
    case recentlyUpdated = "Recently Updated"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .category: return isChineseLanguage ? "按类别排序" : "Category"
        case .name: return isChineseLanguage ? "按名称排序" : "Name"
        case .priceDesc: return isChineseLanguage ? "价格：由高到低" : "Price: High to Low"
        case .priceAsc: return isChineseLanguage ? "价格：由低到高" : "Price: Low to High"
        case .releaseYear: return isChineseLanguage ? "按发售年份" : "Release Year"
        case .recentlyUpdated: return isChineseLanguage ? "按最近修改" : "Recently Updated"
        }
    }
}
