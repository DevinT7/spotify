# How Spotify on iOS works, and what Tempo does about it

## Evidence (sources I could actually read)
| Claim | Source |
|---|---|
| Third-party iOS apps can't stream Spotify audio. The iOS SDK (App Remote) only remote-controls the Spotify app installed on the same device; audio stays in Spotify. | [Spotify community: App Remote without Spotify app](https://community.spotify.com/t5/Spotify-for-Developers/Does-Spotify-App-Remote-work-without-physical-Spotify-iOS-app/m-p/5025514/highlight/true), [30s idle disconnect](https://community.spotify.com/t5/Spotify-for-Developers/iOS-amp-Android-Remote-SDK-loses-connection-after-paused-for-30s/td-p/7077461) |
| Playback control endpoints need Premium and an active Connect device. | Third-party API docs (e.g. [Requestly](https://requestly.com/api-explorer/spotify/)); verified only indirectly. |
| Search `limit` max is now 10; type-specific save/follow endpoints replaced by `/me/library`; playlist `/tracks` renamed `/items`; batch fetch, browse, artist top-tracks removed. Playback + queue endpoints unchanged. | [Spotify Feb 2026 migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide) (fetched) |
| Dev-mode apps need the owner to hold Premium; 5 users per app; extended quota is org-only. | [Spotify blog](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security), [July 2026 quota update](https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates) |

Architecture implied: the Spotify mobile app = UI + local playback engine + Spotify Connect (cloud-routed control of any logged-in device). The Web API is a remote control for Connect. So Tempo is a Connect controller with its own UI.

I did **not** decompile the iOS binary: no iOS build was available locally (only the macOS `Spotify.app`), and everything needed for this design is publicly documented.

## UI complaints
**Could not read the requested Reddit thread** (reddit.com is blocked from both fetch tools here), so nothing below is from it. Gathered instead from Spotify's community forums and press:
- Vertical TikTok-style home feed and autoplaying video; fewer items visible at once ([TechCrunch](https://techcrunch.com/2023/03/08/spotify-revamps-its-app-with-tiktok-style-discovery-feeds-smart-shuffle-for-playlists-and-more), [forum](https://community.spotify.com/t5/App-Features/New-Home-Feed-Interface/m-p/5522678/highlight/true))
- Giant album art that limits browsing ([forum](https://community.spotify.com/t5/App-Features/My-home-screen-updated-yesterday-and-it-as-l-is-absolutely/m-p/5511227/highlight/true))
- Queue/repeat/shuffle buried behind "..." ([forum](https://community.spotify.com/t5/Implemented-Ideas/Mobile-Return-repeat-and-queue-buttons-to-Now-Playing-screen/idc-p/4689545/highlight/true))
- Queue reshuffling and Smart Shuffle bugs ([forum](https://community.spotify.com/t5/iOS-iPhone-iPad/Several-issues-with-queue-and-shuffling/m-p/6141601/highlight/true))
- No opt-out of the new layout.
If you paste the Reddit comments here I'll fold them in.

## Tempo's answers
| Complaint / idea | Tempo |
|---|---|
| Queue from search | `+` on every track row (search, home, library, albums); swipe right and long-press also work. Stays on-screen, shows a toast and a ✓. |
| Queue disappears | `QueueStore` persists every queued song to disk; Queue tab "history" lets you re-queue or play any of them. Entries flip Up next → Played automatically. |
| Hidden controls | Now Playing shows shuffle, repeat, queue, devices, like, volume at once. |
| Feed/video clutter | Home is static: resume card, queue trail, 2-col playlist grid, recents, top tracks, top artists. |

## Premium features: what is and isn't possible
Works (Web API, Premium): on-demand play, skip, seek, volume, shuffle/repeat, queue add, device transfer.
Not possible for any third-party app: playing audio inside the app, offline downloads, lossless, DJ, Smart Shuffle, Jam, lyrics, podcasts/video, removing or reordering Spotify's queue (the API is add-only).
