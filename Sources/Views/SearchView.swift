import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var results: SearchResponse?
    @State private var tracks: [Track] = []
    @State private var filter = Filter.all
    @State private var loading = false
    @State private var recents: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    @State private var searchTask: Task<Void, Never>?

    enum Filter: String, CaseIterable { case all = "All", songs = "Songs", albums = "Albums", artists = "Artists", playlists = "Playlists" }

    var body: some View {
        List {
            if text.isEmpty {
                recentSection
            } else {
                Picker("", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).listRowBackground(Color.clear).listRowSeparator(.hidden)
                resultSections
            }
        }
        .listStyle(.plain)
        .navigationTitle("Search")
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs, albums, artists")
        .onSubmit(of: .search) { remember(text) }
        .onChange(of: text) { _, new in
            searchTask?.cancel()
            guard !new.trimmingCharacters(in: .whitespaces).isEmpty else { results = nil; tracks = []; return }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await run(new)
            }
        }
        .overlay { if loading && results == nil { ProgressView() } }
    }

    @ViewBuilder private var recentSection: some View {
        if !recents.isEmpty {
            Section {
                ForEach(recents, id: \.self) { r in
                    Button { text = r } label: { Label(r, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary) }
                }.onDelete { recents.remove(atOffsets: $0); UserDefaults.standard.set(recents, forKey: "recentSearches") }
            } header: { Text("Recent searches") }
        } else {
            ContentUnavailableView("Find anything", systemImage: "magnifyingglass",
                                   description: Text("Tap the + next to any song to queue it without leaving search."))
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var resultSections: some View {
        if filter == .all || filter == .songs, !tracks.isEmpty {
            Section("Songs") {
                ForEach(tracks) { t in TrackRow(track: t, list: nil) }
                if let total = results?.tracks?.total, tracks.count < total, tracks.count < 50 {
                    Button("Show more songs") { Task { await moreTracks() } }.foregroundStyle(Theme.accent)
                }
            }
        }
        if filter == .all || filter == .artists, let a = results?.artists?.items, !a.isEmpty {
            Section("Artists") {
                ForEach(a.prefix(filter == .all ? 3 : 10)) { ar in
                    NavigationLink(value: Route.artist(ar)) {
                        HStack { Artwork(url: bestImage(ar.images), size: 48, circle: true); Text(ar.name) }
                    }
                }
            }
        }
        if filter == .all || filter == .albums, let a = results?.albums?.items, !a.isEmpty {
            Section("Albums") {
                ForEach(a.prefix(filter == .all ? 4 : 10)) { al in
                    NavigationLink(value: Route.album(al)) {
                        HStack { Artwork(url: bestImage(al.images)); VStack(alignment: .leading) {
                            Text(al.name).lineLimit(1); Text("\(al.year) · \(al.artistLine)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1) } }
                    }
                }
            }
        }
        if filter == .all || filter == .playlists, let p = results?.playlists?.items, !p.isEmpty {
            Section("Playlists") {
                ForEach(p.prefix(filter == .all ? 3 : 10)) { pl in
                    NavigationLink(value: Route.playlist(pl)) {
                        HStack { Artwork(url: pl.artwork); VStack(alignment: .leading) {
                            Text(pl.name).lineLimit(1); Text(pl.owner?.displayName ?? "").font(.subheadline).foregroundStyle(.secondary) } }
                    }
                }
            }
        }
    }

    private func run(_ q: String) async {
        loading = true; defer { loading = false }
        do {
            let r = try await model.api.search(q)
            results = r; tracks = r.tracks?.items ?? []
        } catch { model.toast.show(error.localizedDescription, icon: "exclamationmark.triangle.fill", error: true) }
    }
    private func moreTracks() async {
        guard let r = try? await model.api.search(text, types: "track", offset: tracks.count) else { return }
        tracks += r.tracks?.items ?? []
    }
    private func remember(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
        recents.removeAll { $0 == t }; recents.insert(t, at: 0); recents = Array(recents.prefix(10))
        UserDefaults.standard.set(recents, forKey: "recentSearches")
    }
}
