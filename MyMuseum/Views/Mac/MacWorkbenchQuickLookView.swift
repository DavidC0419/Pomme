//
//  MacWorkbenchQuickLookView.swift
//  Pomme
//
//  空格键快速大图预览弹窗 (QuickLook Sheet)
//

import SwiftUI

struct MacWorkbenchQuickLookView: View {
    let item: CollectionItem
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.title2.weight(.bold))
                    Text(item.resolvedProductName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isChineseLanguage ? "关闭 (Esc)" : "Close (Esc)") {
                    onClose()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
                    .frame(height: 300)
                
                Image(item.artworkAssetName)
                    .resizable()
                    .scaledToFit()
                    .padding((isAirPodsMax2Device(item) || isPowerbeatsProGlacierDevice(item)) ? 0 : 24)
                    .scaleEffect((isAirPodsMax2Device(item) || isPowerbeatsProGlacierDevice(item)) ? 1.5 : 1.0)
                    .frame(maxHeight: 300)
                    .clipped()
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
            }
            
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Label(itemRootCategory(item), systemImage: categorySymbol(item.category))
                    if let model = item.model, !model.isEmpty {
                        Label(model, systemImage: "number")
                    }
                    if let sn = item.serialNumber, !sn.isEmpty {
                        Label(sn, systemImage: "barcode.viewfinder")
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                
                if let price = item.price, !price.isEmpty {
                    let p = CuratorCatalogPDFExporter.parsePrice(price)
                    HStack(spacing: 3) {
                        Text("¥")
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                        Text(p > 0 ? String(format: "%.2f", p) : price)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 500, minHeight: 480)
    }
}
