import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../models/playlist.dart';
import '../data/sample_data.dart';

class AudioService extends ChangeNotifier {
  // ── Sample song catalog (always available) ──────────────────────────────────
  final List<Song> _songs = List.from(SampleData.songs);
  List<Song> get songs => _songs;

  late List<Playlist> _playlists;
  List<Playlist> get playlists => _playlists;

  // ── Local storage scanning ───────────────────────────────────────────────────
  static const _platform = MethodChannel('com.example.rachan/local_music');
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
    _playlists = SampleData.getPlaylists(_songs);

    // Pre-select the first sample song so the mini-player is ready.
    if (_songs.isNotEmpty) {
      _currentSong = _songs[0];
      _queue = List.from(_songs);
      _currentQueueIndex = 0;
    }

    _attachPlayerListeners();
  }

  // ── Player listener wiring ────────────────────────────────────────────────────
  void _attachPlayerListeners() {
    // Track is/playing state
    _playerStateSub = _player.playerStateStream.listen((state) {
      final playing = state.playing;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        notifyListeners();
      }
    });

    // Real-time position updates
    _positionSub = _player.positionStream.listen((pos) {
      _playbackPosition = pos;
      notifyListeners();
    });

    // Auto-advance to next song on natural completion
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
      '[SONG_SELECTED] title="${song.title}" id=${song.id} path="${song.audioPath}"',
    );

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

    _currentSong = song;
    _playbackPosition = Duration.zero;
    notifyListeners();

    await _loadAndPlay(song);
  }

  Future<void> _loadAndPlay(Song song) async {
    final path = song.audioPath;

    // Sample songs have no real path — skip audio loading gracefully.
    if (path.isEmpty || path.startsWith('simulated_')) {
      debugPrint(
        '[AUDIO_SOURCE] Sample song detected — no real audio to play. path="$path"',
      );
      return;
    }

    debugPrint('[AUDIO_SOURCE] uri="$path"');

    try {
      await _player.stop();

      final AudioSource source;
      if (path.startsWith('content://')) {
        // Android MediaStore content URI — must use Uri.parse, NOT a file path
        debugPrint('[AUDIO_LOADING] Loading as content:// URI');
        source = AudioSource.uri(Uri.parse(path));
      } else if (path.startsWith('/') || path.startsWith('file://')) {
        // Absolute file path — wrap as file URI
        final fileUri = path.startsWith('file://')
            ? Uri.parse(path)
            : Uri.file(path);
        debugPrint('[AUDIO_LOADING] Loading as file URI: $fileUri');
        source = AudioSource.uri(fileUri);
      } else {
        debugPrint('[AUDIO_ERROR] Unrecognised path format: "$path"');
        return;
      }

      final duration = await _player.setAudioSource(source);
      debugPrint('[AUDIO_READY] duration=$duration');

      // Update the song's duration from the real file metadata.
      if (duration != null && duration > Duration.zero) {
        final idx = _songs.indexWhere((s) => s.id == song.id);
        if (idx != -1) {
          _songs[idx] = _songs[idx].copyWith(duration: duration);
        }
        final localIdx = _localSongs.indexWhere((s) => s.id == song.id);
        if (localIdx != -1) {
          _localSongs[localIdx] = _localSongs[localIdx].copyWith(
            duration: duration,
          );
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
      // Sample songs — toggle a fake state for UI feedback
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

  Future<void> seek(Duration position) async {
    if (_currentSong == null) return;
    _playbackPosition = position;
    notifyListeners();

    final path = _currentSong!.audioPath;
    if (path.isEmpty || path.startsWith('simulated_')) return;

    await _player.seek(position);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_shuffleEnabled) {
      _currentQueueIndex = Random().nextInt(_queue.length);
    } else {
      _currentQueueIndex = (_currentQueueIndex + 1) % _queue.length;
    }
    _currentSong = _queue[_currentQueueIndex];
    _playbackPosition = Duration.zero;
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
    _currentSong = _queue[_currentQueueIndex];
    _playbackPosition = Duration.zero;
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
    void updateInList(List<Song> list) {
      final idx = list.indexWhere((s) => s.id == song.id);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(isFavorite: !list[idx].isFavorite);
      }
    }

    updateInList(_songs);
    updateInList(_localSongs);

    final qIdx = _queue.indexWhere((s) => s.id == song.id);
    if (qIdx != -1) {
      _queue[qIdx] = _queue[qIdx].copyWith(
        isFavorite: !_queue[qIdx].isFavorite,
      );
    }

    final updated = _songs.firstWhere(
      (s) => s.id == song.id,
      orElse: () =>
          _localSongs.firstWhere((s) => s.id == song.id, orElse: () => song),
    );
    if (_currentSong?.id == song.id) _currentSong = updated;

    for (final pl in _playlists) {
      final pIdx = pl.songs.indexWhere((s) => s.id == song.id);
      if (pIdx != -1) pl.songs[pIdx] = updated;
    }
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
  Future<void> scanLocalSongs() async {
    _isScanning = true;
    _localSongs = [];
    notifyListeners();

    try {
      final granted =
          await _platform.invokeMethod<bool>('requestPermission') ?? false;
      debugPrint('[AUDIO_SOURCE] Storage permission granted=$granted');

      if (granted) {
        final List<dynamic>? songsData = await _platform
            .invokeMethod<List<dynamic>>('fetchLocalSongs');
        if (songsData != null) {
          _localSongs = songsData.map((data) {
            final map = Map<String, dynamic>.from(data as Map);
            final int id = map['id'] as int;
            final int durationMs = (map['duration'] as int?) ?? 0;
            final String path = (map['path'] as String?) ?? '';
            debugPrint(
              '[AUDIO_SOURCE] Scanned: id=$id title="${map['title']}" path="$path"',
            );
            return Song(
              id: id,
              title: (map['title'] as String?) ?? 'Unknown Title',
              artist: (map['artist'] as String?) ?? 'Unknown Artist',
              album: (map['album'] as String?) ?? 'Unknown Album',
              duration: Duration(milliseconds: durationMs),
              audioPath: path,
              gradientId: id,
            );
          }).toList();
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
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _playerCompleteSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
