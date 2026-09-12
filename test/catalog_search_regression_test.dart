import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/models/youtube_video.dart';
import 'package:harmoniq/screens/library_screen.dart';
import 'package:harmoniq/screens/search_screen.dart';
import 'package:harmoniq/services/audio_service.dart';
import 'package:harmoniq/widgets/song_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song track(int id, {String? title, String album = 'Album'}) => Song(
  id: id,
  title: title ?? 'Track $id',
  artist: 'Artist',
  album: album,
  duration: const Duration(minutes: 3),
  audioPath: '',
  gradientId: id,
);

YoutubeVideo video(String id, String title) =>
    YoutubeVideo(id: id, title: title, artist: 'Channel', thumbnailUrl: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.harmoniq/local_music');
  late AudioService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = AudioService();
    // Let persisted favorites initialize before making assertions.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void scanReturns(FutureOr<List<Map<String, Object>>> Function() fetch) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'fetchLocalSongs') return await fetch();
          return true;
        });
  }

  test('saved source tags migrate to legacy without changing metadata', () {
    final original = track(7)
        .copyWith(
          audioPath: 'https://previous.example/track.mp3',
          isFavorite: true,
          licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
          audioDownloadAllowed: true,
        )
        .toJson();
    for (final source in ['jamendo', 'legacy']) {
      final restored = Song.fromJson({...original, 'source': source});
      expect(restored.source, SongSource.legacy);
      expect(restored.isOnline, isTrue);
      expect(restored.toJson(), {...original, 'source': 'legacy'});
      expect(Song.fromJson(restored.toJson()).toJson(), restored.toJson());
    }
    expect(Song.fromJson(original).source, SongSource.local);
    expect(
      Song.fromJson({...original}..remove('source')).source,
      SongSource.local,
    );
    expect(
      Song.fromJson({...original, 'source': 'unknown-online'}).source,
      SongSource.legacy,
    );
  });

  test(
    'legacy favorites survive load, local ID collision, save, and reload',
    () async {
      const key = 'harmoniq_favorites_v1';
      final saved = track(7, title: 'Saved old favorite').copyWith(
        source: SongSource.legacy,
        audioPath: 'https://previous.example/track.mp3',
        isFavorite: true,
      );
      final oldJson = {...saved.toJson(), 'source': 'jamendo'};
      service.dispose();
      SharedPreferences.setMockInitialValues({
        key: [jsonEncode(oldJson)],
      });
      service = AudioService();
      await Future<void>.delayed(Duration.zero);
      expect(service.favorites.single.toJson(), saved.toJson());
      expect(service.playlists.first.songs.single.source, SongSource.legacy);
      final prefs = await SharedPreferences.getInstance();
      // Merely loading does not rewrite or discard the existing storage.
      expect(prefs.getStringList(key), [jsonEncode(oldJson)]);

      scanReturns(
        () => [
          {'id': 7, 'title': 'Local collision', 'path': ''},
        ],
      );
      await service.scanLocalSongs();
      final local = service.localSongs.single;
      expect(local.source, SongSource.local);
      expect(local.isFavorite, isFalse);
      expect(service.isSongFavorite(local), isFalse);
      service.toggleFavorite(local);
      expect(service.favorites, hasLength(2));
      service.toggleFavorite(local);
      await Future<void>.delayed(Duration.zero);
      expect(service.favorites.single.toJson(), saved.toJson());
      expect(jsonDecode(prefs.getStringList(key)!.single), saved.toJson());

      service.dispose();
      service = AudioService();
      await Future<void>.delayed(Duration.zero);
      expect(service.favorites.single.toJson(), saved.toJson());
      expect(service.playlists.first.songs.single.toJson(), saved.toJson());
      expect(service.currentSong, isNull);
    },
  );

  test('legacy tracks and remote URLs tagged local are rejected without state changes', () async {
    final local = track(1);
    final rejected = [
      track(2).copyWith(source: SongSource.legacy),
      track(3).copyWith(
        source: SongSource.legacy,
        audioPath: 'https://previous.example/track.mp3',
      ),
      track(4).copyWith(
        source: SongSource.legacy,
        audioPath: '/storage/music/legacy.mp3',
      ),
      track(5)
          .copyWith(audioPath: 'https://www.youtube.com/watch?v=abcdefghijk'),
      track(6).copyWith(audioPath: 'HTTP://previous.example/track.mp3'),
    ];
    for (final song in rejected) {
      await service.playSong(song, contextQueue: [local, song]);
    }
    expect(service.currentSong, isNull);
    expect(service.songs, isEmpty);
    expect(service.queue, isEmpty);
    await service.playSong(local);
    await service.seek(const Duration(seconds: 12));
    final revision = service.catalogRevision;
    var notifications = 0;
    service.addListener(() => notifications++);
    for (final song in rejected) {
      await service.playSong(song, contextQueue: [song]);
    }
    expect(service.currentSong, local);
    expect(service.queue, [local]);
    expect(service.currentQueueIndex, 0);
    expect(service.playbackPosition, const Duration(seconds: 12));
    expect(service.catalogRevision, revision);
    expect(notifications, 0);
  });

  test(
    'queue filters unavailable entries and skip navigation stays local',
    () async {
      final first = track(1);
      final last = track(2);
      final legacy = track(1).copyWith(source: SongSource.legacy);
      final remote = track(3)
          .copyWith(audioPath: 'https://youtu.be/abcdefghijk');
      await service.playSong(
        first,
        contextQueue: [legacy, first, remote, last],
      );
      expect(service.queue, [first, last]);
      expect(
        service.queue.every((song) => song.source == SongSource.local),
        isTrue,
      );
      expect(() => service.queue.add(legacy), throwsUnsupportedError);
      await service.skipToIndex(2);
      await service.skipToIndex(-1);
      expect(service.currentSong, first);
      await service.skipToIndex(1);
      expect(service.currentSong, last);
      await service.next();
      expect(service.currentSong, first);
      await service.previous();
      expect(service.currentSong, last);
      service.toggleShuffle();
      await service.next();
      await service.previous();
      expect(service.currentSong!.source, SongSource.local);
      await service.playSong(track(4));
      expect(service.queue.map((song) => song.id), [1, 2, 4]);
    },
  );

  testWidgets('legacy favorites stay visible and taps explain unavailability', (
    tester,
  ) async {
    final legacy = track(
      7,
      title: 'Previous favorite',
    ).copyWith(source: SongSource.legacy);
    service.toggleFavorite(legacy);
    var playRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          audioService: service,
          onSongTap: (_) => playRequests++,
          onFavoriteTap: service.toggleFavorite,
          onCreatePlaylist: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Favorites'));
    await tester.pump();
    expect(find.text('Previous source (1)'), findsOneWidget);
    expect(find.text('Previous favorite'), findsOneWidget);
    expect(find.textContaining('saved but unavailable'), findsOneWidget);
    await tester.tap(find.text('Previous source (1)'));
    await tester.pump();
    await tester.tap(find.text('Previous favorite'));
    await tester.pump();
    expect(playRequests, 0);
    expect(
      find.textContaining('Search for "Previous favorite"'),
      findsOneWidget,
    );
    expect(service.favorites.single.source, SongSource.legacy);
    await tester.tap(find.byTooltip('Remove favorite'));
    await tester.pump();
    expect(find.text('Previous source (1)'), findsNothing);
    expect(find.text('No favorites yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'bulk registration preserves order, replaces metadata, and notifies once',
    () {
      final songs = List.generate(10000, track);
      var notifications = 0;
      service.addListener(() => notifications++);
      service.registerSongs(songs);
      final revision = service.catalogRevision;
      service.registerSongs([
        track(500, title: 'Replacement'),
        track(10000),
        track(10000, title: 'Last wins'),
      ]);
      expect(service.songs, hasLength(10001));
      expect(service.songs[500].title, 'Replacement');
      expect(service.songs.last.title, 'Last wins');
      expect(service.songs.first.id, 0);
      expect(service.catalogRevision, greaterThan(revision));
      expect(notifications, 2);
      service.toggleFavorite(songs.first);
      service.registerSongs([songs.first]);
      expect(service.songs.first.isFavorite, isTrue);
    },
  );

  test('overlapping scans share a future and successful refresh removes deleted files', () async {
    final pending = Completer<List<Map<String, Object>>>();
    var fetches = 0;
    scanReturns(() {
      fetches++;
      return pending.future;
    });
    final first = service.scanLocalSongs();
    final second = service.scanLocalSongs();
    expect(identical(first, second), isTrue);
    pending.complete([
      {'id': 1, 'title': 'Local one', 'path': ''},
    ]);
    await first;
    expect(fetches, 1);
    expect(service.localSongs.single.title, 'Local one');
    scanReturns(() => throw PlatformException(code: 'SCAN_FAILED'));
    await service.scanLocalSongs();
    expect(service.localSongs, hasLength(1));
    scanReturns(() => []);
    await service.scanLocalSongs();
    expect(service.localSongs, isEmpty);
    expect(service.songs, isEmpty);
  });

  testWidgets('album cache updates after same-ID metadata replacement', (
    tester,
  ) async {
    service.registerSongs([track(1, album: 'Old album')]);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          audioService: service,
          onSongTap: (_) {},
          onFavoriteTap: (_) {},
          onCreatePlaylist: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Albums'));
    await tester.pump();
    expect(find.text('Old album'), findsOneWidget);
    service.registerSongs([track(1, album: 'New album')]);
    await tester.pump();
    expect(find.text('Old album'), findsNothing);
    expect(find.text('New album'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> showSearch(
    WidgetTester tester,
    Future<List<YoutubeVideo>> Function(String) search,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          audioService: service,
          onSongTap: (_) {},
          onFavoriteTap: service.toggleFavorite,
          searchVideos: search,
        ),
      ),
    );
  }

  testWidgets(
    'stale online success cannot replace results or register old songs',
    (tester) async {
      final old = Completer<List<YoutubeVideo>>();
      final current = Completer<List<YoutubeVideo>>();
      await showSearch(
        tester,
        (query) => query == 'old' ? old.future : current.future,
      );
      await tester.enterText(find.byType(TextField), 'old');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'new');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      current.complete([video('current0001', 'Current result')]);
      await tester.pump();
      old.complete([video('oldvideo001', 'Stale result')]);
      await tester.pump();
      expect(find.text('Current result'), findsOneWidget);
      expect(find.text('Stale result'), findsNothing);
      expect(service.songs, isEmpty);
      expect(service.queue, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'clearing query invalidates pending failures and retry starts loading',
    (tester) async {
      final pending = Completer<List<YoutubeVideo>>();
      var requests = 0;
      await showSearch(tester, (_) {
        requests++;
        return requests == 1
            ? Future.error(Exception('offline'))
            : pending.future;
      });
      await tester.enterText(find.byType(TextField), 'query');
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests, 0);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump();
      expect(find.text('Retry YouTube search'), findsOneWidget);
      await tester.tap(find.text('Retry YouTube search'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      pending.completeError(Exception('late failure'));
      await tester.pump();
      expect(find.text('Start somewhere good.'), findsOneWidget);
      expect(find.text('Retry YouTube search'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('local matches build lazily and refresh when a scan completes', (
    tester,
  ) async {
    scanReturns(
      () => List.generate(
        2000,
        (id) => <String, Object>{
          'id': id,
          'title': 'Local track $id',
          'path': '',
        },
      ),
    );
    await showSearch(tester, (_) async => []);
    await tester.enterText(find.byType(TextField), 'Local');
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Local'));
    await tester.pump();
    expect(find.text('No local results found'), findsOneWidget);
    await tester.runAsync(() => service.scanLocalSongs());
    await tester.pump();
    expect(find.text('Local track 0'), findsOneWidget);
    expect(find.byType(SongTile).evaluate().length, lessThan(30));
    expect(find.text('Local track 1999'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Local');
    await tester.pump();
    expect(find.text('Local track 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
