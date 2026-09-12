import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../models/playlist.dart';

class AudioService extends ChangeNotifier {
  // ── Global song registry (populated by loaded online & local tracks) ─────────
  final List<Song> _songs = [];
  List<Song> get songs => _songs;

  late List<Playlist> _playlists;
  List<Playlist> get playlists => _playlists;

  // ── Persistent Favorites ──────────────────────────────────────────────────────
  static const String _prefsKeyFavorites = 'harmoniq_favorites_v1';
  List<Song> _favorites = [];
  List<Song> get favorites => _favorites;

  // ── Local storage scanning ───────────────────────────────────────────────────
  static const _platform = MethodChannel('com.example.harmoniq/local_music');
  List<Song> _localSongs = [];
  List<Song> get localSongs => _localSongs;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  // ── Real audio player ────────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();

  // ── Playback state (driven by the real player) ───────────────────────────────
  Song? _currentSong;
  Song? get currentSong => _currentSong;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Duration _playbackPosition = Duration.zero;
  Duration get playbackPosition => _playbackPosition;

  // Dedicated notifier for 60fps seek bar updates without rebuilding main screens
  final ValueNotifier<Duration> playbackPositionNotifier =
      ValueNotifier<Duration>(Duration.zero);

  bool _shuffleEnabled = false;
  bool get shuffleEnabled => _shuffleEnabled;

  bool _repeatEnabled = false;
  bool get repeatEnabled => _repeatEnabled;

  List<Song> _queue = [];
  List<Song> get queue => _queue;

  int _currentQueueIndex = -1;
  int get currentQueueIndex => _currentQueueIndex;

  // ── Subscriptions ─────────────────────────────────────────────────────────────
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _playerCompleteSub;

  AudioService() {
    _playlists = [
      Playlist(id: 0, name: "Favorites", songs: [], gradientId: 0),
      Playlist(id: 1, name: "Chill Vibes", songs: [], gradientId: 1),
      Playlist(id: 2, name: "Workout", songs: [], gradientId: 5),
      Playlist(id: 3, name: "Focus & Flow", songs: [], gradientId: 7),
    ];

    _attachPlayerListeners();
    _loadFavorites();
  }

