//
//  MacWorkbenchSortHelpers.swift
//  Pomme
//
//  Mac 策展人工作台排序与数据健康过滤辅助逻辑
//

import Foundation

enum MacWorkbenchSortHelpers {
    static func applyHealthFilter(_ filter: DataHealthFilter, on list: [CollectionItem]) -> [CollectionItem] {
        let snap = MacDataHealthSnapshot.analyze(items: list)
        switch filter {
        case .all:
            return list.filter {
                $0.price?.isEmpty != false || $0.serialNumber?.isEmpty != false || $0.processor?.isEmpty != false
            }
        case .missingPrice: return snap.missingPriceItems
        case .missingSN: return snap.missingSNItems
        case .missingSpecs: return snap.missingSpecsItems
        case .batteryOverdue: return snap.batteryOverdueItems
        }
    }
    
    static func sortItems(_ list: [CollectionItem], by option: MacSortOption) -> [CollectionItem] {
        switch option {
        case .category:
            return list.sorted {
                let c0 = itemRootCategory($0)
                let c1 = itemRootCategory($1)
                if c0 != c1 { return c0.localizedStandardCompare(c1) == .orderedAscending }
                let cmp = $0.displayName.localizedStandardCompare($1.displayName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                if let col0 = $0.color, let col1 = $1.color, col0 != col1 {
                    return col0.localizedStandardCompare(col1) == .orderedAscending
                }
                if let s0 = $0.serialNumber, let s1 = $1.serialNumber, s0 != s1 {
                    return s0 < s1
                }
                return $0.id < $1.id
            }
        case .name:
            return list.sorted {
                let cmp = $0.displayName.localizedStandardCompare($1.displayName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                if let col0 = $0.color, let col1 = $1.color, col0 != col1 {
                    return col0.localizedStandardCompare(col1) == .orderedAscending
                }
                if let s0 = $0.serialNumber, let s1 = $1.serialNumber, s0 != s1 {
                    return s0 < s1
                }
                return $0.id < $1.id
            }
        case .priceDesc:
            return list.sorted {
                let p0 = CuratorCatalogPDFExporter.parsePrice($0.price)
                let p1 = CuratorCatalogPDFExporter.parsePrice($1.price)
                if p0 != p1 { return p0 > p1 }
                let cmp = $0.displayName.localizedStandardCompare($1.displayName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.id < $1.id
            }
        case .priceAsc:
            return list.sorted {
                let p0 = CuratorCatalogPDFExporter.parsePrice($0.price)
                let p1 = CuratorCatalogPDFExporter.parsePrice($1.price)
                if p0 != p1 { return p0 < p1 }
                let cmp = $0.displayName.localizedStandardCompare($1.displayName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.id < $1.id
            }
        case .releaseYear:
            return list.sorted {
                let y0 = $0.releaseYear ?? ""
                let y1 = $1.releaseYear ?? ""
                if y0 != y1 { return y0 > y1 }
                let cmp = $0.displayName.localizedStandardCompare($1.displayName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.id < $1.id
            }
        case .recentlyUpdated:
            return list.sorted {
                let d0 = $0.updatedAt ?? .distantPast
                let d1 = $1.updatedAt ?? .distantPast
                if d0 != d1 { return d0 > d1 }
                return $0.id < $1.id
            }
        }
    }
}
