import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/models/youtube_video.dart';
import 'package:harmoniq/services/audio_service.dart';
import 'package:harmoniq/services/youtube_audio_native.dart' as native;
import 'package:harmoniq/services/youtube_audio_stub.dart' as web;
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
    pauseCalls++;
    emit(false, processingState);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
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

Song youtubeSong([String id = 'abcdefghijk']) => Song.fromYoutube(
  YoutubeVideo(
    id: id,
    title: 'Video $id',
    artist: 'Channel',
    thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
    duration: const Duration(minutes: 3),
  ),
);

Song localSong() => const Song(
  id: 0,
  title: 'Local',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 2),
  audioPath: '',
  gradientId: 0,
);

Future<void> flush() => Future<void>.delayed(Duration.zero);
Uri streamUri(String id) =>
    Uri.https('audio.example', '/$id', {'token': 'secret'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestAudioPlayer player;
  late AudioService service;
  late Future<Uri> Function(String) resolve;
  const favoritesKey = 'harmoniq_favorites_v1';
  const scanChannel = MethodChannel('com.example.harmoniq/local_music');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    player = TestAudioPlayer();
    resolve = (id) async => streamUri(id);
    service = AudioService(
      audioPlayer: player,
      resolveYoutubeAudio: (id) => resolve(id),
    );
    await flush();
  });

  tearDown(() async {
    service.dispose();
    await flush();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scanChannel, null);
  });

  test('identity is source-aware and YouTube URLs never enter Song JSON', () {
    final a = youtubeSong();
    final b = youtubeSong('lmnopqrstuv');
    final local = localSong();
    final legacy = local.copyWith(source: SongSource.legacy);
    expect(a.id, 0);
    expect(a.videoId, 'abcdefghijk');
    expect(a.identity, 'youtube:abcdefghijk');
    expect(local.identity, 'local:0');
    expect(legacy.identity, 'legacy:0');
    expect({a, b, local, legacy}, hasLength(4));
    expect(a, a.copyWith(id: 123, title: 'Changed'));
    expect(a.hashCode, a.copyWith(id: 123).hashCode);
    expect(a.gradientId, youtubeSong().gradientId);
    final restored = Song.fromJson({
      ...a.toJson(),
      'audioPath': streamUri(a.videoId!).toString(),
    });
    expect(restored.audioPath, isEmpty);
    expect(restored.toJson()['audioPath'], isEmpty);
    expect(
      a.copyWith(audioPath: streamUri(a.videoId!).toString()).audioPath,
      '',
    );
    expect(Song.fromJson(a.toJson()), a);
    expect(Song.fromJson({...local.toJson()}..remove('source')), local);
    expect(Song.fromJson({...local.toJson(), 'source': 'jamendo'}), legacy);
  });

  test('resolver rejects invalid IDs offline and web is unsupported', () async {
    await expectLater(
      native.resolveYoutubeAudio('invalid'),
      throwsFormatException,
    );
    await expectLater(
      web.resolveYoutubeAudio('abcdefghijk'),
      throwsUnsupportedError,
    );
  });

  test(
    'catalog favorites playlists and scan preserve colliding sources',
    () async {
      final a = youtubeSong();
      final b = youtubeSong('lmnopqrstuv');
      final local = localSong();
      final legacy = local.copyWith(source: SongSource.legacy);
      service.registerSongs([a, b, local, legacy]);
      service.registerSongs([a.copyWith(title: 'Updated')]);
      expect(service.songs, hasLength(4));
      expect(service.songs.first.title, 'Updated');
      for (final song in [a, b, local, legacy]) {
        service.toggleFavorite(song);
        service.addSongToPlaylist(song, service.playlists[1]);
      }
      expect(service.favorites, hasLength(4));
      expect(service.playlists[1].songs, hasLength(4));
      service.toggleFavorite(b);
      service.removeSongFromPlaylist(b, service.playlists[1]);
      expect(service.isSongFavorite(a), isTrue);
      expect(service.isSongFavorite(b), isFalse);
      expect(service.playlists[1].songs, [a, local, legacy]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(scanChannel, (call) async {
            if (call.method == 'fetchLocalSongs') {
              return [
                {'id': 0, 'title': 'Scanned', 'path': ''},
              ];
            }
            return true;
          });
      await service.scanLocalSongs();
      expect(service.songs, hasLength(4));
      expect(service.localSongs.single.isFavorite, isTrue);
      await flush();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(favoritesKey)!;
      expect(saved.join(), isNot(contains('token')));
      expect(saved.map((s) => Song.fromJson(jsonDecode(s))).toSet(), {
        a,
        local,
        legacy,
      });
      service.dispose();
      await flush();
      player = TestAudioPlayer();
      service = AudioService(
        audioPlayer: player,
        resolveYoutubeAudio: (id) => resolve(id),
      );
      await flush();
      expect(service.favorites.toSet(), {a, local, legacy});
    },
  );

  test(
    'metadata loads immediately and play does not await track completion',
    () async {
      final gate = Completer<Uri>();
      resolve = (_) => gate.future;
      final song = youtubeSong();
      final selected = service.playSong(song);
      expect(service.currentSong, song);
      expect(service.isLoading, isTrue);
      expect(service.wantsToPlay, isTrue);
      expect(service.isPlaying, isFalse);
      expect(service.canSeek, isFalse);
      gate.complete(streamUri(song.videoId!));
      await selected.timeout(const Duration(seconds: 1));
      expect(player.plays.single.isCompleted, isFalse);
      expect(service.isLoading, isFalse);
      expect(service.isPlaying, isTrue);
      expect(service.canSeek, isTrue);
      final source = player.sources.single;
      final media = source.tag as MediaItem;
      expect(source.uri, streamUri(song.videoId!));
      expect(media.id, song.identity);
      expect(media.title, song.title);
      expect(media.artUri.toString(), song.albumArtUrl);
      expect(service.currentSong!.audioPath, isEmpty);
      await service.seek(const Duration(seconds: 45));
      expect(player.seeks, [const Duration(seconds: 45)]);
    },
  );

  test('slow resolver A cannot block or replace newer B', () async {
    final a = youtubeSong();
    final b = youtubeSong('lmnopqrstuv');
    final gate = Completer<Uri>();
    resolve = (id) =>
        id == a.videoId ? gate.future : Future.value(streamUri(id));
    final first = service.playSong(a);
    await service.playSong(b).timeout(const Duration(seconds: 1));
    gate.complete(streamUri(a.videoId!));
    await first;
    expect(service.currentSong, b);
    expect(player.sources.map((s) => (s.tag as MediaItem).id), [b.identity]);
    expect(player.plays, hasLength(1));
  });

  test('stale resolver failure cannot fail newer B', () async {
    final gate = Completer<Uri>();
    resolve = (id) =>
        id == 'abcdefghijk' ? gate.future : Future.value(streamUri(id));
    final first = service.playSong(youtubeSong());
    await service.playSong(youtubeSong('lmnopqrstuv'));
    gate.completeError(StateError('signed URL secret'));
    await first;
    expect(service.playbackError, isNull);
    expect(service.isPlaying, isTrue);
  });

  test(
    'pause while resolving persists and resume needs no new resolution',
    () async {
      final gate = Completer<Uri>();
      var calls = 0;
      resolve = (_) {
        calls++;
        return gate.future;
      };
      final selected = service.playSong(youtubeSong());
      await service.togglePlay();
      expect(service.wantsToPlay, isFalse);
      expect(service.isLoading, isTrue);
      gate.complete(streamUri('abcdefghijk'));
      await selected;
      expect(player.plays, isEmpty);
      expect(service.isPlaying, isFalse);
      expect(service.canSeek, isTrue);
      await service.togglePlay();
      expect(calls, 1);
      expect(service.isPlaying, isTrue);
    },
  );

  test(
    'pause during set source and duration updates preserve latest favorite',
    () async {
      player.loadGate = Completer<Duration?>();
      final song = youtubeSong();
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

  test('stop clears immediately and invalidates unresolved work', () async {
    final gate = Completer<Uri>();
    resolve = (_) => gate.future;
    final selected = service.playSong(youtubeSong());
    final stopped = service.stopAndClear();
    expect(service.currentSong, isNull);
    expect(service.isLoading, isFalse);
    expect(service.wantsToPlay, isFalse);
    await stopped;
    gate.complete(streamUri('abcdefghijk'));
    await selected;
    expect(player.sources, isEmpty);
    expect(service.queue, hasLength(1));
  });

  test(
    'dispose invalidates resolver and cannot resurrect player or notify',
    () async {
      final gate = Completer<Uri>();
      resolve = (_) => gate.future;
      final selected = service.playSong(youtubeSong());
      var notifications = 0;
      service.addListener(() => notifications++);
      service.dispose();
      gate.complete(streamUri('abcdefghijk'));
      await selected;
      await flush();
      expect(player.disposed, isTrue);
      expect(player.sources, isEmpty);
      expect(notifications, 0);
    },
  );

  test(
    'source installs serialize and discard old progress and completion',
    () async {
      final a = youtubeSong();
      final b = youtubeSong('lmnopqrstuv');
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

  test('stop while source installs suppresses its eventual play', () async {
    player.loadGate = Completer<Duration?>();
    final selected = service.playSong(youtubeSong());
    await flush();
    final stopped = service.stopAndClear();
    expect(service.currentSong, isNull);
    player.loadGate!.complete(const Duration(minutes: 4));
    await Future.wait([selected, stopped]);
    expect(player.plays, isEmpty);
    expect(service.currentSong, isNull);
  });

  test(
    'failure is sanitized and retry resolves a fresh URL without fake play',
    () async {
      var calls = 0;
      resolve = (id) async {
        if (++calls == 1) {
          throw StateError('https://secret.example?token=secret');
        }
        return streamUri(id);
      };
      await service.playSong(youtubeSong());
      expect(service.playbackError, isNotNull);
      expect(service.playbackError, isNot(contains('secret')));
      expect(service.isPlaying, isFalse);
      expect(service.wantsToPlay, isFalse);
      expect(service.canSeek, isFalse);
      expect(service.isLoading, isFalse);
      expect(player.plays, isEmpty);
      await service.retryPlayback();
      expect(calls, 2);
      expect(service.playbackError, isNull);
      expect(service.isPlaying, isTrue);
    },
  );

  test('non-HTTPS resolver result and player failure are sanitized', () async {
    resolve = (_) async => Uri.parse('http://audio.example/?token=secret');
    await service.playSong(youtubeSong());
    expect(player.sources, isEmpty);
    expect(service.playbackError, isNotNull);
    resolve = (id) async => streamUri(id);
    player.failLoad = PlayerException(
      0,
      'Source error https://secret.example/signed?token=secret403token',
    );
    await service.retryPlayback();
    expect(service.playbackError, isNot(contains('secret')));
    expect(service.isPlaying, isFalse);
    expect(player.plays, isEmpty);
    player.failLoad = null;
    await service.retryPlayback();
    expect(service.isPlaying, isTrue);
  });

  test('Exo 403 load failure is shown without automatic retries', () async {
    var calls = 0;
    resolve = (id) async {
      calls++;
      return streamUri(id);
    };
    player.failLoad = PlayerException(0, 'Source error', {
      'originalError': {
        'cause': {
          'responseCode': 403,
          'message': 'Response code: 403',
          'url': 'https://secret.example/?token=secret403token',
        },
      },
    });
    final song = youtubeSong('SMs0GnYze34');
    await service.playSong(song, contextQueue: [song, youtubeSong()]);
    await flush();
    expect(
      service.playbackError,
      'YouTube refused this audio stream (403). Retrying may not help. '
      'Choose another track.',
    );
    expect(service.currentSong, song);
    expect(service.isPlaying, isFalse);
    expect(service.wantsToPlay, isFalse);
    expect(service.isLoading, isFalse);
    expect(service.canSeek, isFalse);
    expect(calls, 1);
    expect(player.sources, hasLength(1));
    expect(player.plays, isEmpty);
  });

  test('source error without HTTP evidence stays generic', () async {
    // Cached just_audio sends only type/message/index, not the logged cause.
    player.failLoad = PlayerException(0, 'Source error', {'index': 0});
    await service.playSong(youtubeSong());
    expect(
      service.playbackError,
      'YouTube audio is unavailable. Please try again.',
    );
  });

  test('timeout from resolver is shown with retry guidance', () async {
    var calls = 0;
    resolve = (_) async {
      calls++;
      throw TimeoutException('https://secret.example/?token=secret403token');
    };
    await service.playSong(youtubeSong());
    await flush();
    expect(service.playbackError, 'YouTube audio timed out. Please try again.');
    expect(calls, 1);
    expect(player.sources, isEmpty);
    expect(service.isLoading, isFalse);
    expect(service.wantsToPlay, isFalse);
  });

  test('local source failures never claim YouTube', () async {
    final local = localSong().copyWith(audioPath: 'file:///music/track.mp3');
    player.failLoad = PlayerException(0, 'Source error: Response code: 403');
    await service.playSong(local);
    expect(
      service.playbackError,
      'Unable to access this audio (403). Choose another track.',
    );
    player.failLoad = TimeoutException('secret local path');
    await service.retryPlayback();
    expect(
      service.playbackError,
      'Audio playback timed out. Please try again.',
    );
    player.failLoad = PlayerException(0, 'Source error');
    await service.retryPlayback();
    expect(
      service.playbackError,
      'Unable to play this audio. Please try again.',
    );
  });

  test('stale source and stream errors cannot fail newer selection', () async {
    final a = youtubeSong();
    final b = youtubeSong('lmnopqrstuv');
    final gate = Completer<Duration?>();
    player.loadGate = gate;
    final first = service.playSong(a);
    await flush();
    final second = service.playSong(b);
    player.events.addError(
      PlayerException(0, 'Source error: Response code: 403'),
    );
    expect(service.currentSong, b);
    expect(service.playbackError, isNull);
    player.loadGate = null;
    gate.completeError(PlayerException(0, 'Source error: Response code: 403'));
    await Future.wait([first, second]);
    await flush();
    expect(service.currentSong, b);
    expect(service.playbackError, isNull);
    expect(service.isPlaying, isTrue);
    expect(player.sources, hasLength(2));
    expect(player.plays, hasLength(1));
  });

  test('playback event errors preserve HTTP evidence without retry', () async {
    var calls = 0;
    resolve = (id) async {
      calls++;
      return streamUri(id);
    };
    await service.playSong(youtubeSong());
    player.events.addError(
      PlatformException(
        code: '0',
        message:
            'Source error: Response code: 403 '
            'https://secret.example/?token=secret',
      ),
    );
    await flush();
    expect(
      service.playbackError,
      'YouTube refused this audio stream (403). Retrying may not help. '
      'Choose another track.',
    );
    expect(service.isPlaying, isFalse);
    expect(service.isLoading, isFalse);
    expect(service.wantsToPlay, isFalse);
    expect(service.canSeek, isFalse);
    expect(calls, 1);
    expect(player.sources, hasLength(1));
    expect(player.plays, hasLength(1));
  });

  test(
    'late play errors from old generation do not fail new playback',
    () async {
      await service.playSong(youtubeSong());
      final oldPlay = player.plays.single;
      await service.playSong(youtubeSong('lmnopqrstuv'));
      oldPlay.completeError(
        PlayerException(0, 'Source error: Response code: 403'),
      );
      await flush();
      expect(service.playbackError, isNull);
      expect(service.isPlaying, isTrue);
      player.plays.last.completeError(
        PlayerException(0, 'Source error: Response code: 403'),
      );
      await flush();
      expect(
        service.playbackError,
        'YouTube refused this audio stream (403). Retrying may not help. '
        'Choose another track.',
      );
      expect(service.isPlaying, isFalse);
    },
  );

  test(
    'native controls synchronize intent and buffering does not latch loading',
    () async {
      await service.playSong(youtubeSong());
      player.emit(false, ProcessingState.ready);
      expect(service.wantsToPlay, isFalse);
      expect(service.isPlaying, isFalse);
      player.emit(true, ProcessingState.ready);
      expect(service.wantsToPlay, isTrue);
      expect(service.isPlaying, isTrue);
      player.emit(true, ProcessingState.buffering);
      expect(service.isLoading, isTrue);
      expect(service.canSeek, isFalse);
      await service.togglePlay();
      expect(player.pauseCalls, 1);
      expect(service.wantsToPlay, isFalse);
      player.emit(false, ProcessingState.ready);
      expect(service.isLoading, isFalse);
      expect(service.canSeek, isTrue);
      player.events.addError(StateError('https://secret.example?token=secret'));
      expect(service.playbackError, isNotNull);
      expect(service.playbackError, isNot(contains('secret')));
    },
  );

  test(
    'queue navigation uses YouTube identity and rejects legacy and HTTP local',
    () async {
      final a = youtubeSong();
      final b = youtubeSong('lmnopqrstuv');
      final local = localSong();
      final legacy = local.copyWith(source: SongSource.legacy);
      final remote = local.copyWith(audioPath: 'https://example.com/audio.mp3');
      await service.playSong(a, contextQueue: [a, b, local, legacy, remote]);
      expect(service.queue, [a, b, local]);
      await service.next();
      expect(service.currentSong, b);
      await service.previous();
      expect(service.currentSong, a);
      await service.skipToIndex(2);
      expect(service.currentSong, local);
      expect(service.isPlaying, isFalse);
      await service.togglePlay();
      expect(service.isPlaying, isTrue);
      await service.seek(const Duration(seconds: 10));
      expect(service.playbackPosition, const Duration(seconds: 10));
      await service.playSong(legacy);
      await service.playSong(remote);
      await service.playSong(youtubeSong('invalid'));
      expect(service.currentSong, local);
      expect(service.queue, [a, b, local]);
    },
  );
}
