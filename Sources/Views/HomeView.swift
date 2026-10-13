import SwiftUI

/// Dense, static home: no autoplay video, no carousels inside carousels. Everything is one tap from playing or queueing.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var recent: [Track] = []
    @State private var top: [Track] = []
    @State private var artists: [ArtistRef] = []
    @State private var loaded = false
    @State private var loadError: String?

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"; case 12..<18: "Good afternoon"; default: "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                resumeCard
                if !model.queue.entries.isEmpty { queueTrail }
                if !model.playlists.isEmpty { playlistGrid }
                if !recent.isEmpty { recentSection }
                if !top.isEmpty { topSection }
                if !artists.isEmpty { artistRow }
                if let loadError {
                    VStack(spacing: 10) {
                        Label("Couldn't load your music", systemImage: "exclamationmark.triangle.fill").font(.headline)
                        Text(loadError).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try again") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity).padding().background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                }
                if !loaded { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("").navigationBarHidden(true)
        .refreshable { await load() }
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(greeting).font(.largeTitle.weight(.heavy))
                if let n = model.profile?.displayName { Text(n).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu {
                if let p = model.profile?.product { Text("Plan: \(p.capitalized)") }
                Button("Sign out", role: .destructive) { model.auth.signOut() }
            } label: { Image(systemName: "person.crop.circle").font(.title) }
        }
    }

    @ViewBuilder private var resumeCard: some View {
        if let t = model.player.track ?? recent.first {
            HStack(spacing: 14) {
                Artwork(url: t.artwork, size: 84, radius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.player.track == nil ? "PICK UP WHERE YOU LEFT OFF" : "NOW PLAYING")
                        .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                    Text(t.name).font(.headline).lineLimit(2)
                    Text(t.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { model.player.track == nil ? model.player.play(t) : model.player.togglePlay() } label: {
                    Image(systemName: model.player.track != nil && model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(Theme.accent)
                }
            }
            .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var queueTrail: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Your queue trail", subtitle: "Everything you've queued — tap to play or queue again")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.queue.entries.prefix(15)) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Artwork(url: e.track.artwork, size: 110, radius: 8)
                            Text(e.track.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(e.playedAt == nil ? "Up next" : "Played").font(.caption2)
                                .foregroundStyle(e.playedAt == nil ? Theme.accent : .secondary)
                        }
                        .frame(width: 110).contentShape(Rectangle())
                        .onTapGesture { model.player.enqueue(e.track) }
                        .contextMenu { TrackMenu(track: e.track) }
                    }
                }
            }
        }
    }

    private var playlistGrid: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Jump back in")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(model.playlists.prefix(8)) { p in
                    NavigationLink(value: Route.playlist(p)) {
                        HStack(spacing: 8) {
                            Artwork(url: p.artwork, size: 52, radius: 0)
                            Text(p.name).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6)).clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(spacing: 4) {
            SectionHeader(title: "Recently played")
            ForEach(recent.prefix(6)) { t in TrackRow(track: t, list: recent) }
        }
    }

    private var topSection: some View {
        VStack(spacing: 4) {
            SectionHeader(title: "On repeat", subtitle: "Your top tracks lately")
            ForEach(top.prefix(8)) { t in TrackRow(track: t, list: top) }
        }
    }

    private var artistRow: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Your top artists")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(artists.prefix(12)) { a in
                        NavigationLink(value: Route.artist(a)) {
                            VStack {
                                Artwork(url: bestImage(a.images), size: 84, circle: true)
                                Text(a.name).font(.caption).lineLimit(1).frame(width: 84)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        loadError = nil
        do { _ = try await model.api.recentlyPlayed() } catch is CancellationError { return } catch let e as URLError where e.code == .cancelled { return } catch {
            if case SpotifyError.http(403, _) = error {
                loadError = "Spotify returned 403: this account isn't allowed to use your app. In the Spotify developer dashboard open your app → User Management and add the name and email of the Spotify account you signed in with, then tap Try again."
            } else { loadError = error.localizedDescription }
            loaded = true; return
        }
        if model.playlists.isEmpty { model.playlists = (try? await model.api.playlists()) ?? [] }
        async let r = try? model.api.recentlyPlayed()
        async let t = try? model.api.topTracks()
        async let a = try? model.api.topArtists()
        let (rr, tt, aa) = await (r, t, a)
        var seen = Set<String>()
        recent = (rr ?? []).map(\.track).filter { seen.insert($0.uri).inserted }
        top = tt ?? []; artists = aa ?? []
        loaded = true
    }
}
