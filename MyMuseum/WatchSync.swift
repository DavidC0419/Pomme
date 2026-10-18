import Foundation
#if os(iOS)
import WatchConnectivity
import UIKit
#endif

/// Sends the collection snapshot to the paired Apple Watch (iPhone only) and keeps a copy
/// in the App Group so the iPhone's own Siri intents can answer questions too.
@MainActor
final class PommeWatchBridge: NSObject {
    static let shared = PommeWatchBridge()
    private var pending: PommeSnapshot?

    func publish(_ snapshot: PommeSnapshot) {
        PommeStore.saveSnapshot(snapshot)
#if os(iOS)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        guard session.activationState == .activated else {
            pending = snapshot
            if session.activationState == .notActivated { session.activate() }
            return
        }
        send(snapshot, via: session)
#endif
    }

    private var lastFileTransferTime: Date = .distantPast

#if os(iOS)
    private func send(_ snapshot: PommeSnapshot, via session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }

        // 优先通过 updateApplicationContext 极速传输包含缩略图的最新快照（单次限制约 265KB，轻量 JPEG 轻松容纳）
        if let data = try? JSONEncoder().encode(snapshot), data.count < 240_000 {
            try? session.updateApplicationContext(["snapshot": data])
        } else {
            // 若极端情况下藏品数量极多，优先保留 Today's Exhibit 候选展品的缩略图即时投递
            var prioritizedSnapshot = snapshot
            let exhibitIDs = Set(snapshot.exhibitCandidates.prefix(25).map(\.id))
            prioritizedSnapshot.items = snapshot.items.map { item in
                var copy = item
                if !exhibitIDs.contains(item.id) {
                    copy.thumbnail = nil
                }
                return copy
            }
            if let data = try? JSONEncoder().encode(prioritizedSnapshot), data.count < 240_000 {
                try? session.updateApplicationContext(["snapshot": data])
            } else {
                var compact = snapshot
                compact.items = snapshot.items.map { var item = $0; item.thumbnail = nil; return item }
                if let data = try? JSONEncoder().encode(compact) {
                    try? session.updateApplicationContext(["snapshot": data])
                }
            }
        }

        // 功耗优化：大文件传输通过蓝牙广播能耗较高，做 60 秒限频截流，避免藏品频刷时电池狂掉
        let now = Date()
        if now.timeIntervalSince(lastFileTransferTime) > 60 {
            lastFileTransferTime = now
            session.outstandingFileTransfers.forEach { $0.cancel() }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pomme-snapshot-\(UUID().uuidString).json")
            if let data = try? JSONEncoder().encode(snapshot), (try? data.write(to: url)) != nil {
                session.transferFile(url, metadata: nil)
            }
        }
    }
#endif
}

#if os(iOS)
extension PommeWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard activationState == .activated, let pending = self.pending else { return }
            self.pending = nil
            self.send(pending, via: session)
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
