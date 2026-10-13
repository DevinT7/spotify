import SwiftUI

/// Spotify's own queue is write-only and forgetful. This tab shows what's coming AND everything you've ever queued here.
struct QueueView: View {
    @Environment(AppModel.self) private var model
    @State private var showAllHistory = false

    var body: some View {
        let p = model.player
        List {
            if let t = p.track {
                Section("Now playing") { TrackRow(track: t) }
            }
            Section {
                if p.upNext.isEmpty { Text("Nothing queued. Use the + on any song.").foregroundStyle(.secondary) }
                ForEach(Array(p.upNext.prefix(30).enumerated()), id: \.offset) { _, t in TrackRow(track: t) }
            } header: { Text("Up next · Spotify") } footer: {
                Text("Spotify doesn't let apps remove or reorder its queue, but nothing here is ever lost — see History below.")
            }
            Section {
                let list = showAllHistory ? model.queue.entries : Array(model.queue.entries.prefix(25))
                if list.isEmpty { Text("Songs you queue will be remembered here.").foregroundStyle(.secondary) }
                ForEach(list) { e in
                    HStack {
                        TrackRow(track: e.track)
                    }
                    .overlay(alignment: .topTrailing) {
                        Text(e.playedAt == nil ? "UP NEXT" : relative(e.queuedAt))
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(e.playedAt == nil ? Theme.accent : .secondary)
                    }
                    .swipeActions(edge: .trailing) { Button(role: .destructive) { model.queue.remove(e.id) } label: { Label("Forget", systemImage: "trash") } }
                }
                if model.queue.entries.count > 25 && !showAllHistory { Button("Show all \(model.queue.entries.count)") { showAllHistory = true } }
            } header: {
                Text("Queue history · yours")
            }
        }
        .listStyle(.plain)
        .navigationTitle("Queue")
        .toolbar { if !model.queue.played.isEmpty { Button("Clear played") { model.queue.clearPlayed() } } }
        .refreshable { await p.refreshQueue() }
        .task { await p.refreshQueue() }
    }

    private func relative(_ d: Date) -> String { d.formatted(.relative(presentation: .named)).uppercased() }
}
