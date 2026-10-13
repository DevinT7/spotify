import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var liked: [Track] = []
    @State private var albums: [Album] = []
    @State private var tab = 0
    @State private var filter = ""
    @State private var newName = ""
    @State private var creating = false

    var body: some View {
        List {
            Picker("", selection: $tab) { Text("Playlists").tag(0); Text("Liked").tag(1); Text("Albums").tag(2) }
                .pickerStyle(.segmented).listRowSeparator(.hidden).listRowBackground(Color.clear)
            switch tab {
            case 0:
                ForEach(model.playlists.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { p in
                    NavigationLink(value: Route.playlist(p)) {
                        HStack { Artwork(url: p.artwork, size: 56); VStack(alignment: .leading) {
                            Text(p.name).lineLimit(1)
                            Text("\(p.count.map { "\($0) songs" } ?? "Playlist") · \(p.owner?.displayName ?? "")").font(.subheadline).foregroundStyle(.secondary).lineLimit(1) } }
                    }
                }
            case 1:
                ForEach(liked.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.artistLine.localizedCaseInsensitiveContains(filter) }) { t in
                    TrackRow(track: t, list: liked)
                }
            default:
                ForEach(albums.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { a in
                    NavigationLink(value: Route.album(a)) {
                        HStack { Artwork(url: bestImage(a.images), size: 56); VStack(alignment: .leading) {
                            Text(a.name).lineLimit(1); Text(a.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) } }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Library")
        .searchable(text: $filter, prompt: "Filter your library")
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .alert("New playlist", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") {
                let n = newName; newName = ""
                Task { if let p = try? await model.api.createPlaylist(name: n) { model.playlists.insert(p, at: 0); model.toast.show("Created \(n)") } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            if let s = try? await model.api.savedTracks() { liked = s.items.map(\.track) }
            albums = (try? await model.api.savedAlbums()) ?? []
        }
    }
}
