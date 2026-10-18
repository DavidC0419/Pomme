//
//  NewsBookmarkManager.swift
//  Pomme
//
//  新闻稍后阅读与永久收藏管理器 (News Read Later & Permanent Bookmarks Engine)
//  支持 15 天未读自动清理、单条新闻侧滑快捷加存、多端 iCloud Drive 增量同步。
//

import Foundation
import SwiftUI
import Combine

// MARK: - 稍后阅读项数据模型 (Read Later Item)
struct ReadLaterStoryItem: Codable, Identifiable, Hashable, Sendable {
    let id: String // story URL absolute string
    let title: String
    let summary: String
    let link: URL
    let source: String
    let publishedAt: Date?
    let imageURL: URL?
    let addedAt: Date
    var isRead: Bool

    /// 是否已超过 15 天保留期（15 天未读自动删除）
    var isExpired: Bool {
        let fifteenDaysInSeconds: TimeInterval = 15 * 86400
        return !isRead && Date().timeIntervalSince(addedAt) > fifteenDaysInSeconds
    }

    /// 剩余有效天数（1~15 天）
    var remainingDays: Int {
        let fifteenDaysInSeconds: TimeInterval = 15 * 86400
        let elapsed = Date().timeIntervalSince(addedAt)
        let remaining = fifteenDaysInSeconds - elapsed
        return max(0, Int(ceil(remaining / 86400)))
    }

    var asStory: RumorStory {
        RumorStory(
            id: id,
            title: title,
            summary: summary,
            link: link,
            source: source,
            publishedAt: publishedAt,
            imageURL: imageURL
        )
    }
}

// MARK: - 永久保存文章数据模型 (Saved Article Item)
struct SavedStoryItem: Codable, Identifiable, Hashable, Sendable {
    let id: String // story URL absolute string
    let title: String
    let summary: String
    let link: URL
    let source: String
    let publishedAt: Date?
    let imageURL: URL?
    let savedAt: Date

    var asStory: RumorStory {
        RumorStory(
            id: id,
            title: title,
            summary: summary,
            link: link,
            source: source,
            publishedAt: publishedAt,
            imageURL: imageURL
        )
    }
}

// MARK: - 新闻书签与稍后阅读中心管理器 (News Bookmark Manager)
@MainActor
final class NewsBookmarkManager: ObservableObject {
    static let shared = NewsBookmarkManager()

    @Published private(set) var readLaterItems: [ReadLaterStoryItem] = []
    @Published private(set) var savedItems: [SavedStoryItem] = []

    private let readLaterStorageKey = "Pomme_ReadLaterStories_v1"
    private let savedStorageKey = "Pomme_SavedStories_v1"

    init() {
        loadAndPrune()
    }

    /// 从本地加载并自动修剪超过 15 天未读的稍后阅读条目
    func loadAndPrune() {
        if let data = UserDefaults.standard.data(forKey: readLaterStorageKey),
           let list = try? JSONDecoder().decode([ReadLaterStoryItem].self, from: data) {
            // 自动清理超过 15 天未读的文章
            let active = list.filter { !$0.isExpired }
            self.readLaterItems = active.sorted { $0.addedAt > $1.addedAt }
            if active.count != list.count {
                saveReadLater()
            }
        }

        if let data = UserDefaults.standard.data(forKey: savedStorageKey),
           let list = try? JSONDecoder().decode([SavedStoryItem].self, from: data) {
            self.savedItems = list.sorted { $0.savedAt > $1.savedAt }
        }
    }

    // MARK: - Read Later 操作
    func isReadLater(storyId: String) -> Bool {
        readLaterItems.contains { $0.id == storyId }
    }

