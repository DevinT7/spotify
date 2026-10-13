import SwiftUI

struct DetailHeader: View {
    @Environment(AppModel.self) private var model
    let artwork: URL?; let title: String; let subtitle: String; let tracks: [Track]; let context: String?
    var body: some View {
        VStack(spacing: 10) {
            Artwork(url: artwork, size: 200, radius: 10)
            Text(title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { if let context { model.player.playContext(context) } else if let f = tracks.first { model.player.play(f, in: tracks) } } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.accent, in: Capsule()).foregroundStyle(.black).font(.headline)
                }
                Button { tracks.forEach { model.player.enqueue($0) } } label: {
                    Label("Queue all", systemImage: "text.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.card, in: Capsule()).font(.headline)
                }
            }.buttonStyle(.plain).disabled(tracks.isEmpty)
        }.frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
}

struct PlaylistView: View {
    @Environment(AppModel.self) private var model
    let playlist: Playlist
    @State private var tracks: [Track] = []
    @State private var failed = false
    var body: some View {
        List {
            DetailHeader(artwork: playlist.artwork, title: playlist.name, subtitle: playlist.owner?.displayName ?? "", tracks: tracks, context: playlist.uri)
            ForEach(tracks) { TrackRow(track: $0, list: tracks, context: playlist.uri) }
            if failed { Text("Spotify only exposes tracks for playlists you own or collaborate on.").font(.footnote).foregroundStyle(.secondary) }
        }
        .listStyle(.plain).navigationBarTitleDisplayMode(.inline)
        .task {
            do { tracks = try await model.api.playlistTracks(playlist.spotifyID) } catch { failed = true }
        }
    }
}

struct AlbumView: View {
    @Environment(AppModel.self) private var model
    let album: Album
    @State private var tracks: [Track] = []
    var body: some View {
        List {
            DetailHeader(artwork: bestImage(album.images), title: album.name, subtitle: "\(album.artistLine) · \(album.year)", tracks: tracks, context: album.uri)
            ForEach(tracks) { TrackRow(track: $0, list: tracks, context: album.uri, showArtwork: false) }
        }
        .listStyle(.plain).navigationBarTitleDisplayMode(.inline)
        .task { tracks = (try? await model.api.albumTracks(album)) ?? [] }
    }
}

struct ArtistView: View {
    @Environment(AppModel.self) private var model
    let artist: ArtistRef
    @State private var albums: [Album] = []
    var body: some View {
        List {
            VStack(spacing: 10) {
                Artwork(url: bestImage(artist.images), size: 180, circle: true)
                Text(artist.name).font(.title.weight(.bold))
                if let u = artist.uri { Button { model.player.playContext(u) } label: {
                    Label("Play", systemImage: "play.fill").padding(.horizontal, 40).padding(.vertical, 12)
                        .background(Theme.accent, in: Capsule()).foregroundStyle(.black).font(.headline) }.buttonStyle(.plain) }
            }.frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Color.clear)
            Section("Albums & singles") {
                ForEach(albums) { al in
                    NavigationLink(value: Route.album(al)) {
                        HStack { Artwork(url: bestImage(al.images)); VStack(alignment: .leading) {
                            Text(al.name).lineLimit(1); Text(al.year).font(.subheadline).foregroundStyle(.secondary) } }
                    }
                }
            }
        }
        .listStyle(.plain).navigationBarTitleDisplayMode(.inline)
        .task { if let id = artist.spotifyID { albums = (try? await model.api.artistAlbums(id)) ?? [] } }
    }
}
