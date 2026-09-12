# Harmoniq

A Flutter music player with native audio controls for local files and online YouTube audio.

## Listening

1. Tap **Find your next song**, choose a mood, or open Search.
2. Search for a song/artist, or paste a YouTube/YouTube Music link.
3. Select a result. Harmoniq opens its own Now Playing screen with artwork, queue, seek, favorite, shuffle/repeat and play/pause controls.

There is no embedded video, hidden WebView, or external YouTube app handoff. The search result list becomes the queue. Online and local tracks use the same `just_audio` engine and Android background-media integration.

## How online playback works

- Search uses public metadata via `youtube_explode_dart` without a key on native platforms, or the official YouTube Data API when configured.
- At playback time, the resolver requests an audio-only stream manifest using the library's standard API. MP4 audio is preferred where available, otherwise another audio-only stream is selected.
- Resolved signed URLs are temporary. They are never persisted in songs/favorites or printed in logs; retry resolves a fresh URL.
- Loading and playback errors are visible. Pause while loading is respected; skip/stop/dispose invalidate older requests so stale work cannot restart playback.
- YouTube song IDs remain strings, separate from local numeric IDs, preventing queue/catalog/favorite collisions.

**This playback integration is unofficial.** It is not the YouTube Music API or a Premium integration. Streams may fail because of service changes, expired links, regional/age restrictions, throttling or authentication requirements. No user cookies, credentials, proxies, custom challenge solvers, or additional bypass mechanisms are configured. The third-party package has its own default request identities and retry behavior. No video fallback is used. Review provider terms and media rights before distributing or using online features commercially.

### Known playback blocker (2026-09-12)

The reported Proximity track `SMs0GnYze34` currently fails audio delivery with HTTP 403. A manifest can resolve even when its media cannot be fetched. The MP4 library download produced zero bytes before the deadline. A WebM prefix request returned 206, but both a subsequent full request and a first full request from a fresh manifest returned 403 with zero bytes. Therefore neither format switching nor temporary-file buffering has been validated as a fix. The app now distinguishes provider denial when the Dart error payload includes an HTTP status, without exposing signed URLs. The installed just_audio Android plugin often logs HTTP 403 natively but forwards only `Source error` to Dart; those cases correctly remain generic rather than inventing a cause. Do not treat passing unit tests, a successful build, or a small prefix download as proof of working YouTube audio playback.

## Run

```sh
flutter pub get
flutter run
```

Optional official **metadata** API mode (does not grant official audio-stream access):

```sh
flutter run --dart-define=YOUTUBE_API_KEY=YOUR_RESTRICTED_KEY
flutter build apk --release --dart-define=YOUTUBE_API_KEY=YOUR_RESTRICTED_KEY
```

Enable YouTube Data API v3 in Google Cloud. Never commit a real key. Client `dart-define` values are bundled and are not secrets; apply suitable application/API restrictions, quota limits, or use an authenticated backend for production credential protection.

## Platforms

- **Android:** primary target; local MediaStore scanning, native online audio and media notifications.
- **Web:** UI preview and optional official metadata search; online audio resolution is explicitly unsupported due to browser/network restrictions. No iframe or public CORS proxy fallback.
- **iOS/macOS:** source-resolution code is native-compatible but platform audio/signing/network configuration is unverified here.
- **Windows/Linux:** metadata resolution can run, but this project does not include an appropriate `just_audio` desktop backend. A successful source request is not native playback support.

Windows Flutter plugin development may require symlink support. The project does not change machine settings automatically.

## Existing library

Local scanning remains off the Android UI thread, lists remain lazy/cached, and progress updates are isolated from full-screen rebuilds. Saved favorites from the removed Jamendo source remain unavailable legacy metadata, not silently deleted or converted into unrelated YouTube tracks.

## Checks

```sh
flutter analyze
flutter test
flutter build apk --release
flutter build web --release
```

Tests cover source-aware identity/serialization, temporary URL exclusion, resolver failure/races, loading/pause/stop/retry, queues, local scanning, search routing, responsive layouts and reduced motion. Tests use fake transports/players; distinguish these from live device playback verification.

## Main components

- `youtube_catalog.dart`: metadata discovery and bounded caching.
- `youtube_audio_resolver.dart`: native/stub audio-resolution boundary.
- `audio_service.dart`: shared native playback, queue and library state.
- `now_playing_screen.dart` / `mini_player.dart`: native audio UI.

Harmoniq is independent and is not affiliated with or endorsed by YouTube or Google.