    func toggleReadLater(for story: RumorStory) {
        if let idx = readLaterItems.firstIndex(where: { $0.id == story.id }) {
            readLaterItems.remove(at: idx)
        } else {
            let item = ReadLaterStoryItem(
                id: story.id,
                title: story.title,
                summary: story.summary,
                link: story.link,
                source: story.source,
                publishedAt: story.publishedAt,
                imageURL: story.imageURL,
                addedAt: Date(),
                isRead: false
            )
            readLaterItems.insert(item, at: 0)
        }
        saveReadLater()
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    func markAsRead(storyId: String) {
        guard let idx = readLaterItems.firstIndex(where: { $0.id == storyId }) else { return }
        if !readLaterItems[idx].isRead {
            readLaterItems[idx].isRead = true
            saveReadLater()
            CloudVaultSyncManager.shared.scheduleAutoSync()
        }
    }

    func toggleReadStatus(storyId: String) {
        guard let idx = readLaterItems.firstIndex(where: { $0.id == storyId }) else { return }
        readLaterItems[idx].isRead.toggle()
        saveReadLater()
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    func removeReadLater(storyId: String) {
        readLaterItems.removeAll { $0.id == storyId }
        saveReadLater()
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    // MARK: - 永久保存操作 (Saved / Starred)
    func isSaved(storyId: String) -> Bool {
        savedItems.contains { $0.id == storyId }
    }

    func toggleSaved(for story: RumorStory) {
        if let idx = savedItems.firstIndex(where: { $0.id == story.id }) {
            savedItems.remove(at: idx)
        } else {
            let item = SavedStoryItem(
                id: story.id,
                title: story.title,
                summary: story.summary,
                link: story.link,
                source: story.source,
                publishedAt: story.publishedAt,
                imageURL: story.imageURL,
                savedAt: Date()
            )
            savedItems.insert(item, at: 0)
        }
        saveSaved()
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    func removeSaved(storyId: String) {
        savedItems.removeAll { $0.id == storyId }
        saveSaved()
        CloudVaultSyncManager.shared.scheduleAutoSync()
    }

    // MARK: - 云端同步合并注入
    func updateFromCloud(readLater: [ReadLaterStoryItem], saved: [SavedStoryItem]) {
        // 1. 合并 Read Later
        var readLaterMap: [String: ReadLaterStoryItem] = [:]
        for item in self.readLaterItems {
            readLaterMap[item.id] = item
        }
        for item in readLater {
            if let existing = readLaterMap[item.id] {
                // 如果任一端已读，标记为已读；取较早的 addedAt
                let isRead = existing.isRead || item.isRead
                let addedAt = min(existing.addedAt, item.addedAt)
                readLaterMap[item.id] = ReadLaterStoryItem(
                    id: existing.id,
                    title: existing.title,
                    summary: existing.summary,
                    link: existing.link,
                    source: existing.source,
                    publishedAt: existing.publishedAt,
                    imageURL: existing.imageURL,
                    addedAt: addedAt,
                    isRead: isRead
                )
            } else {
                readLaterMap[item.id] = item
            }
        }
        let mergedReadLater = readLaterMap.values.filter { !$0.isExpired }.sorted { $0.addedAt > $1.addedAt }
        self.readLaterItems = mergedReadLater
        saveReadLater()

        // 2. 合并 Saved
        var savedMap: [String: SavedStoryItem] = [:]
        for item in self.savedItems {
            savedMap[item.id] = item
        }
        for item in saved {
            if let existing = savedMap[item.id] {
                let savedAt = min(existing.savedAt, item.savedAt)
                savedMap[item.id] = SavedStoryItem(
                    id: existing.id,
                    title: existing.title,
                    summary: existing.summary,
                    link: existing.link,
                    source: existing.source,
                    publishedAt: existing.publishedAt,
                    imageURL: existing.imageURL,
                    savedAt: savedAt
                )
            } else {
                savedMap[item.id] = item
            }
        }
        self.savedItems = Array(savedMap.values).sorted { $0.savedAt > $1.savedAt }
        saveSaved()
    }

    private func saveReadLater() {
        if let data = try? JSONEncoder().encode(readLaterItems) {
            UserDefaults.standard.set(data, forKey: readLaterStorageKey)
        }
    }

    private func saveSaved() {
        if let data = try? JSONEncoder().encode(savedItems) {
            UserDefaults.standard.set(data, forKey: savedStorageKey)
        }
    }
}
