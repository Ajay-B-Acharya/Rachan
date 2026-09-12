import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../models/playlist.dart';
import 'playback_failure.dart';
import 'online_music_service.dart';

class AudioService extends ChangeNotifier {
  // ── Song registry ──────────────────────────────────────────────────────────
  final List<Song> _songs = [];
  final Map<String, int> _songIndices = {};
  List<Song> get songs => _songs;

  // Lists retain their identity, so consumers must invalidate derived caches
  // using these revisions rather than list identity or playback notifications.
  int _catalogRevision = 0;
  int get catalogRevision => _catalogRevision;
  int _localSongsRevision = 0;
  int get localSongsRevision => _localSongsRevision;
  bool _disposed = false;
  Future<void>? _scanFuture;

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
  final AudioPlayer _player;
  final Future<Uri> Function(String) _resolveOnlineAudio;
  Future<void> _playerMutations = Future<void>.value();
  int _generation = 0;
  int? _readyGeneration;
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String? _playbackError;
  String? get playbackError => _playbackError;
  bool _wantsToPlay = false;
  bool get wantsToPlay => _wantsToPlay;
  bool get canSeek =>
      !_disposed &&
      _currentSong != null &&
      !_isLoading &&
      _playbackError == null &&
      _readyGeneration == _generation;

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
  List<Song> get queue => UnmodifiableListView(_queue);

  int _currentQueueIndex = -1;
  int get currentQueueIndex => _currentQueueIndex;

  // ── Subscriptions ─────────────────────────────────────────────────────────────
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _playerCompleteSub;
  StreamSubscription<PlaybackEvent>? _playbackErrorSub;

