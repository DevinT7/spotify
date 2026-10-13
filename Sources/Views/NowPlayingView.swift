import SwiftUI

/// Every control is visible at once: shuffle, repeat, queue, devices, like. Nothing hides behind a "..." menu.
struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showDevices = false
    @State private var scrub: Double = 0
    @State private var volume: Double = 50

    var body: some View {
        let p = model.player
        VStack(spacing: 22) {
            Capsule().fill(.secondary).frame(width: 40, height: 5).padding(.top, 8).onTapGesture { dismiss() }
            if let t = p.track {
                Artwork(url: t.artwork, size: 320, radius: 14).shadow(radius: 20)
                    .frame(maxWidth: .infinity).padding(.top, 8)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.name).font(.title2.weight(.bold)).lineLimit(2)
                        Text(t.artistLine).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { p.toggleLike(t) } label: {
                        Image(systemName: p.isLiked(t.uri) ? "heart.fill" : "heart").font(.title)
                            .foregroundStyle(p.isLiked(t.uri) ? Theme.accent : .primary)
                    }
                    Menu { TrackMenu(track: t) } label: { Image(systemName: "ellipsis.circle").font(.title) }
                }
                VStack(spacing: 2) {
                    Slider(value: Binding(get: { p.isScrubbing ? scrub : p.progressMs }, set: { scrub = $0 }),
                           in: 0...Double(max(t.durationMs, 1))) { editing in
                        p.isScrubbing = editing
                        if !editing { p.seek(to: scrub) }
                    }
                    HStack { Text(fmt(p.isScrubbing ? scrub : p.progressMs)); Spacer(); Text(fmt(Double(t.durationMs))) }
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Button { p.toggleShuffle() } label: { Image(systemName: "shuffle").foregroundStyle(p.shuffleOn ? Theme.accent : .primary) }
                    Spacer()
                    Button { p.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                    Spacer()
                    Button { p.togglePlay() } label: { Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72)) }
                    Spacer()
                    Button { p.next() } label: { Image(systemName: "forward.fill").font(.title) }
                    Spacer()
                    Button { p.cycleRepeat() } label: {
                        Image(systemName: p.repeatState == "track" ? "repeat.1" : "repeat").foregroundStyle(p.repeatState == "off" ? Color.primary : Theme.accent)
                    }
                }.font(.title2).buttonStyle(.plain)
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...100) { e in if !e { p.setVolume(Int(volume)) } }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                HStack {
                    Button { showDevices = true } label: { Label(p.deviceName ?? "Devices", systemImage: "airplayaudio").font(.subheadline).foregroundStyle(Theme.accent) }
                    Spacer()
                    Button { showQueue = true } label: { Label("Queue", systemImage: "list.bullet").font(.subheadline) }
                    Button { model.player.enqueue(t) } label: { Label("Again", systemImage: "arrow.counterclockwise").font(.subheadline) }
                }.buttonStyle(.plain)
            } else {
                Spacer(); Text("Nothing playing").foregroundStyle(.secondary)
                Button("Choose a device") { showDevices = true }; Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { volume = Double(p.volume) }
        .sheet(isPresented: $showQueue) { NavigationStack { QueueView() }.presentationDetents([.large]) }
        .sheet(isPresented: $showDevices) { DevicesSheet().presentationDetents([.medium]) }
    }

    private func fmt(_ ms: Double) -> String {
        let s = Int(ms / 1000); return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

struct DevicesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if model.player.devices.isEmpty { Text("No devices found. Open Spotify on a phone, Mac or speaker, then pull to refresh.").foregroundStyle(.secondary) }
                ForEach(model.player.devices) { d in
                    Button { model.player.transfer(to: d); dismiss() } label: {
                        HStack { Image(systemName: d.icon).frame(width: 30); Text(d.name)
                            Spacer(); if d.isActive { Image(systemName: "waveform").foregroundStyle(Theme.accent) } }
                    }.foregroundStyle(d.isActive ? Theme.accent : .primary)
                }
            }
            .navigationTitle("Connect to a device").navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.player.refreshDevices() }
            .task { await model.player.refreshDevices() }
        }
    }
}
