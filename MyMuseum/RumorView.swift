//
//  RumorView.swift
//  Pomme
//
//  苹果新品传闻与官方新闻动态模块 (Rumors & Apple Newsroom)
//  支持 MacRumors, 9to5Mac, AppleInsider RSS 源以及 Apple Newsroom 官方新闻。
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 传闻与新闻文章数据模型
nonisolated struct RumorStory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    let link: URL
    let source: String
    let publishedAt: Date?
    let imageURL: URL?

    var isOfficial: Bool {
        source.contains("Apple") && (source.contains("Newsroom") || source == "Apple Newsroom")
    }

    var subjectTopic: String {
        let text = "\(title) \(summary)".lowercased()
        if text.contains("vision pro") || text.contains("visionpro") || text.contains("visionos") { return "Vision Pro" }
        if text.contains("iphone") { return "iPhone" }
        if text.contains("ipad") { return "iPad" }
        if text.contains("mac") || text.contains("macbook") || text.contains("imac") || text.contains("macos") { return "Mac" }
        if text.contains("homepod") || text.contains("apple tv") || text.contains("appletv") || text.contains("tvos") || text.contains("homeview") || text.contains("homekit") || text.contains("smart home") || text.contains("matter") || text.contains("home") { return "Home" }
        return "Others"
    }

    var topic: String {
        if isOfficial { return "Newsroom" }
        return subjectTopic
    }

    var timeText: String {
        guard let publishedAt else { return source }
        let relative = publishedAt.formatted(.relative(presentation: .named))
        return "\(source) · \(relative)"
    }
}

// MARK: - RSS 订阅源定义 (含 Apple Newsroom 官方源)
nonisolated private struct RumorFeedSource: Sendable {
    let name: String
    let url: URL

    static let all = [
        RumorFeedSource(name: "Apple Newsroom", url: URL(string: "https://www.apple.com/newsroom/rss-feed.rss")!),
        RumorFeedSource(name: "MacRumors", url: URL(string: "https://feeds.macrumors.com/MacRumors-All")!),
        RumorFeedSource(name: "9to5Mac", url: URL(string: "https://9to5mac.com/feed/")!),
        RumorFeedSource(name: "AppleInsider", url: URL(string: "https://appleinsider.com/rss/news")!)
    ]
}

