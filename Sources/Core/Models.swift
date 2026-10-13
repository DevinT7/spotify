import Foundation

/// Decodes an array element as nil instead of failing the whole array (Spotify returns nulls and episodes).
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct Paging<T: Decodable>: Decodable {
    let items: [T]
    let total: Int?
    let next: String?
    enum CodingKeys: String, CodingKey { case items, total, next }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? c.decode([Lossy<T>].self, forKey: .items)) ?? []).compactMap(\.value)
        total = try? c.decode(Int.self, forKey: .total)
        next = try? c.decode(String.self, forKey: .next)
    }
}

struct SImage: Codable, Hashable { let url: String; let width: Int?; let height: Int? }

func bestImage(_ images: [SImage]?) -> URL? {
    guard let images, !images.isEmpty else { return nil }
    let sorted = images.sorted { ($0.width ?? 0) > ($1.width ?? 0) }
    let pick = sorted.first(where: { ($0.width ?? 0) <= 400 }) ?? sorted.last!
    return URL(string: pick.url)
}

struct ArtistRef: Codable, Hashable, Identifiable {
    let spotifyID: String?
    let uri: String?
    let name: String
    let images: [SImage]?
    var id: String { uri ?? name }
    enum CodingKeys: String, CodingKey { case spotifyID = "id", uri, name, images }
}

struct Album: Codable, Hashable, Identifiable {
    let spotifyID: String?
    let uri: String?
    let name: String
    let images: [SImage]?
    let artists: [ArtistRef]?
    let releaseDate: String?
    let totalTracks: Int?
    var id: String { uri ?? name }
    var artistLine: String { (artists ?? []).map(\.name).joined(separator: ", ") }
    var year: String { String((releaseDate ?? "").prefix(4)) }
    enum CodingKeys: String, CodingKey { case spotifyID = "id", uri, name, images, artists, releaseDate, totalTracks }
}

struct Track: Codable, Hashable, Identifiable {
    let uri: String
    let name: String
    let artists: [ArtistRef]
    var album: Album?
    let durationMs: Int
    let explicit: Bool
    var id: String { uri }
    var artistLine: String { artists.map(\.name).joined(separator: ", ") }
    var artwork: URL? { bestImage(album?.images) }

    enum CodingKeys: String, CodingKey { case uri, name, artists, album, durationMs, explicit }
    init(uri: String, name: String, artists: [ArtistRef], album: Album?, durationMs: Int, explicit: Bool) {
        self.uri = uri; self.name = name; self.artists = artists; self.album = album
        self.durationMs = durationMs; self.explicit = explicit
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decode(String.self, forKey: .uri)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
        artists = (try? c.decode([ArtistRef].self, forKey: .artists)) ?? []
        album = try? c.decode(Album.self, forKey: .album)
        durationMs = (try? c.decode(Int.self, forKey: .durationMs)) ?? 0
        explicit = (try? c.decode(Bool.self, forKey: .explicit)) ?? false
    }
}

struct Playlist: Codable, Hashable, Identifiable {
    struct Owner: Codable, Hashable { let displayName: String? }
    struct Total: Codable, Hashable { let total: Int? }
    let spotifyID: String
    let uri: String
    let name: String
    let images: [SImage]?
    let owner: Owner?
    let description: String?
    let tracks: Total?
    let items: Total?
    var id: String { uri }
    var count: Int? { items?.total ?? tracks?.total }
    var artwork: URL? { bestImage(images) }
    enum CodingKeys: String, CodingKey { case spotifyID = "id", uri, name, images, owner, description, tracks, items }
}

struct PlaylistEntry: Decodable {
    let track: Track?
    enum CodingKeys: String, CodingKey { case track, item }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        track = (try? c.decode(Track.self, forKey: .item)) ?? (try? c.decode(Track.self, forKey: .track))
    }
}

struct Device: Codable, Hashable, Identifiable {
    let spotifyID: String?
    let name: String
    let type: String
    let isActive: Bool
    let volumePercent: Int?
    var id: String { spotifyID ?? name }
    var icon: String {
        switch type.lowercased() {
        case "computer": "laptopcomputer"
        case "smartphone": "iphone"
        case "speaker": "hifispeaker"
        case "tv": "tv"
        default: "speaker.wave.2"
        }
    }
    enum CodingKeys: String, CodingKey { case spotifyID = "id", name, type, isActive, volumePercent }
}

struct PlaybackState: Decodable {
    let isPlaying: Bool
    let progressMs: Int?
    let item: Track?
    let device: Device?
    let shuffleState: Bool?
    let repeatState: String?
}

struct QueueResponse: Decodable {
    let currentlyPlaying: Track?
    let queue: [Track]
    enum CodingKeys: String, CodingKey { case currentlyPlaying, queue }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentlyPlaying = try? c.decode(Track.self, forKey: .currentlyPlaying)
        queue = ((try? c.decode([Lossy<Track>].self, forKey: .queue)) ?? []).compactMap(\.value)
    }
}

struct SearchResponse: Decodable {
    let tracks: Paging<Track>?
    let albums: Paging<Album>?
    let artists: Paging<ArtistRef>?
    let playlists: Paging<Playlist>?
}

struct PlayHistoryItem: Decodable { let track: Track; let playedAt: String }
struct SavedTrack: Decodable { let track: Track }
struct SavedAlbum: Decodable { let album: Album }
struct UserProfile: Decodable { let displayName: String?; let product: String?; let id: String }
