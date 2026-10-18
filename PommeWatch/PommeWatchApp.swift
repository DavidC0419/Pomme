import SwiftUI
import WatchConnectivity
import WidgetKit

@main
struct PommeWatchApp: App {
    @State private var sync = WatchSyncReceiver.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(sync)
                .onAppear { sync.activate() }
        }
    }
}

/// Receives collection snapshots from the iPhone and stores them for the app and its complications.
@Observable
final class WatchSyncReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchSyncReceiver()
    private(set) var snapshot = PommeStore.loadSnapshot()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL),
              let snapshot = try? JSONDecoder().decode(PommeSnapshot.self, from: data) else { return }
        store(snapshot)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Fallback path: a compact snapshot without thumbnails.
        guard let data = applicationContext["snapshot"] as? Data,
              let incoming = try? JSONDecoder().decode(PommeSnapshot.self, from: data) else { return }
        let current = PommeStore.loadSnapshot()
        guard incoming.generatedAt > current.generatedAt else { return }
        // Keep thumbnails we already have for unchanged items.
        let thumbs = Dictionary(current.items.map { ($0.id, $0.thumbnail) }, uniquingKeysWith: { a, _ in a })
        var merged = incoming
        merged.items = incoming.items.map { var item = $0; item.thumbnail = item.thumbnail ?? thumbs[item.id] ?? nil; return item }
        store(merged)
    }

    nonisolated private func store(_ snapshot: PommeSnapshot) {
        PommeStore.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in WatchSyncReceiver.shared.snapshot = snapshot }
    }
}