// MARK: - 传闻 Feed 数据加载器
@MainActor
private final class RumorFeedModel: ObservableObject {
    @Published private(set) var stories: [RumorStory] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var failedSources: [String] = []
    private var lastFetchTime: Date? = nil

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        // 缓存优化：若非强制刷新，且10分钟内已成功拉取过，则直接复用缓存，避免重复唤醒基带与Wi-Fi耗电
        if !force, let last = lastFetchTime, Date().timeIntervalSince(last) < 600, !stories.isEmpty {
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 并行拉取各订阅源，避免单个源缓慢影响整体
        let results = await withTaskGroup(of: (index: Int, name: String, stories: [RumorStory]?).self) { group in
            for (index, source) in RumorFeedSource.all.enumerated() {
                group.addTask {
                    var request = URLRequest(url: source.url)
                    request.timeoutInterval = 15
                    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                    request.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
                    do {
                        let (data, _) = try await URLSession.shared.data(for: request)
                        return (index, source.name, try RumorRSSParser.parse(data, source: source.name))
                    } catch {
                        return (index, source.name, nil)
                    }
                }
            }
            var collected: [(index: Int, name: String, stories: [RumorStory]?)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.index < $1.index }
        }

        failedSources = results.filter { $0.stories == nil }.map(\.name)
        let loadedStories = results.flatMap { $0.stories ?? [] }

        guard !loadedStories.isEmpty else {
            errorMessage = String(localized: "Couldn't reach the news feeds. Check your connection and try again.")
            return
        }

        stories = Array(Dictionary(loadedStories.map { ($0.link.absoluteString, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        lastFetchTime = Date()
    }
}

// MARK: - XML/RSS 解析器
nonisolated final class RumorRSSParser: NSObject, XMLParserDelegate {
    private let source: String
    private var stories: [RumorStory] = []
    private var currentElement = ""
    private var currentText = ""
    private var title = ""
    private var summary = ""
    private var link = ""
    private var date = ""
    private var image = ""
    private var inItem = false

    private init(source: String) { self.source = source }

    static func parse(_ data: Data, source: String) throws -> [RumorStory] {
        let parserDelegate = RumorRSSParser(source: source)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = parserDelegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return parserDelegate.stories
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = (qName ?? elementName).lowercased()
        currentText = ""
        if currentElement == "item" || currentElement == "entry" {
            inItem = true
            title = ""
            summary = ""
            link = ""
            date = ""
            image = ""
        }
        let normalizedAttributes = Dictionary(attributeDict.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        if inItem, currentElement == "enclosure" || currentElement.hasSuffix("thumbnail") || currentElement.hasSuffix(":content") {
            image = normalizedAttributes["url"] ?? image
        }
        if inItem, currentElement == "link", let href = normalizedAttributes["href"] {
            let relation = normalizedAttributes["rel"]?.lowercased() ?? ""
            let type = normalizedAttributes["type"]?.lowercased() ?? ""
            if relation == "enclosure" || type.hasPrefix("image/") {
                image = href
            } else {
                link = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) { currentText += value }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = (qName ?? elementName).lowercased()
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch element {
            case "title": title = value
            case "description", "content:encoded", "content": if summary.isEmpty { summary = value }
            case "link": if link.isEmpty { link = value }
            case "pubdate", "published", "updated", "dc:date": date = value
            case "item", "entry": appendStory()
            default: break
            }
        }
        currentElement = ""
        currentText = ""
    }

    private func appendStory() {
        defer { inItem = false }
        guard !title.isEmpty, let storyURL = URL(string: link), ["http", "https"].contains(storyURL.scheme?.lowercased() ?? "") else { return }
        if image.isEmpty, let embeddedImageURL = Self.imageURL(in: summary) {
            image = embeddedImageURL
        }
        let cleanSummary = summary
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#8217;", with: "’")
            .replacingOccurrences(of: "&#8216;", with: "‘")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#8211;", with: "–")
            .replacingOccurrences(of: "&#8212;", with: "—")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmedDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
        let published = Self.isoDateFormatterWithFractionalSeconds.date(from: trimmedDate)
            ?? Self.isoDateFormatter.date(from: trimmedDate)
            ?? Self.rssDateFormatter.date(from: trimmedDate)
            ?? Self.rssAltDateFormatter.date(from: trimmedDate)
        stories.append(RumorStory(
            id: storyURL.absoluteString,
            title: title,
            summary: cleanSummary,
            link: storyURL,
            source: source,
            publishedAt: published,
            imageURL: URL(string: image)
        ))
    }

    private static let isoDateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDateFormatter = ISO8601DateFormatter()

    private static let rssDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private static let rssAltDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private static func imageURL(in html: String) -> String? {
        let pattern = #"<(?:img|source)[^>]+(?:src|data-src)=[\"']([^\"']+)[\"']"#
        guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
              let match = html[range].range(of: #"[\"']([^\"']+)[\"']"#, options: .regularExpression) else {
            return nil
        }
        let quotedValue = String(html[match])
        let urlValue = quotedValue.dropFirst().dropLast().replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: String(urlValue)), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.absoluteString
    }
}

// MARK: - 传闻主视图 (RumorView)
struct RumorView: View {
    @StateObject private var model = RumorFeedModel()
    @ObservedObject private var bookmarkManager = NewsBookmarkManager.shared
    @State private var selectedTopic = "Featured"

    // 标签分类：Featured -> Read Later -> Saved -> Newsroom -> Vision Pro -> iPhone -> iPad -> Mac -> Home -> Others
    private let topics = ["Featured", "Read Later", "Saved", "Newsroom", "Vision Pro", "iPhone", "iPad", "Mac", "Home", "Others"]

    private var visibleStories: [RumorStory] {
        let list: [RumorStory]
        if selectedTopic == "Featured" {
            list = model.stories
        } else if selectedTopic == "Read Later" {
            list = bookmarkManager.readLaterItems.map(\.asStory)
        } else if selectedTopic == "Saved" {
            list = bookmarkManager.savedItems.map(\.asStory)
        } else if selectedTopic == "Newsroom" {
            list = model.stories.filter { $0.isOfficial }
        } else if selectedTopic == "Others" {
            list = model.stories.filter { $0.subjectTopic == "Others" }
        } else {
            list = model.stories.filter { $0.subjectTopic == selectedTopic }
        }
        return list.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topicPicker
                    .padding(.vertical, 8)
                    .background(rumorGroupedBackground)

                Divider()

                storyListView
            }
            .background(rumorGroupedBackground)
            .navigationTitle("Rumors")
            .rumorInlineTitleMode()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await model.refresh(force: true)
                            bookmarkManager.loadAndPrune()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                    .accessibilityLabel("Refresh News")
                }
            }
            .navigationDestination(for: RumorStory.self) { story in
                RumorStoryDetailView(story: story)
            }
            .task {
                await model.refresh(force: false)
                bookmarkManager.loadAndPrune()
            }
            .refreshable {
                await model.refresh(force: true)
                bookmarkManager.loadAndPrune()
            }
        }
    }

