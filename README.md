# Harmoniq

Online music discovery and native audio playback, alongside your local Android library. No YouTube, extraction tools, WebView player, or self-hosted backend.

## Download for Android

**[Download the latest Harmoniq APK](https://github.com/Ajay-B-Acharya/Rachan/raw/refs/heads/feat/audius-streaming-download/downloads/harmoniq-latest.apk)**

Version **1.0.0+1** · Android · **53.3 MiB** · Updated **September 12, 2026**

This build includes Audius online streaming and local music playback. Download it on your Android phone, open the APK, and allow installation from your browser/file manager if prompted. Only install APKs from a source you trust.

**Development build:** the APK uses the project's development signing key, not a production release key. If Android reports a signing conflict with an existing installation, uninstalling it will remove app-local settings and favorites; back up anything important first.

[Browse the APK](downloads/harmoniq-latest.apk) · [Verify SHA-256](downloads/harmoniq-latest.apk.sha256)

## Listen online

- Home shows trending public tracks from **Audius**.
- Search a song, artist or genre, then tap **Search online** (or the keyboard search action).
- Select a track to play it in Harmoniq's native Now Playing screen. Results become the queue.
- Use play/pause, seek, next/previous, shuffle, repeat, favorites, playlists and the mini-player. Android background media controls use the same audio engine.
- The Local tab retains device scanning and offline playback.

**Catalog:** Audius artist/community music, including original independent music, mixes and edits. This is a Spotify-style player experience, not Spotify's licensed catalog; not every mainstream recording will be available.

## Supported streaming source

The app uses Audius's documented REST API: trending/search/details, and `/v1/tracks/{id}/stream`. Public endpoints support anonymous read access with `app_name=Harmoniq`. An optional client-safe API key may improve rate limits:

```sh
flutter run --dart-define=AUDIUS_API_KEY=YOUR_PUBLIC_API_KEY
```

No key is bundled by default. Never put a bearer token or private signing key in the app. Optional `api_key` uses the official SDK's query convention, not a guessed auth header. URLs containing keys or CDN signatures are not logged or persisted in Song metadata.

Only explicitly streamable, available, public, ungated full tracks are shown. Deleted, unlisted, gated and preview-only entries are excluded. Availability is rechecked before playback. The native player follows the official stream endpoint's CDN redirects; there is no scraping, stream extraction, download feature or third-party proxy.

Source references:
- [Audius API specification](https://api.audius.co/v1/swagger.yaml)
- [Audius documentation](https://docs.audius.co/)

Live development checks retrieved a complete 9,013,650-byte MP3 and verified a 65,536-byte midpoint range against the original file. Other requests encountered slow responses or transient access failures, so error/retry states remain important. A release-mode smoke check on the connected Moto g45 5G (Android 15) subsequently passed native playback progression, seeking to 60 seconds, pause and resume using the production AudioService. The complete Harmoniq app was rebuilt after the temporary test entry point; this spot check does not guarantee every catalog item or network.

## Local music and saved data

Open **Local**, grant music access and scan your device. Scanning runs off the Android UI thread; local search is immediate and lazy-built. Old removed-source favorites remain unavailable legacy records, distinct from Audius records, rather than silently mapping to different songs.

## Develop / build

```sh
flutter pub get
flutter run
flutter analyze
flutter test
flutter build apk --release
```

Android is the primary tested build target. Web can preview UI and use public streaming subject to browser CORS/autoplay; it cannot use the Android local scanner. Other platform folders remain scaffolding; signing, networking and native audio support require platform-specific validation.

## Key files

- `lib/services/online_music_service.dart`: supported API, eligibility checks, bounded metadata cache and safe errors.
- `lib/services/audio_service.dart`: native local/online playback, queue, favorites, scanning and loading state.
- `lib/models/song.dart`: source-aware identity; no persisted temporary media links.
- `lib/screens/`: discovery, search, library and native player.
- `test/`: API eligibility, playback races, local regression and responsive UI tests.

No fake songs, simulated playback, or backend tokens are needed. Release signing still uses the development key; configure production signing and review source terms before publication. Harmoniq is not affiliated with Audius or Spotify.