  AudioService({
    AudioPlayer? audioPlayer,
    Future<Uri> Function(String)? resolveOnlineAudio,
  }) : _player = audioPlayer ?? AudioPlayer(),
       _resolveOnlineAudio =
           resolveOnlineAudio ?? OnlineMusicService.instance.streamUri {
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
      if (_disposed) return;
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
      final jsonList = _favorites.map((s) => json.encode(s.toJson())).toList();
      await prefs.setStringList(_prefsKeyFavorites, jsonList);
    } catch (e) {
      debugPrint('[AUDIO_SERVICE] Error saving favorites: $e');
    }
  }

  bool isSongFavorite(Song song) =>
      _favorites.any((s) => s.identity == song.identity);

  void _syncFavoriteStates() {
    final favIds = _favorites.map((s) => s.identity).toSet();

    for (int i = 0; i < _songs.length; i++) {
      _songs[i] = _songs[i].copyWith(
        isFavorite: favIds.contains(_songs[i].identity),
      );
    }
    for (int i = 0; i < _localSongs.length; i++) {
      _localSongs[i] = _localSongs[i].copyWith(
        isFavorite: favIds.contains(_localSongs[i].identity),
      );
    }
    for (int i = 0; i < _queue.length; i++) {
      _queue[i] = _queue[i].copyWith(
        isFavorite: favIds.contains(_queue[i].identity),
      );
    }
    if (_currentSong != null) {
      _currentSong = _currentSong!.copyWith(
        isFavorite: favIds.contains(_currentSong!.identity),
      );
    }
    for (final playlist in _playlists.where((p) => p.id != 0)) {
      for (var i = 0; i < playlist.songs.length; i++) {
        final song = playlist.songs[i];
        playlist.songs[i] = song.copyWith(
          isFavorite: favIds.contains(song.identity),
        );
      }
    }

    _catalogRevision++;
    _localSongsRevision++;

    // Sync playlist #0 (Favorites)
    final favPlaylist = _playlists.firstWhere((p) => p.id == 0);
    favPlaylist.songs.clear();
    favPlaylist.songs.addAll(_favorites);
  }

  /// Register tracks in input order; later metadata for an identity wins.
  void registerSongs(List<Song> newSongs) {
    if (_disposed || newSongs.isEmpty) return;
    _registerSongs(newSongs);
    notifyListeners();
  }

  void _registerSongs(List<Song> newSongs) {
    final favIds = _favorites.map((s) => s.identity).toSet();
    for (final song in newSongs) {
      final idx = _songIndices[song.identity];
      final synced = song.copyWith(isFavorite: favIds.contains(song.identity));
      if (idx == null) {
        _songIndices[song.identity] = _songs.length;
        _songs.add(synced);
      } else {
        _songs[idx] = synced;
      }
    }
    _catalogRevision++;
  }

  // Player events have no source ID. Ignore them until the selected generation
  // has finished installing its source, including all stop/load transitions.
  bool get _acceptPlayerEvents => !_disposed && _readyGeneration == _generation;

  void _attachPlayerListeners() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!_acceptPlayerEvents) return;
      final loading =
          state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;
      if (state.playing != _isPlaying ||
          state.playing != _wantsToPlay ||
          loading != _isLoading) {
        // Native notification controls/audio interruptions also change intent.
        _wantsToPlay = state.playing;
        _isPlaying = state.playing;
        _isLoading = loading;
        notifyListeners();
      }
    });
    _playbackErrorSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object error) {
        if (_acceptPlayerEvents) _failPlayback(_generation, error: error);
      },
    );
    _positionSub = _player.positionStream.listen((pos) {
      if (!_acceptPlayerEvents) return;
      _playbackPosition = pos;
      playbackPositionNotifier.value = pos;
    });
    _playerCompleteSub = _player.processingStateStream
        .where((s) => s == ProcessingState.completed)
        .listen((_) {
          if (!_acceptPlayerEvents || !_wantsToPlay) return;
          if (_repeatEnabled) {
            unawaited(_restart(_generation));
          } else {
            unawaited(next());
          }
        });
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  // Serialize source installs and controls; stale generations cannot start play.
  Future<void> _mutatePlayer(Future<void> Function() action) {
    final result = _playerMutations.then((_) => action());
    _playerMutations = result.catchError((Object _) {});
    return result;
  }

  bool _canPlay(Song song) {
    if (song.source == SongSource.online) {
      return Song.isValidProviderId(song.providerId);
    }
    if (song.source != SongSource.local) return false;
    final path = song.audioPath;
    return path.startsWith('content://') ||
        path.startsWith('file://') ||
        path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    if (_disposed || !_canPlay(song)) return;
    _registerSongs([song]);
    if (contextQueue != null) {
      _queue = contextQueue.where(_canPlay).toList();
    }
    _currentQueueIndex = _queue.indexWhere((s) => s.identity == song.identity);
    if (_currentQueueIndex == -1) {
      _queue.add(song);
      _currentQueueIndex = _queue.length - 1;
    }
    await _selectSong(song);
  }

  Future<void> skipToIndex(int index) async {
    if (_disposed ||
        index < 0 ||
        index >= _queue.length ||
        index == _currentQueueIndex ||
        !_canPlay(_queue[index])) {
      return;
    }
    _currentQueueIndex = index;
    await _selectSong(_queue[index]);
  }

  Future<void> _selectSong(Song song) async {
    final generation = ++_generation;
    _readyGeneration = null;
    _currentSong = song.copyWith(isFavorite: isSongFavorite(song));
    _isPlaying = false;
    _wantsToPlay = true;
    _isLoading = true;
    _playbackError = null;
    _playbackPosition = Duration.zero;
    playbackPositionNotifier.value = Duration.zero;
    notifyListeners();

    // Stop the previous source while resolving this generation's next source.
    final stopped =
        _mutatePlayer(() async {
          if (_isCurrent(generation)) await _player.stop();
        }).catchError((Object error) {
          _failPlayback(generation, error: error);
        });
    try {
      final path = song.audioPath;
      final Uri uri;
      if (song.source == SongSource.online) {
        uri = await _resolveOnlineAudio(song.providerId!)
            .timeout(const Duration(seconds: 10));
        if (uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const OnlineMusicException(OnlineMusicFailure.invalidTrack);
        }
      } else {
        uri = path.startsWith('content://') || path.startsWith('file://')
            ? Uri.parse(path)
            : Uri.file(path, windows: RegExp(r'^[A-Za-z]:').hasMatch(path));
      }
      await stopped;
      if (!_isCurrent(generation) || _playbackError != null) return;
      await _mutatePlayer(() async {
        if (!_isCurrent(generation)) return;
        final mediaItem = MediaItem(
          id: song.identity,
          album: song.album,
          title: song.title,
          artist: song.artist,
          duration: song.duration > Duration.zero ? song.duration : null,
          artUri: _artworkUri(song),
        );
        final duration = await _player.setAudioSource(
          AudioSource.uri(uri, tag: mediaItem),
        );
        if (!_isCurrent(generation)) return;
        if (duration != null && duration > Duration.zero) {
          _updateDuration(song.identity, duration);
        }
        _readyGeneration = generation;
        _isLoading = false;
        notifyListeners();
        if (_isCurrent(generation) && _wantsToPlay) _startPlaying(generation);
      });
    } catch (error) {
      _failPlayback(generation, error: error);
    }
  }

  Uri? _artworkUri(Song song) {
    final uri = Uri.tryParse(song.albumArtUrl ?? '');
    if (uri == null) return null;
    if (song.source == SongSource.online) {
      return uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty
          ? uri
          : null;
    }
    return uri.scheme == 'file' || uri.scheme == 'content' ? uri : null;
  }

  void _updateDuration(String identity, Duration duration) {
    final idx = _songIndices[identity];
    if (idx != null) {
      _songs[idx] = _songs[idx].copyWith(duration: duration);
      _catalogRevision++;
    }
    void update(List<Song> songs) {
      for (var i = 0; i < songs.length; i++) {
        if (songs[i].identity == identity) {
          songs[i] = songs[i].copyWith(duration: duration);
        }
      }
    }

    if (_localSongs.any((song) => song.identity == identity)) {
      update(_localSongs);
      _localSongsRevision++;
    }
    update(_queue);
    update(_favorites);
    for (final playlist in _playlists) {
      update(playlist.songs);
    }
    // Use current metadata, not the snapshot from before loading/favoriting.
    _currentSong = _currentSong!.copyWith(duration: duration);
  }

  void _failPlayback(int generation, {Object? error}) {
    if (!_isCurrent(generation)) return;
    _readyGeneration = null;
    _isLoading = false;
    _isPlaying = false;
    _wantsToPlay = false;
    _playbackError = error is OnlineMusicException
        ? error.message
        : classifyPlaybackFailure(
            error,
            online: _currentSong?.source == SongSource.online,
          ).message();
    notifyListeners();
    // Never print exceptions: platform errors can include private file paths.
    unawaited(
      _mutatePlayer(() async {
        if (_isCurrent(generation)) await _player.stop();
      }).catchError((Object _) {}),
    );
  }

  void _startPlaying(int generation) {
    if (!_isCurrent(generation) || !_wantsToPlay) return;
    // just_audio's play future completes only when paused/stopped/completed.
    unawaited(
      Future<void>.sync(_player.play).catchError((Object error) {
        _failPlayback(generation, error: error);
      }),
    );
  }

  Future<void> _restart(int generation) async {
    try {
      await _mutatePlayer(() async {
        if (!_isCurrent(generation)) return;
        await _player.seek(Duration.zero);
        if (_isCurrent(generation) && _wantsToPlay) _startPlaying(generation);
      });
    } catch (error) {
      _failPlayback(generation, error: error);
    }
  }

  Future<void> retryPlayback() async {
    if (_disposed || _currentSong == null || !_canPlay(_currentSong!)) return;
    await _selectSong(_currentSong!);
  }

  Future<void> togglePlay() async {
    if (_disposed || _currentSong == null || !_canPlay(_currentSong!)) return;
    if (_playbackError != null) {
      await retryPlayback();
      return;
    }
    _wantsToPlay = !_wantsToPlay;
    if (!_wantsToPlay) _isPlaying = false;
    notifyListeners();
    if (_readyGeneration != _generation) return;
    final generation = _generation;
    try {
      await _mutatePlayer(() async {
        if (!_isCurrent(generation)) return;
        if (!_wantsToPlay) {
          await _player.pause();
        } else if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
          if (_isCurrent(generation) && _wantsToPlay) _startPlaying(generation);
        } else {
          _startPlaying(generation);
        }
      });
    } catch (error) {
      _failPlayback(generation, error: error);
    }
  }

  /// Dismiss immediately and invalidate pending loads. Keep the queue for reuse.
  Future<void> stopAndClear() async {
    if (_disposed) return;
    final generation = ++_generation;
    _readyGeneration = null;
    _currentSong = null;
    _currentQueueIndex = -1;
    _isLoading = false;
    _playbackError = null;
    _wantsToPlay = false;
    _isPlaying = false;
    _playbackPosition = Duration.zero;
    playbackPositionNotifier.value = Duration.zero;
    notifyListeners();
    try {
      await _mutatePlayer(() async {
        if (_isCurrent(generation)) await _player.stop();
      });
    } catch (_) {
      // State remains cleared; do not leak platform error details.
    }
  }

  Future<void> seek(Duration position) async {
    if (!canSeek) return;
    final generation = _generation;
    _playbackPosition = position;
    playbackPositionNotifier.value = position;
    try {
      await _mutatePlayer(() async {
        if (_isCurrent(generation) && canSeek) await _player.seek(position);
      });
    } catch (error) {
      _failPlayback(generation, error: error);
    }
  }

  Future<void> next() async {
    if (_disposed || _queue.isEmpty) return;
    final index = _shuffleEnabled
        ? Random().nextInt(_queue.length)
        : (_currentQueueIndex + 1) % _queue.length;
    if (!_canPlay(_queue[index])) return;
    _currentQueueIndex = index;
    await _selectSong(_queue[index]);
  }

  Future<void> previous() async {
    if (_disposed || _queue.isEmpty) return;
    if (_playbackPosition.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    final index = _shuffleEnabled
        ? Random().nextInt(_queue.length)
        : (_currentQueueIndex - 1 + _queue.length) % _queue.length;
    if (!_canPlay(_queue[index])) return;
    _currentQueueIndex = index;
    await _selectSong(_queue[index]);
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
      _favorites.removeWhere((s) => s.identity == song.identity);
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
    if (!playlist.songs.any((s) => s.identity == song.identity)) {
      playlist.songs.add(song);
      notifyListeners();
    }
  }

  void removeSongFromPlaylist(Song song, Playlist playlist) {
    playlist.songs.removeWhere((s) => s.identity == song.identity);
    notifyListeners();
  }

  // ── Local storage scanning ────────────────────────────────────────────────────
  Future<void> scanLocalSongs({bool forcePrompt = false}) {
    if (_disposed) return Future<void>.value();
    return _scanFuture ??= Future<void>.microtask(
      () => _scanLocalSongs(forcePrompt: forcePrompt),
    ).whenComplete(() => _scanFuture = null);
  }

  Future<void> _scanLocalSongs({required bool forcePrompt}) async {
    if (_disposed) return;
    _isScanning = true;
    // Keep the last successful snapshot if the refresh fails.
    notifyListeners();

    try {
      bool granted =
          await _platform.invokeMethod<bool>('checkPermission') ?? false;

      if (_disposed) return;
      if (!granted || forcePrompt) {
        granted =
            await _platform.invokeMethod<bool>('requestPermission') ?? false;
      }
      if (_disposed) return;
      debugPrint('[AUDIO_SOURCE] Storage permission granted=$granted');

      if (granted) {
        final List<dynamic>? songsData = await _platform
            .invokeMethod<List<dynamic>>('fetchLocalSongs');
        if (_disposed) return;
        if (songsData != null) {
          final favIds = _favorites.map((s) => s.identity).toSet();
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
              isFavorite: favIds.contains('local:$id'),
            );
          }).toList();
          _localSongsRevision++;
          // Drop removed local files without touching other source identities.
          final localIds = _localSongs.map((song) => song.identity).toSet();
          _songs.removeWhere(
            (song) =>
                song.source == SongSource.local &&
                !localIds.contains(song.identity),
          );
          _songIndices.clear();
          for (var i = 0; i < _songs.length; i++) {
            _songIndices[_songs[i].identity] = i;
          }
          _registerSongs(_localSongs);
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
      if (!_disposed) notifyListeners();
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _readyGeneration = null;
    _isLoading = false;
    _isPlaying = false;
    _wantsToPlay = false;
    playbackPositionNotifier.dispose();
    unawaited(_playerStateSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_playerCompleteSub?.cancel());
    unawaited(_playbackErrorSub?.cancel());
    unawaited(_mutatePlayer(_player.dispose).catchError((Object _) {}));
    super.dispose();
  }
}