    // MARK: - 单选展开标签选择器 (Single-Select Expanding Topic Bar)
    // 默认仅显示图标，点击选中后平滑展开文字标签
    private var topicPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    let isSelected = selectedTopic == topic
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selectedTopic = topic
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: topicSymbol(topic))
                                .font(.system(size: 14, weight: .medium))

                            if isSelected {
                                Text(LocalizedStringKey(topic))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .leading)),
                                        removal: .opacity
                                    ))
                            }
                        }
                        .padding(.horizontal, isSelected ? 14 : 11)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.primary : Color.primary.opacity(0.08), in: Capsule())
                        .foregroundStyle(isSelected ? rumorSystemBackground : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 新闻列表呈现
    @ViewBuilder
    private var storyListView: some View {
        if selectedTopic == "Read Later" {
            readLaterListView
        } else if selectedTopic == "Saved" {
            savedListView
        } else {
            generalFeedListView
        }
    }

    // 稍后阅读视图（15 天未读自动清理）
    @ViewBuilder
    private var readLaterListView: some View {
        if bookmarkManager.readLaterItems.isEmpty {
            ContentUnavailableView {
                Label("No Read Later Stories", systemImage: "clock")
            } description: {
                Text("Swipe left on any news article to add it here. Unread stories expire in 15 days.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.orange)
                        Text("15-Day Unread Auto-Purge: Unread articles are automatically removed after 15 days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    ForEach(bookmarkManager.readLaterItems) { item in
                        StoryRowWithActions(story: item.asStory, readLaterItem: item)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // 永久保存视图
    @ViewBuilder
    private var savedListView: some View {
        if bookmarkManager.savedItems.isEmpty {
            ContentUnavailableView {
                Label("No Saved Stories", systemImage: "bookmark")
            } description: {
                Text("Save important news and announcements here to keep them permanently across your devices.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(bookmarkManager.savedItems) { item in
                    StoryRowWithActions(
                        story: item.asStory,
                        readLaterItem: bookmarkManager.readLaterItems.first(where: { $0.id == item.id })
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // 常规新闻与传闻视图
    @ViewBuilder
    private var generalFeedListView: some View {
        if visibleStories.isEmpty && model.isLoading {
            ProgressView("Gathering Apple news…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleStories.isEmpty, let error = model.errorMessage {
            ContentUnavailableView {
                Label("News Unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Reload") { Task { await model.refresh() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if selectedTopic == "Featured", let lead = visibleStories.first {
                    ZStack(alignment: .leading) {
                        RumorLeadCard(
                            story: lead,
                            readLaterItem: bookmarkManager.readLaterItems.first(where: { $0.id == lead.id })
                        )
                        NavigationLink(value: lead) {
                            EmptyView()
                        }
                        .opacity(0)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        trailingSwipeButtons(for: lead)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        leadingSwipeButtons(for: lead)
                    }
                    .contextMenu {
                        storyContextMenu(for: lead)
                    }

                    if visibleStories.count > 1 {
                        Text("Latest Stories")
                            .font(.title2.bold())
                            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        ForEach(visibleStories.dropFirst()) { story in
                            StoryRowWithActions(
                                story: story,
                                readLaterItem: bookmarkManager.readLaterItems.first(where: { $0.id == story.id })
                            )
                        }
                    }
                } else {
                    ForEach(visibleStories) { story in
                        StoryRowWithActions(
                            story: story,
                            readLaterItem: bookmarkManager.readLaterItems.first(where: { $0.id == story.id })
                        )
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        if !model.failedSources.isEmpty, !model.stories.isEmpty {
                            Label("Couldn't load: \(model.failedSources.formatted(.list(type: .and)))", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        Text("Rumors are unconfirmed. Refer to Apple for official information. News content and copyright belong to their original publishers.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 20, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func trailingSwipeButtons(for story: RumorStory) -> some View {
        Button {
            bookmarkManager.toggleReadLater(for: story)
        } label: {
            Label(
                bookmarkManager.isReadLater(storyId: story.id) ? "Remove from Read Later" : "Add to Read Later",
                systemImage: bookmarkManager.isReadLater(storyId: story.id) ? "clock.badge.xmark" : "clock"
            )
        }
        .tint(.orange)

        Button {
            bookmarkManager.toggleSaved(for: story)
        } label: {
            Label(
                bookmarkManager.isSaved(storyId: story.id) ? "Remove from Saved" : "Save Article",
                systemImage: bookmarkManager.isSaved(storyId: story.id) ? "bookmark.slash" : "bookmark.fill"
            )
        }
        .tint(.blue)
    }

    @ViewBuilder
    private func leadingSwipeButtons(for story: RumorStory) -> some View {
        if bookmarkManager.isReadLater(storyId: story.id) {
            let isRead = bookmarkManager.readLaterItems.first(where: { $0.id == story.id })?.isRead ?? false
            Button {
                bookmarkManager.toggleReadStatus(storyId: story.id)
            } label: {
                Label(
                    isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: isRead ? "envelope.badge" : "checkmark.circle"
                )
            }
            .tint(.green)
        }
    }

    @ViewBuilder
    private func storyContextMenu(for story: RumorStory) -> some View {
        Button {
            bookmarkManager.toggleReadLater(for: story)
        } label: {
            Label(
                bookmarkManager.isReadLater(storyId: story.id) ? "Remove from Read Later" : "Add to Read Later",
                systemImage: bookmarkManager.isReadLater(storyId: story.id) ? "clock.badge.xmark" : "clock"
            )
        }

        Button {
            bookmarkManager.toggleSaved(for: story)
        } label: {
            Label(
                bookmarkManager.isSaved(storyId: story.id) ? "Remove from Saved" : "Save Article",
                systemImage: bookmarkManager.isSaved(storyId: story.id) ? "bookmark.slash" : "bookmark.fill"
            )
        }

        if bookmarkManager.isReadLater(storyId: story.id) {
            let isRead = bookmarkManager.readLaterItems.first(where: { $0.id == story.id })?.isRead ?? false
            Button {
                bookmarkManager.toggleReadStatus(storyId: story.id)
            } label: {
                Label(
                    isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: isRead ? "envelope.badge" : "checkmark.circle"
                )
            }
        }

        ShareLink(item: story.link) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func topicSymbol(_ topic: String) -> String {
        switch topic {
        case "Featured": return "star.fill"
        case "Read Later": return "clock"
        case "Saved": return "bookmark.fill"
        case "Newsroom": return "apple.logo"
        case "Vision Pro": return "vision.pro"
        case "iPhone": return "iphone"
        case "iPad": return "ipad"
        case "Mac": return "laptopcomputer"
        case "Home": return "house.fill"
        case "Others": return "ellipsis.circle"
        default: return "newspaper"
        }
    }
}

// MARK: - 包含左滑菜单与长按操作的单行封装 (StoryRowWithActions)
private struct StoryRowWithActions: View {
    let story: RumorStory
    let readLaterItem: ReadLaterStoryItem?
    @ObservedObject private var bookmarkManager = NewsBookmarkManager.shared

    var body: some View {
        ZStack(alignment: .leading) {
            RumorStoryRow(story: story, readLaterItem: readLaterItem)
            NavigationLink(value: story) {
                EmptyView()
            }
            .opacity(0)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                bookmarkManager.toggleReadLater(for: story)
            } label: {
                Label(
                    bookmarkManager.isReadLater(storyId: story.id) ? "Remove from Read Later" : "Add to Read Later",
                    systemImage: bookmarkManager.isReadLater(storyId: story.id) ? "clock.badge.xmark" : "clock"
                )
            }
            .tint(.orange)

            Button {
                bookmarkManager.toggleSaved(for: story)
            } label: {
                Label(
                    bookmarkManager.isSaved(storyId: story.id) ? "Remove from Saved" : "Save Article",
                    systemImage: bookmarkManager.isSaved(storyId: story.id) ? "bookmark.slash" : "bookmark.fill"
                )
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if bookmarkManager.isReadLater(storyId: story.id) {
                let isRead = bookmarkManager.readLaterItems.first(where: { $0.id == story.id })?.isRead ?? false
                Button {
                    bookmarkManager.toggleReadStatus(storyId: story.id)
                } label: {
                    Label(
                        isRead ? "Mark as Unread" : "Mark as Read",
                        systemImage: isRead ? "envelope.badge" : "checkmark.circle"
                    )
                }
                .tint(.green)
            }
        }
        .contextMenu {
            Button {
                bookmarkManager.toggleReadLater(for: story)
            } label: {
                Label(
                    bookmarkManager.isReadLater(storyId: story.id) ? "Remove from Read Later" : "Add to Read Later",
                    systemImage: bookmarkManager.isReadLater(storyId: story.id) ? "clock.badge.xmark" : "clock"
                )
            }

            Button {
                bookmarkManager.toggleSaved(for: story)
            } label: {
                Label(
                    bookmarkManager.isSaved(storyId: story.id) ? "Remove from Saved" : "Save Article",
                    systemImage: bookmarkManager.isSaved(storyId: story.id) ? "bookmark.slash" : "bookmark.fill"
                )
            }

            if bookmarkManager.isReadLater(storyId: story.id) {
                let isRead = bookmarkManager.readLaterItems.first(where: { $0.id == story.id })?.isRead ?? false
                Button {
                    bookmarkManager.toggleReadStatus(storyId: story.id)
                } label: {
                    Label(
                        isRead ? "Mark as Unread" : "Mark as Read",
                        systemImage: isRead ? "envelope.badge" : "checkmark.circle"
                    )
                }
            }

            ShareLink(item: story.link) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - 头条大卡片 (Rumor Lead Card)
private struct RumorLeadCard: View {
    let story: RumorStory
    var readLaterItem: ReadLaterStoryItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RumorImage(imageURL: story.imageURL, topic: story.topic)
                .frame(height: 230)
                .clipped()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if story.isOfficial {
                        Image(systemName: "apple.logo")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                        Text("APPLE NEWSROOM · OFFICIAL")
                            .font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.blue)
                    } else {
                        Text("\(story.topic.uppercased()) · FEATURED")
                            .font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.red)
                    }

                    Spacer()

                    if let rl = readLaterItem {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text(String(format: String(localized: "%dd left"), rl.remainingDays))
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(rl.remainingDays <= 3 ? .red : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((rl.remainingDays <= 3 ? Color.red : Color.orange).opacity(0.15), in: Capsule())
                    }

                    if NewsBookmarkManager.shared.isSaved(storyId: story.id) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                Text(story.title)
                    .font(.system(size: 25, weight: .bold, design: .serif))
                    .foregroundStyle(.primary).lineLimit(4).multilineTextAlignment(.leading)
                Text(story.timeText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(rumorSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - 单条新闻行 (Rumor Story Row)
private struct RumorStoryRow: View {
    let story: RumorStory
    var readLaterItem: ReadLaterStoryItem? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    if story.isOfficial {
                        Image(systemName: "apple.logo")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                        Text("NEWSROOM · OFFICIAL")
                            .font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.blue)
                    } else {
                        Text("\(story.topic.uppercased()) · \(story.source.uppercased())")
                            .font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.red)
                    }

                    Spacer(minLength: 4)

                    if let rl = readLaterItem {
                        if rl.isRead {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark")
                                Text("Read")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        } else {
                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                Text(String(format: String(localized: "%dd left"), rl.remainingDays))
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(rl.remainingDays <= 3 ? .red : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((rl.remainingDays <= 3 ? Color.red : Color.orange).opacity(0.15), in: Capsule())
                        }
                    }

                    if NewsBookmarkManager.shared.isSaved(storyId: story.id) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }

                Text(story.title)
                    .font(.headline).foregroundStyle(.primary).lineLimit(3).multilineTextAlignment(.leading)

                Text(story.timeText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            RumorImage(imageURL: story.imageURL, topic: story.topic)
                .frame(width: 112, height: 90).clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

// MARK: - 新闻配图 (Rumor Image)
private struct RumorImage: View {
    let imageURL: URL?
    let topic: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.15, green: 0.21, blue: 0.31), Color(red: 0.36, green: 0.18, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: topicSymbol)
                .font(.system(size: 54, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.76))
        }
        .overlay {
            if let imageURL {
                GeometryReader { geometry in
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private var topicSymbol: String {
        switch topic {
        case "iPhone": return "iphone"
        case "Mac": return "laptopcomputer"
        case "iPad": return "ipad"
        case "Vision Pro": return "vision.pro"
        case "Newsroom": return "apple.logo"
        case "Home": return "house.fill"
        case "Read Later": return "clock"
        case "Saved": return "bookmark.fill"
        case "Others": return "ellipsis.circle"
        default: return "newspaper"
        }
    }
}

// MARK: - 传闻详情页面 (Rumor Story Detail View)
private struct RumorStoryDetailView: View {
    let story: RumorStory
    @ObservedObject private var bookmarkManager = NewsBookmarkManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RumorImage(imageURL: story.imageURL, topic: story.topic)
                    .frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 18))
                HStack(spacing: 6) {
                    if story.isOfficial {
                        Image(systemName: "apple.logo")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                        Text("APPLE NEWSROOM · OFFICIAL PRESS RELEASE")
                            .font(.caption.weight(.bold)).tracking(1).foregroundStyle(.blue)
                    } else {
                        Text("\(story.topic.uppercased())  /  \(story.source.uppercased())")
                            .font(.caption.weight(.bold)).tracking(1).foregroundStyle(.red)
                    }

                    Spacer()

                    if let rl = bookmarkManager.readLaterItems.first(where: { $0.id == story.id }) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(String(format: String(localized: "%dd left"), rl.remainingDays))
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(rl.remainingDays <= 3 ? .red : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((rl.remainingDays <= 3 ? Color.red : Color.orange).opacity(0.15), in: Capsule())
                    }
                }
                Text(story.title)
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                Text(story.timeText).font(.subheadline).foregroundStyle(.secondary)
                Divider()
                Text(story.summary.isEmpty ? String(localized: "No summary available. Tap the button below to read the full story on the publisher's site.") : story.summary)
                    .font(.body).lineSpacing(6).textSelection(.enabled)

                // 快捷操作按钮行：稍后阅读与永久保存
                HStack(spacing: 12) {
                    Button {
                        bookmarkManager.toggleReadLater(for: story)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: bookmarkManager.isReadLater(storyId: story.id) ? "clock.badge.xmark" : "clock")
                            Text(bookmarkManager.isReadLater(storyId: story.id) ? LocalizedStringKey("Remove from Read Later") : LocalizedStringKey("Add to Read Later"))
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button {
                        bookmarkManager.toggleSaved(for: story)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: bookmarkManager.isSaved(storyId: story.id) ? "bookmark.slash" : "bookmark.fill")
                            Text(bookmarkManager.isSaved(storyId: story.id) ? LocalizedStringKey("Remove from Saved") : LocalizedStringKey("Save Article"))
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }

                Link(destination: story.link) {
                    Label(story.isOfficial ? "Read on Apple Newsroom" : "Read Original · \(story.source)", systemImage: "arrow.up.right")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                Text(story.isOfficial ? "Official news provided directly from Apple Newsroom." : "Rumors and reports may be inaccurate. Refer to Apple for official information.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(story.isOfficial ? "Newsroom" : "Story")
        .rumorInlineTitleMode()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    bookmarkManager.toggleReadLater(for: story)
                } label: {
                    Image(systemName: bookmarkManager.isReadLater(storyId: story.id) ? "clock.fill" : "clock")
                        .foregroundStyle(bookmarkManager.isReadLater(storyId: story.id) ? .orange : .primary)
                }
                .accessibilityLabel("Read Later")

                Button {
                    bookmarkManager.toggleSaved(for: story)
                } label: {
                    Image(systemName: bookmarkManager.isSaved(storyId: story.id) ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(bookmarkManager.isSaved(storyId: story.id) ? .blue : .primary)
                }
                .accessibilityLabel("Saved")

                ShareLink(item: story.link) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            bookmarkManager.markAsRead(storyId: story.id)
        }
    }
}

private var rumorGroupedBackground: Color {
#if os(macOS)
    Color(nsColor: .windowBackgroundColor)
#else
    Color(uiColor: .systemGroupedBackground)
#endif
}

private var rumorSecondaryGroupedBackground: Color {
#if os(macOS)
    Color(nsColor: .controlBackgroundColor)
#else
    Color(uiColor: .secondarySystemGroupedBackground)
#endif
}

private var rumorSystemBackground: Color {
#if os(macOS)
    Color(nsColor: .windowBackgroundColor)
#else
    Color(uiColor: .systemBackground)
#endif
}

private extension View {
    @ViewBuilder
    func rumorInlineTitleMode() -> some View {
#if os(macOS)
        self
#else
        self.navigationBarTitleDisplayMode(.inline)
#endif
    }
}
