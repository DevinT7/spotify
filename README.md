# Tempo
SwiftUI iOS 17+ Spotify controller. See [docs/RESEARCH.md](docs/RESEARCH.md).

## Run
1. https://developer.spotify.com/dashboard → Create app → redirect URI `tempo://callback`, API: Web API. Add your Spotify account under User Management (dev mode requires it; the app owner needs Premium).
2. `xcodegen generate && open Tempo.xcodeproj`, run on a simulator or device.
3. Paste the Client ID on the login screen and sign in.
4. Audio plays on a Spotify device: open Spotify on your phone/Mac first, then pick it in Tempo.
