import Foundation

enum SpotifyError: LocalizedError {
    case http(Int, String), noActiveDevice, premiumRequired
    var errorDescription: String? {
        switch self {
        case .http(let c, let m): "Spotify error \(c): \(m)"
        case .noActiveDevice: "No active Spotify device. Open Spotify on a phone, Mac or speaker."
        case .premiumRequired: "This needs Spotify Premium."
        }
    }
}

@MainActor
final class SpotifyAPI {
    let auth: AuthManager
    private let base = "https://api.spotify.com/v1"
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()

    init(auth: AuthManager) { self.auth = auth }

    // MARK: transport
    @discardableResult
    func send(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil, retried: Bool = false) async throws -> Data? {
        var c = URLComponents(string: base + path)!
        if !query.isEmpty { c.queryItems = query.map { .init(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) { print("TEMPO-API \(method) \(path) -> \(status) \(String(data: data, encoding: .utf8) ?? "")") }
        switch status {
        case 200..<300: return status == 204 || data.isEmpty ? nil : data
        case 401 where !retried:
            await auth.forceRefresh()
            return try await send(method, path, query: query, body: body, retried: true)
        case 429 where !retried:
            let wait = Double((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
            try await Task.sleep(for: .seconds(min(wait, 5)))
            return try await send(method, path, query: query, body: body, retried: true)
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any]) } ?? [:]
            let text = (msg["message"] as? String) ?? ""
            let reason = (msg["reason"] as? String) ?? ""
            if reason == "NO_ACTIVE_DEVICE" || (status == 404 && path.hasPrefix("/me/player")) { throw SpotifyError.noActiveDevice }
            if reason == "PREMIUM_REQUIRED" { throw SpotifyError.premiumRequired }
            throw SpotifyError.http(status, text)
        }
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:], as: T.Type = T.self) async throws -> T {
        guard let d = try await send("GET", path, query: query) else { throw SpotifyError.http(204, "empty") }
        return try decoder.decode(T.self, from: d)
    }

    // MARK: profile / browse
    func me() async throws -> UserProfile { try await get("/me") }
    func search(_ q: String, types: String = "track,album,artist,playlist", limit: Int = 10, offset: Int = 0) async throws -> SearchResponse {
        try await get("/search", ["q": q, "type": types, "limit": "\(min(limit, 10))", "offset": "\(offset)"])
    }
    func recentlyPlayed() async throws -> [PlayHistoryItem] {
        (try await get("/me/player/recently-played", ["limit": "50"], as: Paging<PlayHistoryItem>.self)).items
    }
    func topTracks(range: String = "short_term") async throws -> [Track] {
        (try await get("/me/top/tracks", ["limit": "20", "time_range": range], as: Paging<Track>.self)).items
    }
    func topArtists() async throws -> [ArtistRef] {
        (try await get("/me/top/artists", ["limit": "20", "time_range": "medium_term"], as: Paging<ArtistRef>.self)).items
    }
    func playlists() async throws -> [Playlist] {
        var all: [Playlist] = []; var offset = 0
        while offset < 200 {
            let p: Paging<Playlist> = try await get("/me/playlists", ["limit": "50", "offset": "\(offset)"])
            all += p.items
            if p.next == nil { break }; offset += 50
        }
        return all
    }
    func savedTracks(offset: Int = 0) async throws -> Paging<SavedTrack> {
        try await get("/me/tracks", ["limit": "50", "offset": "\(offset)"])
    }
    func savedAlbums() async throws -> [Album] {
        (try await get("/me/albums", ["limit": "50"], as: Paging<SavedAlbum>.self)).items.map(\.album)
    }
    func followedArtists() async throws -> [ArtistRef] {
        struct R: Decodable { let artists: Paging<ArtistRef> }
        return (try await get("/me/following", ["type": "artist", "limit": "50"], as: R.self)).artists.items
    }
    func playlistTracks(_ id: String) async throws -> [Track] {
        var all: [Track] = []; var offset = 0
        while offset < 500 {
            let p: Paging<PlaylistEntry> = try await get("/playlists/\(id)/items", ["limit": "50", "offset": "\(offset)"])
            all += p.items.compactMap(\.track)
            if p.next == nil { break }; offset += 50
        }
        return all
    }
    func albumTracks(_ album: Album) async throws -> [Track] {
        guard let id = album.spotifyID else { return [] }
        var tracks = (try await get("/albums/\(id)/tracks", ["limit": "50"], as: Paging<Track>.self)).items
        for i in tracks.indices { tracks[i].album = album }
        return tracks
    }
    func artistAlbums(_ id: String) async throws -> [Album] {
        (try await get("/artists/\(id)/albums", ["include_groups": "album,single", "limit": "10"], as: Paging<Album>.self)).items
    }
    func createPlaylist(name: String) async throws -> Playlist {
        guard let d = try await send("POST", "/me/playlists", body: ["name": name, "public": false]) else { throw SpotifyError.http(0, "empty") }
        return try decoder.decode(Playlist.self, from: d)
    }
    func addToPlaylist(_ id: String, uris: [String]) async throws {
        try await send("POST", "/playlists/\(id)/items", body: ["uris": uris])
    }

