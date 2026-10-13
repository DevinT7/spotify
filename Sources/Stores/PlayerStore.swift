import Foundation
import Observation
import UIKit

@Observable @MainActor
final class PlayerStore {
    let api: SpotifyAPI
    let queueStore: QueueStore
    let toast: ToastCenter

    var state: PlaybackState?
    var progressMs: Double = 0
    var upNext: [Track] = []
    var devices: [Device] = []
    var liked: [String: Bool] = [:]
    var isScrubbing = false
    private var lastSync = Date()
    private var lastTrackURI: String?
    private var running = false

    init(api: SpotifyAPI, queueStore: QueueStore, toast: ToastCenter) {
        self.api = api; self.queueStore = queueStore; self.toast = toast
        PlaybackBridge.handler = { [weak self] cmd in
            switch cmd { case .toggle: self?.togglePlay(); case .next: self?.next(); case .previous: self?.previous() }
        }
    }

    var track: Track? { state?.item }
    var isPlaying: Bool { state?.isPlaying ?? false }
    var shuffleOn: Bool { state?.shuffleState ?? false }
    var repeatState: String { state?.repeatState ?? "off" }
    var volume: Int { state?.device?.volumePercent ?? 50 }
    var deviceName: String? { state?.device?.name }

    // MARK: sync loop
    func start() {
        guard !running else { return }
        running = true
        Task { while running { await refresh(); try? await Task.sleep(for: .seconds(4)) } }
        Task {
            while running {
                try? await Task.sleep(for: .milliseconds(500))
                if isPlaying, !isScrubbing, let d = track?.durationMs { progressMs = min(Double(d), progressMs + 500) }
            }
        }
    }
    func stop() { running = false }

    func refresh() async {
        do {
            let s = try await api.playbackState()
            state = s
            if !isScrubbing { progressMs = Double(s?.progressMs ?? 0) }
            lastSync = .now
            await LiveActivityManager.shared.sync(track: s?.item, isPlaying: s?.isPlaying ?? false, progressMs: progressMs, device: s?.device?.name)
            if let uri = s?.item?.uri, uri != lastTrackURI {
                lastTrackURI = uri
                queueStore.noteNowPlaying(uri)
                await loadLike(uri)
                await refreshQueue()
            }
        } catch SpotifyError.noActiveDevice { state = nil } catch {}
    }

    func refreshQueue() async { upNext = (try? await api.queue())?.queue ?? upNext }
    func refreshDevices() async { devices = (try? await api.devices()) ?? [] }

    // MARK: actions
    /// Runs a player command; if nothing is active, wakes the best device and retries once.
    private func perform(_ op: @escaping () async throws -> Void) async {
        do { try await op() } catch SpotifyError.noActiveDevice {
            await refreshDevices()
            guard let d = devices.first(where: { $0.type == "Smartphone" }) ?? devices.first(where: { $0.type == "Computer" }) ?? devices.first,
                  let id = d.spotifyID else { toast.show("Open Spotify on a device first", icon: "exclamationmark.triangle.fill", error: true); return }
            try? await api.transfer(to: id, play: false)
            try? await Task.sleep(for: .milliseconds(700))
            do { try await op() } catch { fail(error) }
        } catch { fail(error) }
        try? await Task.sleep(for: .milliseconds(350))
        await refresh()
    }
    private func fail(_ e: Error) { toast.show(e.localizedDescription, icon: "exclamationmark.triangle.fill", error: true) }
    private func haptic() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

    func play(_ t: Track, in list: [Track]? = nil, context: String? = nil) {
        haptic()
        Task {
            await perform { [api] in
                if let context { try await api.play(context: context, offsetURI: t.uri) }
                else if let list, list.count > 1 {
                    let uris = Array(list.map(\.uri).drop(while: { $0 != t.uri }).prefix(100))
                    try await api.play(uris: uris)
                } else { try await api.play(uris: [t.uri]) }
            }
        }
    }
    func playContext(_ uri: String) { Task { await perform { [api] in try await api.play(context: uri) } } }

    func togglePlay() {
        haptic()
        let playing = isPlaying
        if var s = state { s = PlaybackState(isPlaying: !playing, progressMs: s.progressMs, item: s.item, device: s.device, shuffleState: s.shuffleState, repeatState: s.repeatState); state = s }
        Task { await perform { [api] in playing ? try await api.pause() : try await api.resume() } }
    }
    func next() { haptic(); Task { await perform { [api] in try await api.next() } } }
    func previous() { haptic(); Task { await perform { [api] in try await api.previous() } } }
    func seek(to ms: Double) { progressMs = ms; Task { await perform { [api] in try await api.seek(Int(ms)) } } }
    func setVolume(_ v: Int) { Task { try? await api.volume(v) } }
    func toggleShuffle() { Task { await perform { [api, on = shuffleOn] in try await api.shuffle(!on) } } }
    func cycleRepeat() {
        let nextMode = ["off": "context", "context": "track", "track": "off"][repeatState] ?? "off"
        Task { await perform { [api] in try await api.repeatMode(nextMode) } }
    }
    func transfer(to d: Device) {
        guard let id = d.spotifyID else { return }
        Task { try? await api.transfer(to: id, play: true); await refresh(); await refreshDevices() }
    }

    /// Adds to Spotify's queue AND to Tempo's permanent queue trail.
    func enqueue(_ t: Track) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            await perform { [api] in try await api.addToQueue(uri: t.uri) }
            queueStore.record(t)
            toast.show("Added to queue · \(t.name)", icon: "text.line.last.and.arrowtriangle.forward")
            await refreshQueue()
        }
    }

    // MARK: likes
    func isLiked(_ uri: String) -> Bool { liked[uri] ?? false }
    func loadLike(_ uri: String) async { if let r = await api.isSaved([uri]).first { liked[uri] = r } }
    func toggleLike(_ t: Track) {
        let now = !isLiked(t.uri)
        liked[t.uri] = now
        Task {
            do { now ? try await api.save(t.uri) : try await api.unsave(t.uri)
                toast.show(now ? "Added to Liked Songs" : "Removed from Liked Songs", icon: now ? "heart.fill" : "heart.slash")
            } catch { liked[t.uri] = !now; fail(error) }
        }
    }
}
