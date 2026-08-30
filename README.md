# Rachan 🎧

A modern Flutter-based music player focused on playing music stored locally on an Android device.

## Version

v1.0.0 — Local Music Player

## Current Features

- **Local Storage Access & Permissions**: Requests and handles standard storage access (supporting modern Android 13+ `READ_MEDIA_AUDIO` permission workflow).
- **Local Audio Scanning**: Natively queries the Android `MediaStore` cursor via a custom Kotlin MethodChannel to retrieve real MP3 tracks.
- **Audio Playback Engine**: Fully integrated with `just_audio` to play local media tracks with hardware decoding.
- **Playback Controls**: Play, pause, resume, seek, next/previous queue skipping.
- **Real-Time Duration & Progress**: Displays actual track durations and current playback positions dynamically.
- **Glassmorphism Dark UI**: A sleek, modern dark-themed dashboard using premium glass-morphic visual styling.
- **Interactive Mini Player**: Stays fully synchronized with active track changes and progress across all app tabs.
- **Now Playing Screen**: Features a detailed view with spring-based album art animations, a queue drawer, and precise seeking controls.
- **Search Screen**: Allows typing queries to search and filter local songs instantly.
- **Favorites & Library**: Supports favoriting songs and adding them to custom user-created playlists dynamically.

## Current Limitations

- **Rachan v1.0.0** currently supports local music playback only.
- Online music streaming is not implemented yet.
- No Spotify, YouTube, or other commercial music catalog integration.
- No user authentication or cloud sync.
- The app currently focuses on music files available physically on the Android device.

## Tech Stack

- **Framework**: [Flutter](https://flutter.dev) (Dart SDK `^3.13.2`)
- **Native Android Binding**: Kotlin MethodChannel (`com.example.rachan/local_music`)
- **Audio Engine**: [`just_audio`](https://pub.dev/packages/just_audio) for local resource decoding and playback control
- **Permissions Handler**: Custom native activity request logic for `READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE`

## Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd rachan
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Connect an Android device** with USB debugging enabled.

4. **Run the app**:
   ```bash
   flutter run
   ```

## Permissions

Rachan requests local storage permissions to scan and play audio files:
* **Android 13+ (API 33+)**: Requests `android.permission.READ_MEDIA_AUDIO` for direct access to music libraries.
* **Android 12 and below**: Requests `android.permission.READ_EXTERNAL_STORAGE` for legacy filesystem access.

## Project Structure

The primary directory layout is organized as follows:
```text
rachan/
├── android/            # Native Android Gradle configuration and Kotlin plugins
│   └── app/src/main/kotlin/com/example/rachan/MainActivity.kt # Local music cursor scanning
├── lib/
│   ├── data/           # Fallback mock/sample data
│   ├── models/         # Data structures (Song, Playlist)
│   ├── screens/        # Primary layout layers (HomeScreen, SearchScreen, LocalScreen, NowPlayingScreen)
│   ├── services/       # Audio player services (AudioService backed by just_audio)
│   ├── theme/          # App coloring and visual configuration
│   ├── widgets/        # Component widgets (MiniPlayer, AlbumArt, BottomNav, GlassCard)
│   └── main.dart       # Main entry point and screen routing shell
├── pubspec.yaml        # Flutter dependency manager
└── README.md           # Project documentation
```

## Future Roadmap

### v1.1
- Improve local library organization (artist and album groupings)
- Custom playlist improvements (sorting and cover customisation)
- Better queue management (re-orderable lists)

### v2.0
- Online music discovery
- Public/open music catalog integration
- Online search and streaming where legally supported

### Future
- Cloud sync
- User accounts
- Enhanced recommendation systems
- Additional personalization

---

### Disclaimer
Rachan is an independent local music player and is not affiliated with, endorsed by, or in any way associated with Spotify or other streaming companies.
