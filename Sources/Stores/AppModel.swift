import Observation

@Observable @MainActor
final class AppModel {
    let auth = AuthManager()
    let api: SpotifyAPI
    let queue = QueueStore()
    let toast = ToastCenter()
    let player: PlayerStore
    var profile: UserProfile?
    var playlists: [Playlist] = []

    init() {
        api = SpotifyAPI(auth: auth)
        player = PlayerStore(api: api, queueStore: queue, toast: toast)
    }

    func bootstrap() async {
        PlaybackBridge.handler = PlaybackBridge.handler
        player.start()
        profile = try? await api.me()
        playlists = (try? await api.playlists()) ?? []
    }
}
