//
//  CuratorCatalogPDFExporter.swift
//  Pomme
//
//  策展人藏品清单与资产估值 PDF 导出引擎
//  采用原生底层 CoreGraphics + CoreText 双向适配渲染，杜绝任何平台倒转与字符模糊问题。
//  支持生成带图、带价、带规格与序列号的高清多页专业资产盘点画册。
//

import Foundation
import CoreGraphics
import CoreText
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#endif

final class CuratorCatalogPDFExporter {
    
    struct SummaryStats {
        let totalItems: Int
        let totalValuation: Double
        let pricedItemsCount: Int
        let inUseCount: Int
        let categoriesCount: [String: Int]
    }
    
    static func computeStats(for items: [CollectionItem]) -> SummaryStats {
        var totalVal: Double = 0
        var pricedCount = 0
        var inUse = 0
        var catCounts: [String: Int] = [:]
        
        for item in items {
            let p = parsePrice(item.price)
            if p > 0 {
                totalVal += p
                pricedCount += 1
            }
            if item.isDailyDriver { inUse += 1 }
            let cat = itemRootCategory(item)
            catCounts[cat, default: 0] += 1
        }
        
        return SummaryStats(
            totalItems: items.count,
            totalValuation: totalVal,
            pricedItemsCount: pricedCount,
            inUseCount: inUse,
            categoriesCount: catCounts
        )
    }
    
