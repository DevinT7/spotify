import ActivityKit
import AppIntents
import Foundation

struct NowPlayingAttributes: ActivityAttributes {
    /// Default Codable only (required so push payloads could decode later). Keep tiny: 4KB limit.
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var device: String
        var start: Date          // when position 0 would have been, so ProgressView(timerInterval:) ticks on its own
        var end: Date
        var pausedFraction: Double
    }
    var appName: String = "Tempo"
}

enum PlaybackCommand { case toggle, next, previous }

/// The app registers a handler at launch; the widget process never runs perform().
@MainActor enum PlaybackBridge { static var handler: ((PlaybackCommand) -> Void)? }

struct TogglePlayIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play or pause"
    func perform() async throws -> some IntentResult { await MainActor.run { PlaybackBridge.handler?(.toggle) }; return .result() }
}
struct NextTrackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next track"
    func perform() async throws -> some IntentResult { await MainActor.run { PlaybackBridge.handler?(.next) }; return .result() }
}
struct PreviousTrackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous track"
    func perform() async throws -> some IntentResult { await MainActor.run { PlaybackBridge.handler?(.previous) }; return .result() }
}
