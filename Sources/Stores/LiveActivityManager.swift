import ActivityKit
import Foundation

/// Mirrors playback into a Live Activity (Lock Screen + Dynamic Island). Local updates only, so it refreshes
/// while Tempo is running; Spotify itself is the audio source and Tempo is suspended by iOS in the background.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<NowPlayingAttributes>?
    private var last: NowPlayingAttributes.ContentState?

    func sync(track: Track?, isPlaying: Bool, progressMs: Double, device: String?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let track else { await end(); return }
        let dur = Double(max(track.durationMs, 1))
        let start = Date().addingTimeInterval(-progressMs / 1000)
        let state = NowPlayingAttributes.ContentState(
            title: track.name, artist: track.artistLine, isPlaying: isPlaying, device: device ?? "Spotify",
            start: start, end: start.addingTimeInterval(dur / 1000), pausedFraction: min(1, progressMs / dur))
        if let l = last, l.title == state.title, l.isPlaying == state.isPlaying, l.device == state.device,
           abs(l.start.timeIntervalSince(state.start)) < 3 { return }
        last = state
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(isPlaying ? dur / 1000 + 30 : 3600))
        if let activity { await activity.update(content); return }
        activity = Activity<NowPlayingAttributes>.activities.first
        if let activity { await activity.update(content); return }
        do { activity = try Activity.request(attributes: NowPlayingAttributes(), content: content, pushType: nil) }
        catch { print("TEMPO-LA start failed: \(error)") }
    }

    func end() async {
        last = nil
        for a in Activity<NowPlayingAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        activity = nil
    }
}