    static func parsePrice(_ priceStr: String?) -> Double {
        guard let s = priceStr?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return 0 }
        let cleaned = s.replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0
    }
    
    /// 将以页面左上角为原点的坐标 (top-down) 转换为 PDF 规范底层坐标 (bottom-up)
    private static func bottomUp(_ rect: CGRect, pageHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: pageHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    /// 生成符合 A4 标准（595.2 x 841.8 pt）的多页专业资产画册 PDF 数据
    static func generatePDF(for items: [CollectionItem], museumTitle: String) -> Data {
        let stats = computeStats(for: items)
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 @ 72 DPI
        let margin: CGFloat = 36.0
        let contentWidth = pageRect.width - margin * 2
        
        let sortedItems = items.sorted {
            let cat0 = itemRootCategory($0)
            let cat1 = itemRootCategory($1)
            if cat0 != cat1 {
                return cat0.localizedStandardCompare(cat1) == .orderedAscending
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        
        let itemsPerPage = 4
        let totalPages = max(1, Int(ceil(Double(sortedItems.count) / Double(itemsPerPage))))
        let docTitle = museumTitle.isEmpty ? "Pomme Museum Collection" : museumTitle
        
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return Data()
        }
        
        for pageIndex in 0..<totalPages {
            var mediaBox = pageRect
            context.beginPage(mediaBox: &mediaBox)
            
            // 1. 顶部 Header
            drawHeader(
                context: context,
                museumTitle: docTitle,
                stats: stats,
                pageIndex: pageIndex,
                totalPages: totalPages,
                pageRect: pageRect,
                margin: margin,
                contentWidth: contentWidth
            )
            
            // 2. 本页藏品卡片（2列 x 2行）
            let startIndex = pageIndex * itemsPerPage
            let endIndex = min(startIndex + itemsPerPage, sortedItems.count)
            let pageItems = Array(sortedItems[startIndex..<endIndex])
            
            let topOffset: CGFloat = (pageIndex == 0) ? 148.0 : 70.0
            let bottomOffset: CGFloat = 40.0
            let availableHeight = pageRect.height - topOffset - bottomOffset
            let cardSpacing: CGFloat = 12.0
            let cardWidth = (contentWidth - cardSpacing) / 2.0
            let cardHeight = (availableHeight - cardSpacing) / 2.0
            
            for (idx, item) in pageItems.enumerated() {
                let row = idx / 2
                let col = idx % 2
                let cardX = margin + CGFloat(col) * (cardWidth + cardSpacing)
                let cardY = topOffset + CGFloat(row) * (cardHeight + cardSpacing)
                let cardRect = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
                
                drawItemCard(context: context, item: item, in: cardRect, pageHeight: pageRect.height)
            }
            
            // 3. 页脚与页码
            drawFooter(
                context: context,
                pageIndex: pageIndex,
                totalPages: totalPages,
                pageRect: pageRect,
                margin: margin,
                contentWidth: contentWidth
            )
            
            context.endPage()
        }
        
        context.closePDF()
        return pdfData as Data
    }
    
    // MARK: - 绘制 Header
    private static func drawHeader(
        context: CGContext,
        museumTitle: String,
        stats: SummaryStats,
        pageIndex: Int,
        totalPages: Int,
        pageRect: CGRect,
        margin: CGFloat,
        contentWidth: CGFloat
    ) {
        let dateStr = Date().formatted(date: .abbreviated, time: .omitted)
        let pageHeight = pageRect.height
        
        if pageIndex == 0 {
            // 首页豪华标题头
            drawText(
                context: context,
                museumTitle,
                in: CGRect(x: margin, y: 30, width: contentWidth - 220, height: 26),
                pageHeight: pageHeight,
                fontSize: 20,
                bold: true,
                color: CGColor(gray: 0.1, alpha: 1.0)
            )
            
            let subtitleStr = "Curator Catalog & Asset Valuation Dossier · \(dateStr)"
            drawText(
                context: context,
                subtitleStr,
                in: CGRect(x: margin, y: 56, width: contentWidth - 220, height: 16),
                pageHeight: pageHeight,
                fontSize: 10,
                bold: false,
                color: CGColor(gray: 0.45, alpha: 1.0)
            )
            
            // 右上角总价值与件数胶囊
            let valStr = String(format: "¥%.2f", stats.totalValuation)
            let badgeText = "\(stats.totalItems) Items · Total: \(valStr)"
            drawBadge(
                context: context,
                text: badgeText,
                rect: CGRect(x: margin + contentWidth - 210, y: 32, width: 210, height: 26),
                pageHeight: pageHeight,
                bgColor: CGColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1.0),
                textColor: CGColor(red: 0.08, green: 0.35, blue: 0.75, alpha: 1.0),
                fontSize: 8.5
            )
            
            // 细分统计条
            let barY: CGFloat = 84
            let barRect = CGRect(x: margin, y: barY, width: contentWidth, height: 44)
            drawStatSummaryBar(context: context, rect: barRect, stats: stats, pageHeight: pageHeight)
            
            // 分割线
            drawLine(context: context, from: CGPoint(x: margin, y: 138), to: CGPoint(x: margin + contentWidth, y: 138), pageHeight: pageHeight)
        } else {
            // 后续页轻量标题头
            drawText(
                context: context,
                "\(museumTitle) · Catalog Dossier",
                in: CGRect(x: margin, y: 26, width: contentWidth - 100, height: 16),
                pageHeight: pageHeight,
                fontSize: 11,
                bold: true,
                color: CGColor(gray: 0.2, alpha: 1.0)
            )
            
            drawText(
                context: context,
                dateStr,
                in: CGRect(x: margin + contentWidth - 100, y: 26, width: 100, height: 16),
                pageHeight: pageHeight,
                fontSize: 10,
                bold: false,
                color: CGColor(gray: 0.5, alpha: 1.0),
                alignRight: true
            )
            
            drawLine(context: context, from: CGPoint(x: margin, y: 48), to: CGPoint(x: margin + contentWidth, y: 48), pageHeight: pageHeight)
        }
    }
    
    // MARK: - 绘制统计概览条
    private static func drawStatSummaryBar(context: CGContext, rect: CGRect, stats: SummaryStats, pageHeight: CGFloat) {
        let path = CGPath(roundedRect: bottomUp(rect, pageHeight: pageHeight), cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.setFillColor(CGColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1.0))
        context.fillPath()
        
        let colW = rect.width / 4.0
        let itemsData = [
            ("TOTAL ASSETS", "\(stats.totalItems)"),
            ("TOTAL VALUATION", String(format: "¥%.0f", stats.totalValuation)),
            ("IN-USE DRIVERS", "\(stats.inUseCount)"),
            ("PRICED COVERAGE", "\(stats.pricedItemsCount) / \(stats.totalItems)")
        ]
        
        for (i, col) in itemsData.enumerated() {
            let colX = rect.minX + CGFloat(i) * colW
            drawText(
                context: context,
                col.0,
                in: CGRect(x: colX + 12, y: rect.minY + 6, width: colW - 24, height: 12),
                pageHeight: pageHeight,
                fontSize: 7.5,
                bold: true,
                color: CGColor(gray: 0.5, alpha: 1.0)
            )
            drawText(
                context: context,
                col.1,
                in: CGRect(x: colX + 12, y: rect.minY + 20, width: colW - 24, height: 16),
                pageHeight: pageHeight,
                fontSize: 12,
                bold: true,
                color: CGColor(gray: 0.12, alpha: 1.0)
            )
        }
    }
    
    // MARK: - 绘制藏品单卡
    private static func drawItemCard(context: CGContext, item: CollectionItem, in rect: CGRect, pageHeight: CGFloat) {
        // 卡片圆角外框与底色
        let cardPath = CGPath(roundedRect: bottomUp(rect, pageHeight: pageHeight), cornerWidth: 9, cornerHeight: 9, transform: nil)
        context.addPath(cardPath)
        context.setFillColor(CGColor(gray: 0.985, alpha: 1.0))
        context.fillPath()
        context.addPath(cardPath)
        context.setStrokeColor(CGColor(gray: 0.88, alpha: 1.0))
        context.setLineWidth(0.8)
        context.strokePath()
        
        let pad: CGFloat = 10.0
        let innerRect = rect.insetBy(dx: pad, dy: pad)
        let innerW = innerRect.width
        
        // 1. 上方高清产品照片展示区 (高 112 pt)
        let imgBoxHeight: CGFloat = 112.0
        let imgBoxRect = CGRect(x: innerRect.minX, y: innerRect.minY, width: innerW, height: imgBoxHeight)
        
        let imgBg = CGPath(roundedRect: bottomUp(imgBoxRect, pageHeight: pageHeight), cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(imgBg)
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fillPath()
        context.addPath(imgBg)
        context.setStrokeColor(CGColor(gray: 0.92, alpha: 1.0))
        context.setLineWidth(0.5)
        context.strokePath()
        
        // 绘制设备图片
        let imageInnerRect = imgBoxRect.insetBy(dx: 6, dy: 6)
        drawImage(context: context, assetName: item.artworkAssetName, in: imageInnerRect, pageHeight: pageHeight)
        
        // 左上角品类标签
        let catTitle = categoryTitle(item.category)
        let catBadgeW: CGFloat = CGFloat(catTitle.count) * 6.5 + 16.0
        drawBadge(
            context: context,
            text: catTitle,
            rect: CGRect(x: imgBoxRect.minX + 6, y: imgBoxRect.minY + 6, width: catBadgeW, height: 16),
            pageHeight: pageHeight,
            bgColor: CGColor(gray: 0.95, alpha: 0.9),
            textColor: CGColor(gray: 0.25, alpha: 1.0),
            fontSize: 7.2
        )
        
        // 右上角在用 (Daily Driver) 徽标
        if item.isDailyDriver {
            drawBadge(
                context: context,
                text: "⚡️ IN-USE",
                rect: CGRect(x: imgBoxRect.maxX - 56, y: imgBoxRect.minY + 6, width: 50, height: 16),
                pageHeight: pageHeight,
                bgColor: CGColor(red: 0.08, green: 0.45, blue: 0.95, alpha: 0.92),
                textColor: CGColor(gray: 1.0, alpha: 1.0),
                fontSize: 7.0
            )
        }
        
        // 2. 下方档案参数区
        var curY = imgBoxRect.maxY + 8
        
        // 产品标题
        drawText(
            context: context,
            item.displayName,
            in: CGRect(x: innerRect.minX, y: curY, width: innerW, height: 16),
            pageHeight: pageHeight,
            fontSize: 11,
            bold: true,
            color: CGColor(gray: 0.1, alpha: 1.0)
        )
        curY += 16
        
        // 型号 · 年份 · 官方配色
        var subParts: [String] = []
        if let model = item.model, !model.isEmpty { subParts.append(model) }
        if let year = item.releaseYear, !year.isEmpty { subParts.append(year) }
        if let color = item.color, !color.isEmpty { subParts.append(deviceColorLabel(color)) }
        let subText = subParts.isEmpty ? itemRootCategory(item) : subParts.joined(separator: " · ")
        drawText(
            context: context,
            subText,
            in: CGRect(x: innerRect.minX, y: curY, width: innerW, height: 12),
            pageHeight: pageHeight,
            fontSize: 8.5,
            bold: false,
            color: CGColor(gray: 0.45, alpha: 1.0)
        )
        curY += 14
        
        // 核心技术规格
        var specs: [String] = []
        if let cpu = item.processor ?? catalogProcessor(for: item), !cpu.isEmpty {
            specs.append(cpu)
        }
        if let mem = item.memory, !mem.isEmpty {
            specs.append(mem.contains("RAM") || mem.contains("GB") ? mem : "\(mem) RAM")
        }
        if let sto = item.storage, !sto.isEmpty {
            specs.append(sto.contains("SSD") || sto.contains("HD") || sto.contains("GB") || sto.contains("TB") ? sto : "\(sto) Storage")
        }
        if let scr = item.screenSize, !scr.isEmpty {
            specs.append(scr)
        }
        if let os = item.osVersion ?? item.system, !os.isEmpty {
            specs.append(os)
        }
        if let bat = item.battery, !bat.isEmpty {
            specs.append("Bat: \(bat)")
        }
        
        if !specs.isEmpty {
            let specStr = specs.joined(separator: "  |  ")
            drawText(
                context: context,
                specStr,
                in: CGRect(x: innerRect.minX, y: curY, width: innerW, height: 13),
                pageHeight: pageHeight,
                fontSize: 7.8,
                bold: false,
                color: CGColor(gray: 0.2, alpha: 1.0)
            )
            curY += 14
        }
        
        // 序列号徽章
        if let sn = item.serialNumber, !sn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drawBadge(
                context: context,
                text: "SN: \(sn)",
                rect: CGRect(x: innerRect.minX, y: curY, width: min(innerW, 165), height: 15),
                pageHeight: pageHeight,
                bgColor: CGColor(red: 0.92, green: 0.93, blue: 0.96, alpha: 1.0),
                textColor: CGColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 1.0),
                fontSize: 7.5
            )
            curY += 17
        } else {
            drawText(
                context: context,
                "SN: Unrecorded",
                in: CGRect(x: innerRect.minX, y: curY, width: innerW, height: 12),
                pageHeight: pageHeight,
                fontSize: 7.5,
                bold: false,
                color: CGColor(gray: 0.65, alpha: 1.0)
            )
            curY += 14
        }
        
        // 采购明细 (日期 · 渠道 · 保修)
        var buyParts: [String] = []
        if let date = item.purchaseDate, !date.isEmpty { buyParts.append(date) }
        if let src = item.purchaseSource, !src.isEmpty { buyParts.append(src) }
        if let war = item.warrantyStatus, !war.isEmpty { buyParts.append(war) }
        if !buyParts.isEmpty {
            drawText(
                context: context,
                buyParts.joined(separator: " · "),
                in: CGRect(x: innerRect.minX, y: curY, width: innerW, height: 11),
                pageHeight: pageHeight,
                fontSize: 7.5,
                bold: false,
                color: CGColor(gray: 0.48, alpha: 1.0)
            )
            curY += 13
        }
        
        // 估值价格与成色备注
        if let price = item.price, !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let priceVal = parsePrice(price)
            let formattedPrice = priceVal > 0 ? String(format: "¥%.2f", priceVal) : price
            drawText(
                context: context,
                formattedPrice,
                in: CGRect(x: innerRect.minX, y: curY, width: innerW, height: 15),
                pageHeight: pageHeight,
                fontSize: 11,
                bold: true,
                color: CGColor(red: 0.88, green: 0.32, blue: 0.05, alpha: 1.0)
            )
            curY += 15
        }
        
        if let notes = item.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drawText(
                context: context,
                notes,
                in: CGRect(x: innerRect.minX, y: curY, width: innerW, height: 12),
                pageHeight: pageHeight,
                fontSize: 7.2,
                bold: false,
                color: CGColor(gray: 0.5, alpha: 1.0)
            )
        }
    }
    
    // MARK: - 绘制图片
    private static func drawImage(
        context: CGContext,
        assetName: String,
        in rect: CGRect,
        pageHeight: CGFloat
    ) {
        var resolvedCGImage: CGImage?
        #if canImport(UIKit)
        if let uiImg = UIImage(named: assetName), let cg = uiImg.cgImage {
            resolvedCGImage = cg
        }
        #elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
        if let nsImg = NSImage(named: assetName) {
            var r = CGRect(origin: .zero, size: nsImg.size)
            resolvedCGImage = nsImg.cgImage(forProposedRect: &r, context: nil, hints: nil)
        }
        #endif
        
        if let cgImage = resolvedCGImage {
            let fitted = aspectFit(size: CGSize(width: cgImage.width, height: cgImage.height), in: rect)
            let imgRectBottomUp = bottomUp(fitted, pageHeight: pageHeight)
            context.draw(cgImage, in: imgRectBottomUp)
            return
        }
        
        // 默认占位方块
        let placeRect = rect.insetBy(dx: 10, dy: 10)
        let placePath = CGPath(roundedRect: bottomUp(placeRect, pageHeight: pageHeight), cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(placePath)
        context.setFillColor(CGColor(gray: 0.94, alpha: 1.0))
        context.fillPath()
    }
    
    private static func aspectFit(size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let aspect = size.width / size.height
        let targetAspect = rect.width / rect.height
        
        var fittedSize = rect.size
        if aspect > targetAspect {
            fittedSize.height = rect.width / aspect
        } else {
            fittedSize.width = rect.height * aspect
        }
        
        let originX = rect.midX - fittedSize.width / 2.0
        let originY = rect.midY - fittedSize.height / 2.0
        return CGRect(origin: CGPoint(x: originX, y: originY), size: fittedSize)
    }
    
    // MARK: - 绘制 Footer
    private static func drawFooter(
        context: CGContext,
        pageIndex: Int,
        totalPages: Int,
        pageRect: CGRect,
        margin: CGFloat,
        contentWidth: CGFloat
    ) {
        let pageHeight = pageRect.height
        let footerY = pageHeight - 24
        drawLine(context: context, from: CGPoint(x: margin, y: footerY - 8), to: CGPoint(x: margin + contentWidth, y: footerY - 8), pageHeight: pageHeight)
        
        drawText(
            context: context,
            "Pomme Museum Collection · Confidential Curator Report",
            in: CGRect(x: margin, y: footerY, width: contentWidth - 80, height: 12),
            pageHeight: pageHeight,
            fontSize: 7.5,
            bold: false,
            color: CGColor(gray: 0.6, alpha: 1.0)
        )
        
        drawText(
            context: context,
            "Page \(pageIndex + 1) of \(totalPages)",
            in: CGRect(x: margin + contentWidth - 80, y: footerY, width: 80, height: 12),
            pageHeight: pageHeight,
            fontSize: 8,
            bold: false,
            color: CGColor(gray: 0.5, alpha: 1.0),
            alignRight: true
        )
    }
    
    // MARK: - 绘图工具方法
    
    private static func makeTruncatedLine(text: String, font: CTFont, color: CGColor, maxWidth: CGFloat) -> CTLine {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if lineWidth <= maxWidth {
            return line
        }
        let ellipsisAttrStr = CFAttributedStringCreate(nil, "…" as CFString, attrs as CFDictionary)!
        let ellipsisLine = CTLineCreateWithAttributedString(ellipsisAttrStr)
        return CTLineCreateTruncatedLine(line, Double(maxWidth), .end, ellipsisLine) ?? line
    }
    
    private static func drawText(
        context: CGContext,
        _ text: String,
        in rect: CGRect,
        pageHeight: CGFloat,
        fontSize: CGFloat,
        bold: Bool,
        color: CGColor,
        alignRight: Bool = false
    ) {
        guard !text.isEmpty else { return }
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, fontSize, nil)
            ?? CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, fontSize, nil)
        
        let line = makeTruncatedLine(text: text, font: font, color: color, maxWidth: rect.width)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        
        let descent = CTFontGetDescent(font)
        let ascent = CTFontGetAscent(font)
        
        let boxBottomY = pageHeight - rect.origin.y - rect.height
        let baselineY = boxBottomY + (rect.height - ascent + descent) / 2.0 + descent
        
        let originX = alignRight ? (rect.origin.x + rect.width - lineWidth) : rect.origin.x
        context.textPosition = CGPoint(x: originX, y: baselineY)
        CTLineDraw(line, context)
    }
    
    private static func drawBadge(
        context: CGContext,
        text: String,
        rect: CGRect,
        pageHeight: CGFloat,
        bgColor: CGColor,
        textColor: CGColor,
        fontSize: CGFloat = 7.5
    ) {
        let path = CGPath(roundedRect: bottomUp(rect, pageHeight: pageHeight), cornerWidth: rect.height / 2.0, cornerHeight: rect.height / 2.0, transform: nil)
        context.addPath(path)
        context.setFillColor(bgColor)
        context.fillPath()
        
        let textRect = CGRect(x: rect.minX + 6, y: rect.origin.y, width: rect.width - 12, height: rect.height)
        drawText(
            context: context,
            text,
            in: textRect,
            pageHeight: pageHeight,
            fontSize: fontSize,
            bold: true,
            color: textColor
        )
    }
    
    private static func drawLine(
        context: CGContext,
        from: CGPoint,
        to: CGPoint,
        pageHeight: CGFloat,
        color: CGColor = CGColor(gray: 0.88, alpha: 1.0)
    ) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(0.7)
        context.move(to: CGPoint(x: from.x, y: pageHeight - from.y))
        context.addLine(to: CGPoint(x: to.x, y: pageHeight - to.y))
        context.strokePath()
        context.restoreGState()
    }
}
