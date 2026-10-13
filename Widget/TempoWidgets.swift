import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TempoWidgetBundle: WidgetBundle {
    var body: some Widget { NowPlayingLiveActivity() }
}

private let green = Color(red: 0.12, green: 0.84, blue: 0.38)

struct NowPlayingProgress: View {
    let s: NowPlayingAttributes.ContentState
    var body: some View {
        if s.isPlaying {
            ProgressView(timerInterval: s.start...max(s.end, s.start.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(green)
        } else {
            ProgressView(value: s.pausedFraction).tint(green)
        }
    }
}

struct Controls: View {
    let s: NowPlayingAttributes.ContentState
    var body: some View {
        HStack(spacing: 18) {
            Button(intent: PreviousTrackIntent()) { Image(systemName: "backward.fill") }
            Button(intent: TogglePlayIntent()) { Image(systemName: s.isPlaying ? "pause.fill" : "play.fill").font(.title2) }
            Button(intent: NextTrackIntent()) { Image(systemName: "forward.fill") }
        }.buttonStyle(.plain)
    }
}

struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            let s = context.state
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform").font(.title2).foregroundStyle(.black)
                        .frame(width: 48, height: 48).background(green, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.headline).lineLimit(1)
                        Text(s.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Text("on \(s.device)").font(.caption2).foregroundStyle(green)
                    }
                    Spacer()
                    Controls(s: s)
                }
                NowPlayingProgress(s: s)
            }
            .padding(14).activityBackgroundTint(.black.opacity(0.85)).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform").foregroundStyle(green).font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(s.title).font(.headline).lineLimit(1)
                        Text(s.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.device).font(.caption2).foregroundStyle(green).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) { NowPlayingProgress(s: s); Controls(s: s) }
                }
            } compactLeading: {
                Image(systemName: "waveform").foregroundStyle(green)
            } compactTrailing: {
                Image(systemName: s.isPlaying ? "play.fill" : "pause.fill").foregroundStyle(green)
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(green)
            }
        }
    }
}