  // ── Persistent Favorites Loading & Saving ────────────────────────────────────
  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_prefsKeyFavorites) ?? [];
      _favorites = jsonList.map((str) {
        final map = json.decode(str) as Map<String, dynamic>;
        return Song.fromJson(map).copyWith(isFavorite: true);
      }).toList();

      // Sync Favorites playlist
      final favPlaylist = _playlists.firstWhere((p) => p.id == 0);
      favPlaylist.songs.clear();
      favPlaylist.songs.addAll(_favorites);

      _syncFavoriteStates();
      notifyListeners();
    } catch (e) {
      debugPrint('[AUDIO_SERVICE] Error loading favorites: $e');
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList =
          _favorites.map((s) => json.encode(s.toJson())).toList();
      await prefs.setStringList(_prefsKeyFavorites, jsonList);
    } catch (e) {
      debugPrint('[AUDIO_SERVICE] Error saving favorites: $e');
    }
  }

  bool isSongFavorite(Song song) => _favorites.any((s) => s.id == song.id);

  void _syncFavoriteStates() {
    final favIds = _favorites.map((s) => s.id).toSet();

    for (int i = 0; i < _songs.length; i++) {
      _songs[i] = _songs[i].copyWith(isFavorite: favIds.contains(_songs[i].id));
    }
    for (int i = 0; i < _localSongs.length; i++) {
      _localSongs[i] =
          _localSongs[i].copyWith(isFavorite: favIds.contains(_localSongs[i].id));
    }
    for (int i = 0; i < _queue.length; i++) {
      _queue[i] =
          _queue[i].copyWith(isFavorite: favIds.contains(_queue[i].id));
    }
    if (_currentSong != null) {
      _currentSong = _currentSong!
          .copyWith(isFavorite: favIds.contains(_currentSong!.id));
    }

    // Sync playlist #0 (Favorites)
    final favPlaylist = _playlists.firstWhere((p) => p.id == 0);
    favPlaylist.songs.clear();
    favPlaylist.songs.addAll(_favorites);
  }

  /// Register discovered/fetched online songs into global cache
  void registerSongs(List<Song> newSongs) {
    final favIds = _favorites.map((s) => s.id).toSet();
    for (final song in newSongs) {
      final idx = _songs.indexWhere((s) => s.id == song.id);
      final synced = song.copyWith(isFavorite: favIds.contains(song.id));
      if (idx == -1) {
        _songs.add(synced);
      } else {
        _songs[idx] = synced;
      }
    }
  }

  // ── Player listener wiring ────────────────────────────────────────────────────
  void _attachPlayerListeners() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      final playing = state.playing;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        notifyListeners();
      }
    });

    _positionSub = _player.positionStream.listen((pos) {
      _playbackPosition = pos;
      playbackPositionNotifier.value = pos;
    });

    _playerCompleteSub = _player.processingStateStream
        .where((s) => s == ProcessingState.completed)
        .listen((_) {
          debugPrint('[AUDIO_PLAYING] Track completed, advancing to next.');
          if (_repeatEnabled) {
            _player.seek(Duration.zero).then((_) => _player.play());
          } else {
            next();
          }
        });
  }

  // ── Core playback ─────────────────────────────────────────────────────────────
  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    debugPrint(
      '[SONG_SELECTED] title="${song.title}" id=${song.id} source=${song.source} path="${song.audioPath}"',
    );

    // Register song in global song cache
    registerSongs([song]);

    // Update queue
    if (contextQueue != null) {
      _queue = List.from(contextQueue);
      _currentQueueIndex = _queue.indexWhere((s) => s.id == song.id);
      if (_currentQueueIndex == -1) {
        _queue.add(song);
        _currentQueueIndex = _queue.length - 1;
      }
    } else {
      if (!_queue.any((s) => s.id == song.id)) {
        _queue.add(song);
      }
      _currentQueueIndex = _queue.indexWhere((s) => s.id == song.id);
    }

    _currentSong = song.copyWith(isFavorite: isSongFavorite(song));
    _playbackPosition = Duration.zero;
    playbackPositionNotifier.value = Duration.zero;
    notifyListeners();

    await _loadAndPlay(_currentSong!);
  }

  Future<void> skipToIndex(int index) async {
    if (_queue.isEmpty || index < 0 || index >= _queue.length) return;
    if (_currentQueueIndex == index) return;
    _currentQueueIndex = index;
    _currentSong = _queue[index].copyWith(isFavorite: isSongFavorite(_queue[index]));
    _playbackPosition = Duration.zero;
    playbackPositionNotifier.value = Duration.zero;
    notifyListeners();
    await _loadAndPlay(_currentSong!);
  }

  Future<void> _loadAndPlay(Song song) async {
    final path = song.audioPath;

    if (path.isEmpty || path.startsWith('simulated_')) {
      debugPrint('[AUDIO_SOURCE] Simulated/empty song detected. path="$path"');
      return;
    }

    debugPrint('[AUDIO_SOURCE] uri="$path"');

    try {
      await _player.stop();

      final mediaItem = MediaItem(
        id: song.id.toString(),
        album: song.album,
        title: song.title,
        artist: song.artist,
        duration: song.duration > Duration.zero ? song.duration : null,
        artUri: (song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty)
            ? Uri.tryParse(song.albumArtUrl!)
            : null,
      );

      final AudioSource source;
      if (path.startsWith('http://') || path.startsWith('https://')) {
        // Online Jamendo MP3 stream — progressive HTTP streaming without full download
        debugPrint('[AUDIO_LOADING] Loading online Jamendo HTTP stream: $path');
        source = AudioSource.uri(Uri.parse(path), tag: mediaItem);
      } else if (path.startsWith('content://')) {
        // Android MediaStore content URI
        debugPrint('[AUDIO_LOADING] Loading as content:// URI');
        source = AudioSource.uri(Uri.parse(path), tag: mediaItem);
      } else if (path.startsWith('/') || path.startsWith('file://')) {
        // Absolute local file path
        final fileUri = path.startsWith('file://')
            ? Uri.parse(path)
            : Uri.file(path);
        debugPrint('[AUDIO_LOADING] Loading as file URI: $fileUri');
        source = AudioSource.uri(fileUri, tag: mediaItem);
      } else {
        debugPrint('[AUDIO_ERROR] Unrecognised path format: "$path"');
        return;
      }

      final duration = await _player.setAudioSource(source);
      debugPrint('[AUDIO_READY] duration=$duration');

      if (duration != null && duration > Duration.zero) {
        final idx = _songs.indexWhere((s) => s.id == song.id);
        if (idx != -1) {
          _songs[idx] = _songs[idx].copyWith(duration: duration);
        }
        final localIdx = _localSongs.indexWhere((s) => s.id == song.id);
        if (localIdx != -1) {
          _localSongs[localIdx] =
              _localSongs[localIdx].copyWith(duration: duration);
        }
        final qIdx = _queue.indexWhere((s) => s.id == song.id);
        if (qIdx != -1) {
          _queue[qIdx] = _queue[qIdx].copyWith(duration: duration);
        }
        _currentSong = song.copyWith(duration: duration);
        notifyListeners();
      }

      await _player.play();
      debugPrint('[AUDIO_PLAYING] "${song.title}" is now playing.');
    } on PlayerException catch (e) {
      debugPrint(
        '[AUDIO_ERROR] PlayerException code=${e.code} message=${e.message}',
      );
    } on PlayerInterruptedException catch (e) {
      debugPrint('[AUDIO_ERROR] PlayerInterruptedException: ${e.message}');
    } catch (e, stack) {
      debugPrint('[AUDIO_ERROR] Unexpected error: $e\n$stack');
    }
  }

  Future<void> togglePlay() async {
    if (_currentSong == null) return;

    final path = _currentSong!.audioPath;
    if (path.isEmpty || path.startsWith('simulated_')) {
      _isPlaying = !_isPlaying;
      notifyListeners();
      return;
    }

    if (_player.playing) {
      debugPrint('[AUDIO_PLAYING] Pausing "${_currentSong!.title}"');
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.idle ||
          _player.processingState == ProcessingState.completed) {
        await _loadAndPlay(_currentSong!);
      } else {
        debugPrint('[AUDIO_PLAYING] Resuming "${_currentSong!.title}"');
        await _player.play();
      }
    }
  }

  /// Stop playback entirely and dismiss the current song.
  /// Clears [_currentSong] so the mini player / Now Playing have nothing
  /// to show. The queue is kept so a fresh [playSong] call works normally.
  Future<void> stopAndClear() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[AUDIO_ERROR] stopAndClear failed: $e');
    }
    _currentSong = null;
    _currentQueueIndex = -1;
    _isPlaying = false;
    _playbackPosition = Duration.zero;
    playbackPositionNotifier.value = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (_currentSong == null) return;
    _playbackPosition = position;
    playbackPositionNotifier.value = position;

    final path = _currentSong!.audioPath;
    if (path.isEmpty || path.startsWith('simulated_')) {
      notifyListeners();
      return;
    }

    await _player.seek(position);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_shuffleEnabled) {
      _currentQueueIndex = Random().nextInt(_queue.length);
    } else {
      _currentQueueIndex = (_currentQueueIndex + 1) % _queue.length;
    }
    _currentSong = _queue[_currentQueueIndex].copyWith(
      isFavorite: isSongFavorite(_queue[_currentQueueIndex]),
    );
    _playbackPosition = Duration.zero;
    playbackPositionNotifier.value = Duration.zero;
    notifyListeners();
    await _loadAndPlay(_currentSong!);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_playbackPosition.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_shuffleEnabled) {
      _currentQueueIndex = Random().nextInt(_queue.length);
    } else {
      _currentQueueIndex =
          (_currentQueueIndex - 1 + _queue.length) % _queue.length;
    }
    _currentSong = _queue[_currentQueueIndex].copyWith(
      isFavorite: isSongFavorite(_queue[_currentQueueIndex]),
    );
    _playbackPosition = Duration.zero;
    playbackPositionNotifier.value = Duration.zero;
    notifyListeners();
    await _loadAndPlay(_currentSong!);
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
  }

  void toggleRepeat() {
    _repeatEnabled = !_repeatEnabled;
    notifyListeners();
  }

  void toggleFavorite(Song song) {
    final isFav = isSongFavorite(song);
    if (isFav) {
      _favorites.removeWhere((s) => s.id == song.id);
    } else {
      _favorites.add(song.copyWith(isFavorite: true));
    }
    _saveFavorites();
    _syncFavoriteStates();
    notifyListeners();
  }

  // ── Playlist management ───────────────────────────────────────────────────────
  void createPlaylist(String name) {
    _playlists.add(
      Playlist(
        id: _playlists.length,
        name: name,
        songs: [],
        gradientId: _playlists.length,
      ),
    );
    notifyListeners();
  }

  void addSongToPlaylist(Song song, Playlist playlist) {
    if (!playlist.songs.any((s) => s.id == song.id)) {
      playlist.songs.add(song);
      notifyListeners();
    }
  }

  void removeSongFromPlaylist(Song song, Playlist playlist) {
    playlist.songs.removeWhere((s) => s.id == song.id);
    notifyListeners();
  }

  // ── Local storage scanning ────────────────────────────────────────────────────
  Future<void> scanLocalSongs({bool forcePrompt = false}) async {
    _isScanning = true;
    _localSongs = [];
    notifyListeners();

    try {
      bool granted =
          await _platform.invokeMethod<bool>('checkPermission') ?? false;

      if (!granted || forcePrompt) {
        granted =
            await _platform.invokeMethod<bool>('requestPermission') ?? false;
      }
      debugPrint('[AUDIO_SOURCE] Storage permission granted=$granted');

      if (granted) {
        final List<dynamic>? songsData = await _platform
            .invokeMethod<List<dynamic>>('fetchLocalSongs');
        if (songsData != null) {
          final favIds = _favorites.map((s) => s.id).toSet();
          _localSongs = songsData.map((data) {
            final map = Map<String, dynamic>.from(data as Map);
            final int id = map['id'] as int;
            final int durationMs = (map['duration'] as int?) ?? 0;
            final String path = (map['path'] as String?) ?? '';
            return Song(
              id: id,
              title: (map['title'] as String?) ?? 'Unknown Title',
              artist: (map['artist'] as String?) ?? 'Unknown Artist',
              album: (map['album'] as String?) ?? 'Local Storage',
              duration: Duration(milliseconds: durationMs),
              audioPath: path,
              gradientId: id.abs(),
              source: SongSource.local,
              isFavorite: favIds.contains(id),
            );
          }).toList();
          registerSongs(_localSongs);
          debugPrint(
            '[AUDIO_SOURCE] Scanned ${_localSongs.length} local songs.',
          );
        }
      } else {
        debugPrint('[AUDIO_ERROR] Storage permission was denied by the user.');
      }
    } catch (e, stack) {
      debugPrint('[AUDIO_ERROR] scanLocalSongs failed: $e\n$stack');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    playbackPositionNotifier.dispose();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _playerCompleteSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
