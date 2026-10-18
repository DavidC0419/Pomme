import SwiftUI
import WidgetKit

struct ExhibitEntry: TimelineEntry {
    let date: Date
    let item: WatchItem?
}

struct ExhibitProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExhibitEntry {
        ExhibitEntry(date: Date(), item: WatchItem(id: "placeholder", name: "Macintosh 128K", category: "Mac", year: "1984"))
    }

    func getSnapshot(in context: Context, completion: @escaping (ExhibitEntry) -> Void) {
        let item = PommeStore.loadSnapshot().exhibit()
        completion(item.map { ExhibitEntry(date: Date(), item: $0) } ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExhibitEntry>) -> Void) {
        let snapshot = PommeStore.loadSnapshot()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Today's pick now, then a fresh pick at each of the next midnights.
        let entries = (0..<3).compactMap { offset -> ExhibitEntry? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return ExhibitEntry(date: offset == 0 ? Date() : day, item: snapshot.exhibit(for: day))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct ExhibitComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ExhibitEntry

    var body: some View {
        content
            .widgetURL(entry.item.flatMap { URL(string: "pomme://item/\($0.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0.id)") })
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                thumbnail.padding(4)
            }
        case .accessoryCorner:
            thumbnail.padding(2)
                .widgetLabel(entry.item?.name ?? String(localized: "Today's Exhibit"))
        case .accessoryInline:
            Text(entry.item?.name ?? String(localized: "Today's Exhibit"))
        default:
            HStack(spacing: 8) {
                thumbnail.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.item?.name ?? String(localized: "Today's Exhibit"))
                        .font(.headline)
                        .lineLimit(2)
                    if let year = entry.item?.year {
                        Text(year).font(.caption2).foregroundStyle(.secondary)
                    } else if let cat = entry.item?.category {
                        Text(cat).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let data = entry.item?.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "applelogo")
                .resizable()
                .scaledToFit()
                .widgetAccentable()
        }
    }
}

struct TodayExhibitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayExhibit", provider: ExhibitProvider()) { entry in
            ExhibitComplicationView(entry: entry)
        }
        .configurationDisplayName("Today's Exhibit")
        .description("A different device from your collection every day.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct PommeWatchWidgets: WidgetBundle {
    var body: some Widget { TodayExhibitWidget() }
}
