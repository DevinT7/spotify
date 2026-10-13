import SwiftUI

struct Artwork: View {
    let url: URL?
    var size: CGFloat = 52
    var radius: CGFloat = 6
    var circle = false
    var body: some View {
        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
            Rectangle().fill(Theme.card).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: circle ? size / 2 : radius))
    }
}

/// One track row used everywhere. The trailing "+" queues the song without leaving the screen.
struct TrackRow: View {
    @Environment(AppModel.self) private var model
    let track: Track
    var list: [Track]? = nil
    var context: String? = nil
    var showArtwork = true
    @State private var pop = 0

    var body: some View {
        let isCurrent = model.player.track?.uri == track.uri
        let n = model.queue.timesQueued(track.uri)
        HStack(spacing: 12) {
            Button { model.player.play(track, in: list, context: context) } label: {
                HStack(spacing: 12) {
                    if showArtwork { Artwork(url: track.artwork) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).font(.body).lineLimit(1)
                            .foregroundStyle(isCurrent ? Theme.accent : .primary)
                        HStack(spacing: 4) {
                            if track.explicit { Image(systemName: "e.square.fill").font(.caption2) }
                            Text(track.artistLine).font(.subheadline).lineLimit(1)
                        }.foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)

            Button {
                model.player.enqueue(track); pop += 1
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: model.queue.isPending(track.uri) ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2).foregroundStyle(model.queue.isPending(track.uri) ? Theme.accent : .secondary)
                        .symbolEffect(.bounce, value: pop)
                    if n > 1 { Text("\(n)").font(.system(size: 10, weight: .bold)).padding(3)
                        .background(Theme.accent, in: Circle()).foregroundStyle(.black).offset(x: 6, y: -6) }
                }.frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Add \(track.name) to queue")
        }
        .swipeActions(edge: .leading) {
            Button { model.player.enqueue(track) } label: { Label("Queue", systemImage: "text.badge.plus") }.tint(Theme.accent)
        }
        .contextMenu { TrackMenu(track: track) }
    }
}

struct TrackMenu: View {
    @Environment(AppModel.self) private var model
    let track: Track
    var body: some View {
        Button { model.player.enqueue(track) } label: { Label("Add to queue", systemImage: "text.badge.plus") }
        Button { model.player.play(track) } label: { Label("Play now", systemImage: "play.fill") }
        Button { model.player.toggleLike(track) } label: {
            Label(model.player.isLiked(track.uri) ? "Remove from Liked" : "Like", systemImage: "heart")
        }
        Menu("Add to playlist") {
            ForEach(model.playlists.prefix(25)) { p in
                Button(p.name) {
                    Task {
                        do { try await model.api.addToPlaylist(p.spotifyID, uris: [track.uri]); model.toast.show("Added to \(p.name)") }
                        catch { model.toast.show(error.localizedDescription, icon: "exclamationmark.triangle.fill", error: true) }
                    }
                }
            }
        }
        if let a = track.album, a.spotifyID != nil { NavigationLink(value: Route.album(a)) { Label("Go to album", systemImage: "square.stack") } }
        if let ar = track.artists.first, ar.spotifyID != nil { NavigationLink(value: Route.artist(ar)) { Label("Go to artist", systemImage: "person") } }
    }
}

enum Route: Hashable { case playlist(Playlist), album(Album), artist(ArtistRef) }

extension View {
    func navigationDestinations() -> some View {
        navigationDestination(for: Route.self) { r in
            switch r {
            case .playlist(let p): PlaylistView(playlist: p)
            case .album(let a): AlbumView(album: a)
            case .artist(let a): ArtistView(artist: a)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String; var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void
    var body: some View {
        let p = model.player
        if let t = p.track {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Artwork(url: t.artwork, size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(p.deviceName.map { "\(t.artistLine) · \($0)" } ?? t.artistLine)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { p.toggleLike(t) } label: { Image(systemName: p.isLiked(t.uri) ? "heart.fill" : "heart")
                        .foregroundStyle(p.isLiked(t.uri) ? Theme.accent : .primary) }
                    Button { p.togglePlay() } label: { Image(systemName: p.isPlaying ? "pause.fill" : "play.fill").font(.title3) }
                    Button { p.next() } label: { Image(systemName: "forward.fill") }
                }
                .padding(.horizontal, 12).padding(.vertical, 8).buttonStyle(.plain)
                GeometryReader { g in
                    Rectangle().fill(Theme.accent)
                        .frame(width: g.size.width * CGFloat(p.progressMs / Double(max(t.durationMs, 1))), height: 2)
                }.frame(height: 2)
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
            .contentShape(Rectangle()).onTapGesture(perform: open)
        }
    }
}
