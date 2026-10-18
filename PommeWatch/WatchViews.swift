import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchSyncReceiver.self) private var sync
    @State private var path: [WatchItem] = []

    var body: some View {
        let snapshot = sync.snapshot
        NavigationStack(path: $path) {
            List {
                if let exhibit = snapshot.exhibit() {
                    Section("Today's Exhibit") {
                        NavigationLink(value: exhibit) {
                            VStack(spacing: 6) {
                                ItemThumbnail(item: exhibit, size: 76)
                                    .padding(.vertical, 4)
                                VStack(spacing: 2) {
                                    Text(exhibit.name)
                                        .font(.headline)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                    Text([exhibit.category, exhibit.year].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                    }
                    Section("At a Glance") {
                        StatRow(title: "Items", value: snapshot.items.count, symbol: "shippingbox.fill")
                        StatRow(title: "Categories", value: snapshot.categoryCount, symbol: "square.grid.2x2.fill")
                        StatRow(title: "Wishlist", value: snapshot.wishlistCount, symbol: "dollarsign.circle.fill")
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.and.arrow.forward").font(.title2)
                        Text("Open Pomme on your iPhone to sync your collection.")
                            .font(.footnote).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Pomme")
            .navigationDestination(for: WatchItem.self) { ItemCardView(item: $0) }
        }
        .onOpenURL { url in
            guard url.scheme == "pomme", url.host == "item",
                  let item = snapshot.items.first(where: { $0.id == url.lastPathComponent }) else { return }
            path = [item]
        }
    }
}

private struct StatRow: View {
    let title: LocalizedStringKey
    let value: Int
    let symbol: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text("\(value)").font(.title3.bold()).monospacedDigit()
        }
    }
}

struct ItemCardView: View {
    let item: WatchItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ItemThumbnail(item: item, size: 80).frame(maxWidth: .infinity)
                Text(item.name).font(.headline)
                CardRow(title: "Category", value: item.category)
                CardRow(title: "Year", value: item.year)
                CardRow(title: "Color", value: item.color)
                CardRow(title: "Model", value: item.model)
                CardRow(title: "Processor", value: item.processor)
                CardRow(title: "Storage", value: item.storage)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Exhibit")
    }
}

private struct CardRow: View {
    let title: LocalizedStringKey
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.footnote)
            }
        }
    }
}

struct ItemThumbnail: View {
    let item: WatchItem
    let size: CGFloat

    var body: some View {
        Group {
            if let data = item.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "applelogo").resizable().scaledToFit().padding(size * 0.2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
