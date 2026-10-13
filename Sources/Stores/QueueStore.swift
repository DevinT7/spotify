import Foundation
import Observation

/// Spotify's queue is add-only and forgets songs once they play. This store keeps a permanent local trail
/// of everything queued through Tempo so any of it can be re-queued or played again.
struct QueuedEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    let track: Track
    let queuedAt: Date
    var playedAt: Date?
}

@Observable @MainActor
final class QueueStore {
    private(set) var entries: [QueuedEntry] = []          // newest first
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("queue-history.json")
    }()

    init() {
        if let d = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([QueuedEntry].self, from: d) { entries = e }
    }

    var pending: [QueuedEntry] { entries.filter { $0.playedAt == nil }.reversed() }   // oldest first = play order
    var played: [QueuedEntry] { entries.filter { $0.playedAt != nil } }
    func timesQueued(_ uri: String) -> Int { entries.filter { $0.track.uri == uri }.count }
    func isPending(_ uri: String) -> Bool { entries.contains { $0.track.uri == uri && $0.playedAt == nil } }

    func record(_ track: Track) {
        entries.insert(QueuedEntry(track: track, queuedAt: .now), at: 0)
        if entries.count > 1000 { entries.removeLast(entries.count - 1000) }
        save()
    }

    /// Called whenever the current track changes; marks the oldest matching pending entry as played.
    func noteNowPlaying(_ uri: String) {
        guard let i = entries.lastIndex(where: { $0.track.uri == uri && $0.playedAt == nil }) else { return }
        entries[i].playedAt = .now
        save()
    }

    func remove(_ id: UUID) { entries.removeAll { $0.id == id }; save() }
    func clearPlayed() { entries.removeAll { $0.playedAt != nil }; save() }

    private func save() { if let d = try? JSONEncoder().encode(entries) { try? d.write(to: url, options: .atomic) } }
}