    // MARK: library (generic endpoints, Feb 2026)
    func isSaved(_ uris: [String]) async -> [Bool] {
        guard !uris.isEmpty else { return [] }
        let d = try? await send("GET", "/me/library/contains", query: ["uris": uris.joined(separator: ",")])
        return d.flatMap { try? JSONDecoder().decode([Bool].self, from: $0) } ?? Array(repeating: false, count: uris.count)
    }
    func save(_ uri: String) async throws { try await send("PUT", "/me/library", query: ["uris": uri]) }
    func unsave(_ uri: String) async throws { try await send("DELETE", "/me/library", query: ["uris": uri]) }

    // MARK: player
    func playbackState() async throws -> PlaybackState? {
        guard let d = try await send("GET", "/me/player") else { return nil }
        return try? decoder.decode(PlaybackState.self, from: d)
    }
    func queue() async throws -> QueueResponse? {
        guard let d = try await send("GET", "/me/player/queue") else { return nil }
        return try? decoder.decode(QueueResponse.self, from: d)
    }
    func devices() async throws -> [Device] {
        struct R: Decodable { let devices: [Device] }
        return (try await get("/me/player/devices", as: R.self)).devices
    }
    func addToQueue(uri: String, deviceID: String? = nil) async throws {
        var q = ["uri": uri]; if let deviceID { q["device_id"] = deviceID }
        try await send("POST", "/me/player/queue", query: q)
    }
    func play(uris: [String]? = nil, context: String? = nil, offsetURI: String? = nil, positionMs: Int? = nil, deviceID: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let uris { body["uris"] = uris }
        if let context { body["context_uri"] = context }
        if let offsetURI { body["offset"] = ["uri": offsetURI] }
        if let positionMs { body["position_ms"] = positionMs }
        try await send("PUT", "/me/player/play", query: deviceID.map { ["device_id": $0] } ?? [:], body: body.isEmpty ? nil : body)
    }
    func resume() async throws { try await send("PUT", "/me/player/play") }
    func pause() async throws { try await send("PUT", "/me/player/pause") }
    func next() async throws { try await send("POST", "/me/player/next") }
    func previous() async throws { try await send("POST", "/me/player/previous") }
    func seek(_ ms: Int) async throws { try await send("PUT", "/me/player/seek", query: ["position_ms": "\(ms)"]) }
    func volume(_ pct: Int) async throws { try await send("PUT", "/me/player/volume", query: ["volume_percent": "\(pct)"]) }
    func shuffle(_ on: Bool) async throws { try await send("PUT", "/me/player/shuffle", query: ["state": on ? "true" : "false"]) }
    func repeatMode(_ s: String) async throws { try await send("PUT", "/me/player/repeat", query: ["state": s]) }
    func transfer(to id: String, play: Bool) async throws { try await send("PUT", "/me/player", body: ["device_ids": [id], "play": play]) }
}
