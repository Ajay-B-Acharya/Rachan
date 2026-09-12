import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/services/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Implements the injectable public player API without plugins or network I/O.
class TestAudioPlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final processing = StreamController<ProcessingState>.broadcast(sync: true);
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final sources = <UriAudioSource>[];
  final plays = <Completer<void>>[];
  final seeks = <Duration?>[];
  Completer<Duration?>? loadGate;
  Completer<void>? stopGate;
  Object? failLoad;
  bool disposed = false;
  bool mutating = false;
  int stopCalls = 0;
  int pauseCalls = 0;

  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<ProcessingState> get processingStateStream => processing.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;

  void emit(bool playing, ProcessingState state) {
    this.playing = playing;
    processingState = state;
    states.add(PlayerState(playing, state));
    processing.add(state);
  }

  @override
  Future<void> stop() async {
    expect(mutating, isFalse, reason: 'Player mutations must be serialized');
    mutating = true;
    stopCalls++;
    try {
      await stopGate?.future;
      emit(false, ProcessingState.idle);
    } finally {
      mutating = false;
    }
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    expect(mutating, isFalse);
    mutating = true;
    sources.add(source as UriAudioSource);
    try {
      emit(false, ProcessingState.loading);
      final duration = loadGate == null
          ? const Duration(minutes: 4)
          : await loadGate!.future;
      if (failLoad != null) throw failLoad!;
      emit(false, ProcessingState.ready);
      return duration;
    } finally {
      mutating = false;
    }
  }

  @override
  Future<void> play() {
    final completion = Completer<void>();
    plays.add(completion);
    emit(true, ProcessingState.ready);
    return completion.future;
  }

  @override
  Future<void> pause() async {
    expect(mutating, isFalse);
    pauseCalls++;
    emit(false, processingState);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    expect(mutating, isFalse);
    seeks.add(position);
  }

  @override
  Future<void> dispose() async {
    expect(mutating, isFalse);
    disposed = true;
    for (final completion in plays) {
      if (!completion.isCompleted) completion.complete();
    }
    await Future.wait([
      states.close(),
      positions.close(),
      processing.close(),
      events.close(),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Song localSong([int id = 0]) => Song(
  id: id,
  title: 'Local $id',
  artist: 'Artist',
  album: 'Album',
  duration: const Duration(minutes: 2),
  audioPath: '/test/file$id.mp3',
  gradientId: id,
);

Song onlineSong([String providerId = 'abc123']) => Song(
  id: 0,
  providerId: providerId,
  source: SongSource.online,
  title: 'Online $providerId',
  artist: 'Online artist',
  album: 'Audius',
  duration: const Duration(minutes: 3),
  audioPath: '',
  gradientId: 0,
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestAudioPlayer player;
  late AudioService service;
  const favoritesKey = 'harmoniq_favorites_v1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    player = TestAudioPlayer();
    service = AudioService(audioPlayer: player);
    await flush();
  });

  tearDown(() async {
    service.dispose();
    await flush();
  });

  test('saved nonlocal records migrate without collapsing original keys', () {
    final local = localSong();
    final legacy = local.copyWith(source: SongSource.legacy);
    Song saved(String key) =>
        Song.fromJson({...local.toJson(), 'source': 'youtube', 'videoId': key});
    final first = saved('abcdefghijk');
    final second = saved('lmnopqrstuv');
    expect(SongSource.values, [
      SongSource.local,
      SongSource.legacy,
      SongSource.online,
    ]);
    expect(first.source, SongSource.legacy);
    expect(first.legacyId, 'abcdefghijk');
    expect(local.identity, 'local:0');
    expect(legacy.identity, 'legacy:0');
    expect({local, legacy, first, second}, hasLength(4));
    expect(first, first.copyWith(id: 123, title: 'Updated'));
    expect(first.hashCode, first.copyWith(id: 123).hashCode);
    expect(first.toJson().containsKey('videoId'), isFalse);
    expect(Song.fromJson(first.toJson()), first);
    expect(Song.fromJson({...local.toJson()}..remove('source')), local);
    expect(Song.fromJson({...local.toJson(), 'source': 'jamendo'}), legacy);
  });

  test(
    'saved legacy favorites survive save/reload and remain removable',
    () async {
      final oldRecords = ['abcdefghijk', 'lmnopqrstuv']
          .map(
            (key) => {
              ...localSong().toJson(),
              'source': 'youtube',
              'videoId': key,
              'title': 'Saved $key',
            },
          )
          .toList();
      service.dispose();
      await flush();
      SharedPreferences.setMockInitialValues({
        favoritesKey: oldRecords.map(jsonEncode).toList(),
      });
      player = TestAudioPlayer();
      service = AudioService(audioPlayer: player);
      await flush();
      expect(service.favorites, hasLength(2));
      expect(service.favorites.toSet(), hasLength(2));
      expect(service.playlists.first.songs, service.favorites);
      for (final song in service.favorites) {
        await service.playSong(song);
      }
      expect(service.currentSong, isNull);
      expect(player.sources, isEmpty);
      service.toggleFavorite(localSong());
      await flush();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(favoritesKey)!;
      expect(saved, hasLength(3));
      expect(
        saved.map((s) => Song.fromJson(jsonDecode(s))).toSet(),
        hasLength(3),
      );
      service.dispose();
      await flush();
      player = TestAudioPlayer();
      service = AudioService(audioPlayer: player);
      await flush();
      final remove = service.favorites.first;
      service.toggleFavorite(remove);
      expect(service.favorites, hasLength(2));
      expect(service.favorites.any((song) => song == remove), isFalse);
      expect(
        service.favorites.any((song) => song.legacyId == 'lmnopqrstuv'),
        isTrue,
      );
      expect(service.isSongFavorite(localSong()), isTrue);
    },
  );

  test(
    'metadata loads immediately and play does not await track completion',
    () async {
      player.loadGate = Completer<Duration?>();
      final song = localSong();
      final selected = service.playSong(song);
      expect(service.currentSong, song);
      expect(service.isLoading, isTrue);
      expect(service.wantsToPlay, isTrue);
      expect(service.isPlaying, isFalse);
      expect(service.canSeek, isFalse);
      await service.seek(const Duration(seconds: 45));
      expect(player.seeks, isEmpty);
      player.loadGate!.complete(const Duration(minutes: 4));
      await selected.timeout(const Duration(seconds: 1));
      expect(player.plays.single.isCompleted, isFalse);
      expect(service.isLoading, isFalse);
      expect(service.isPlaying, isTrue);
      expect(service.canSeek, isTrue);
      final source = player.sources.single;
      final media = source.tag as MediaItem;
      expect(source.uri, Uri.file(song.audioPath));
      expect(media.id, song.identity);
      expect(media.title, song.title);
      expect(media.album, song.album);
      expect(media.artist, song.artist);
      await service.seek(const Duration(seconds: 45));
      expect(player.seeks, [const Duration(seconds: 45)]);
    },
  );

  test('file and content URIs and Windows paths use native sources', () async {
    for (final path in [
      'file:///test/file.mp3',
      'content://media/external/audio/media/42',
      r'C:\Music\file.mp3',
    ]) {
      await service.playSong(localSong().copyWith(audioPath: path));
      expect(
        player.sources.last.uri.scheme,
        path.startsWith('content:') ? 'content' : 'file',
      );
      expect(service.isPlaying, isTrue);
    }
  });

  test(
    'new selection supersedes pending stop before old source installs',
    () async {
      player.stopGate = Completer<void>();
      final first = service.playSong(localSong());
      await flush();
      final second = service.playSong(localSong(1));
      player.stopGate!.complete();
      await Future.wait([first, second]);
      expect(player.sources, hasLength(1));
      expect((player.sources.single.tag as MediaItem).id, 'local:1');
      expect(player.plays, hasLength(1));
    },
  );

  test(
    'pause during loading persists and resume reuses loaded source',
    () async {
      player.loadGate = Completer<Duration?>();
      final selected = service.playSong(localSong());
      await service.togglePlay();
      expect(service.wantsToPlay, isFalse);
      expect(service.isLoading, isTrue);
      player.loadGate!.complete(const Duration(minutes: 4));
      await selected;
      expect(player.plays, isEmpty);
      expect(service.canSeek, isTrue);
      await service.togglePlay();
      expect(player.sources, hasLength(1));
      expect(service.isPlaying, isTrue);
    },
  );

  test(
    'duration updates preserve favorite changes made during loading',
    () async {
      player.loadGate = Completer<Duration?>();
      final song = localSong();
      service.addSongToPlaylist(song, service.playlists[1]);
      final selected = service.playSong(song);
      await flush();
      service.toggleFavorite(song);
      await service.togglePlay();
      player.loadGate!.complete(const Duration(minutes: 5));
      await selected;
      expect(player.plays, isEmpty);
      for (final updated in [
        service.currentSong!,
        service.songs.single,
        service.queue.single,
        service.favorites.single,
        service.playlists[1].songs.single,
      ]) {
        expect(updated.isFavorite, isTrue);
        expect(updated.duration, const Duration(minutes: 5));
      }
    },
  );

  test(
    'source installs serialize and ignore old progress and completion',
    () async {
      final a = localSong();
      final b = localSong(1);
      player.loadGate = Completer<Duration?>();
      final first = service.playSong(a, contextQueue: [a, b]);
      await flush();
      final second = service.playSong(b);
      player.positions.add(const Duration(seconds: 99));
      player.emit(true, ProcessingState.completed);
      expect(service.currentSong, b);
      expect(service.playbackPosition, Duration.zero);
      expect(service.isPlaying, isFalse);
      final oldLoad = player.loadGate!;
      player.loadGate = null;
      oldLoad.complete(const Duration(minutes: 9));
      await Future.wait([first, second]);
      expect(player.sources, hasLength(2));
      expect(player.plays, hasLength(1));
      expect(service.currentSong, b);
      expect(service.currentSong!.duration, const Duration(minutes: 4));
      expect(service.songs.first.duration, a.duration);
    },
  );

  test(
    'stop clears immediately and suppresses eventual play from load',
    () async {
      player.loadGate = Completer<Duration?>();
      final selected = service.playSong(localSong());
      await flush();
      final stopped = service.stopAndClear();
      expect(service.currentSong, isNull);
      expect(service.isLoading, isFalse);
      expect(service.wantsToPlay, isFalse);
      expect(service.canSeek, isFalse);
      player.loadGate!.complete(const Duration(minutes: 4));
      await Future.wait([selected, stopped]);
      expect(player.plays, isEmpty);
      expect(service.currentSong, isNull);
      expect(service.queue, hasLength(1));
    },
  );

  test(
    'dispose invalidates load without resurrecting player or notifying',
    () async {
      player.loadGate = Completer<Duration?>();
      final selected = service.playSong(localSong());
      await flush();
      var notifications = 0;
      service.addListener(() => notifications++);
      service.dispose();
      player.loadGate!.complete(const Duration(minutes: 4));
      await selected;
      await flush();
      expect(player.disposed, isTrue);
      expect(player.plays, isEmpty);
      expect(notifications, 0);
    },
  );

  test('load failure is sanitized and retry reloads the local file', () async {
    player.failLoad = PlayerException(0, 'Source error /private/secret.mp3');
    await service.playSong(localSong());
    expect(
      service.playbackError,
      'Unable to play this audio. Please try again.',
    );
    expect(service.isPlaying, isFalse);
    expect(service.wantsToPlay, isFalse);
    expect(service.canSeek, isFalse);
    expect(service.isLoading, isFalse);
    expect(player.plays, isEmpty);
    player.failLoad = null;
    await service.retryPlayback();
    expect(player.sources, hasLength(2));
    expect(service.playbackError, isNull);
    expect(service.isPlaying, isTrue);
  });

  test(
    'local access failure and timeout provide safe messages without auto retry',
    () async {
      player.failLoad = PlayerException(0, 'Source error', {
        'originalError': {'cause': 'FileNotFoundException /private/secret.mp3'},
      });
      await service.playSong(localSong());
      await flush();
      expect(service.playbackError, contains('missing or cannot be accessed'));
      expect(service.playbackError, isNot(contains('secret')));
      expect(player.sources, hasLength(1));
      player.failLoad = TimeoutException('/private/secret.mp3');
      await service.retryPlayback();
      expect(
        service.playbackError,
        'Audio playback timed out. Please try again.',
      );
      expect(player.sources, hasLength(2));
      expect(player.plays, isEmpty);
    },
  );

  test('stale source and stream errors cannot fail newer selection', () async {
    final gate = Completer<Duration?>();
    player.loadGate = gate;
    final first = service.playSong(localSong());
    await flush();
    final second = service.playSong(localSong(1));
    player.events.addError(PlayerException(0, 'FileNotFoundException'));
    expect(service.playbackError, isNull);
    player.loadGate = null;
    gate.completeError(PlayerException(0, 'FileNotFoundException'));
    await Future.wait([first, second]);
    expect(service.currentSong, localSong(1));
    expect(service.playbackError, isNull);
    expect(service.isPlaying, isTrue);
    expect(player.plays, hasLength(1));
  });

  test('stream errors stop controls without silently retrying', () async {
    await service.playSong(localSong());
    player.events.addError(
      PlatformException(
        code: 'permission_denied',
        message: '/private/secret.mp3',
      ),
    );
    await flush();
    expect(service.playbackError, contains('storage permission'));
    expect(service.isPlaying, isFalse);
    expect(service.isLoading, isFalse);
    expect(service.wantsToPlay, isFalse);
    expect(service.canSeek, isFalse);
    expect(player.sources, hasLength(1));
  });

  test('late play failure cannot fail new generation', () async {
    await service.playSong(localSong());
    final oldPlay = player.plays.single;
    await service.playSong(localSong(1));
    oldPlay.completeError(PlayerException(0, 'Source error'));
    await flush();
    expect(service.playbackError, isNull);
    expect(service.isPlaying, isTrue);
    player.plays.last.completeError(PlayerException(0, 'Source error'));
    await flush();
    expect(service.playbackError, isNotNull);
    expect(service.isPlaying, isFalse);
    await service.togglePlay();
    expect(service.playbackError, isNull);
    expect(service.isPlaying, isTrue);
  });

  test(
    'native controls synchronize intent and buffering clears loading',
    () async {
      await service.playSong(localSong());
      player.emit(false, ProcessingState.ready);
      expect(service.wantsToPlay, isFalse);
      expect(service.isPlaying, isFalse);
      player.emit(true, ProcessingState.ready);
      expect(service.wantsToPlay, isTrue);
      player.emit(true, ProcessingState.buffering);
      expect(service.isLoading, isTrue);
      expect(service.canSeek, isFalse);
      await service.togglePlay();
      expect(player.pauseCalls, 1);
      expect(service.wantsToPlay, isFalse);
      player.emit(false, ProcessingState.ready);
      expect(service.isLoading, isFalse);
      expect(service.canSeek, isTrue);
      var notifications = 0;
      service.addListener(() => notifications++);
      player.positions.add(const Duration(seconds: 12));
      expect(
        service.playbackPositionNotifier.value,
        const Duration(seconds: 12),
      );
      expect(
        notifications,
        0,
        reason: 'Progress must not rebuild whole screens',
      );
    },
  );

  test('completion advances queue or repeats through native seek', () async {
    final a = localSong();
    final b = localSong(1);
    await service.playSong(a, contextQueue: [a, b]);
    player.emit(true, ProcessingState.completed);
    await flush();
    expect(service.currentSong, b);
    service.toggleRepeat();
    player.emit(true, ProcessingState.completed);
    await flush();
    expect(service.currentSong, b);
    expect(player.seeks.last, Duration.zero);
    expect(player.sources, hasLength(2));
  });

  test(
    'online resolution uses native metadata and preserves a mixed queue',
    () async {
      service.dispose();
      await flush();
      player = TestAudioPlayer();
      final resolved = <String>[];
      service = AudioService(
        audioPlayer: player,
        resolveOnlineAudio: (id) async {
          resolved.add(id);
          return Uri.https('api.audius.co', '/v1/tracks/$id/stream');
        },
      );
      final online = onlineSong().copyWith(
        albumArtUrl: 'https://art.example/cover.jpg',
      );
      final local = localSong();
      await service.playSong(
        online,
        contextQueue: [online, local, onlineSong('../bad')],
      );
      expect(service.queue, [online, local]);
      expect(resolved, ['abc123']);
      expect(player.sources.single.uri.scheme, 'https');
      final media = player.sources.single.tag as MediaItem;
      expect(media.id, online.identity);
      expect(media.title, online.title);
      expect(media.artist, online.artist);
      expect(media.artUri, Uri.parse(online.albumArtUrl!));
      expect(service.isPlaying, isTrue);
      await service.togglePlay();
      expect(player.pauseCalls, 1);
      await service.togglePlay();
      expect(resolved, [
        'abc123',
      ], reason: 'Resume reuses the installed source');
      await service.next();
      expect(service.currentSong, local);
      expect(player.sources.last.uri.scheme, 'file');
      await service.previous();
      expect(service.currentSong, online);
      expect(resolved, ['abc123', 'abc123']);
    },
  );

  test(
    'stale online resolver cannot replace a newer local selection',
    () async {
      service.dispose();
      await flush();
      player = TestAudioPlayer();
      final pending = Completer<Uri>();
      service = AudioService(
        audioPlayer: player,
        resolveOnlineAudio: (_) => pending.future,
      );
      final oldSelection = service.playSong(onlineSong());
      await flush();
      await service.playSong(localSong());
      pending.complete(Uri.https('api.audius.co', '/v1/tracks/abc123/stream'));
      await oldSelection;
      expect(service.currentSong, localSong());
      expect(player.sources, hasLength(1));
      expect(player.sources.single.uri.scheme, 'file');
      expect(service.playbackError, isNull);
      expect(service.isPlaying, isTrue);
    },
  );

  test('online retry resolves afresh and rejects insecure endpoints', () async {
    service.dispose();
    await flush();
    player = TestAudioPlayer();
    var attempts = 0;
    service = AudioService(
      audioPlayer: player,
      resolveOnlineAudio: (_) async {
        attempts++;
        return Uri.parse(
          attempts == 1
              ? 'http://private.example/secret.mp3'
              : 'https://api.audius.co/v1/tracks/abc123/stream',
        );
      },
    );
    await service.playSong(onlineSong());
    expect(player.sources, isEmpty);
    expect(service.playbackError, isNotNull);
    expect(service.playbackError, isNot(contains('private')));
    expect(service.wantsToPlay, isFalse);
    await service.retryPlayback();
    expect(attempts, 2);
    expect(player.sources, hasLength(1));
    expect(service.playbackError, isNull);
    expect(service.isPlaying, isTrue);
  });

  test(
    'queue rejects legacy, remote, empty, and simulated local entries',
    () async {
      final a = localSong();
      final b = localSong(1);
      final rejected = [
        a.copyWith(source: SongSource.legacy),
        a.copyWith(audioPath: 'https://example.com/audio.mp3'),
        a.copyWith(audioPath: 'HTTP://example.com/audio.mp3'),
        a.copyWith(audioPath: ''),
        a.copyWith(audioPath: 'simulated_track'),
        a.copyWith(audioPath: 'relative.mp3'),
      ];
      await service.playSong(a, contextQueue: [a, ...rejected, b]);
      expect(service.queue, [a, b]);
      await service.next();
      expect(service.currentSong, b);
      await service.previous();
      expect(service.currentSong, a);
      await service.skipToIndex(1);
      expect(service.currentSong, b);
      for (final song in rejected) {
        await service.playSong(song, contextQueue: [song]);
      }
      expect(service.currentSong, b);
      expect(service.queue, [a, b]);
      expect(player.sources, hasLength(4));
    },
  );
}
