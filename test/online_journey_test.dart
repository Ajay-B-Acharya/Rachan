import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/main.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/screens/home_screen.dart';
import 'package:harmoniq/screens/now_playing_screen.dart';
import 'package:harmoniq/screens/search_screen.dart';
import 'package:harmoniq/services/audio_service.dart';
import 'package:harmoniq/theme/app_theme.dart';
import 'package:harmoniq/widgets/mini_player.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_service_test.dart' show TestAudioPlayer, localSong, onlineSong;

class _LocalCatalogService extends AudioService {
  _LocalCatalogService() : super(audioPlayer: TestAudioPlayer());

  @override
  List<Song> get localSongs => [localSong().copyWith(title: 'Local house')];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(Widget child) => MaterialApp(
    theme: AppTheme.darkTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: child,
  );

  testWidgets(
    'online search is explicit and result taps carry the result queue',
    (tester) async {
      final service = _LocalCatalogService();
      addTearDown(service.dispose);
      final results = [onlineSong(), onlineSong('def456')];
      final queries = <String>[];
      Song? selected;
      List<Song>? queue;
      await tester.pumpWidget(
        app(
          SearchScreen(
            audioService: service,
            onSongTap: (_) => fail('The queue callback must take precedence'),
            onFavoriteTap: service.toggleFavorite,
            onQueueTap: (song, songs) {
              selected = song;
              queue = songs;
            },
            searchOnline: (query) async {
              queries.add(query);
              return results;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'house');
      await tester.pump();
      expect(queries, isEmpty);
      expect(find.text('Local house'), findsOneWidget);
      await tester.tap(find.text('Search online'));
      await tester.pumpAndSettle();
      expect(queries, ['house']);
      expect(find.text('Online results · Audius'), findsOneWidget);
      expect(service.songs, results);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Online'));
      await tester.pump();
      expect(find.text('Local house'), findsNothing);
      await tester.tap(find.text(results.first.title));
      expect(selected, results.first);
      expect(queue, results);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pump();
      expect(find.text('Local house'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text(results.first.title), findsNothing);
      expect(find.text('A new favorite awaits.'), findsOneWidget);
      expect(queries, ['house']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keyboard search retries safely and ignores stale query responses',
    (tester) async {
      final service = _LocalCatalogService();
      addTearDown(service.dispose);
      final requests = <(String, Completer<List<Song>>)>[];
      await tester.pumpWidget(
        app(
          SearchScreen(
            audioService: service,
            onSongTap: (_) {},
            onFavoriteTap: (_) {},
            searchOnline: (query) {
              final request = Completer<List<Song>>();
              requests.add((query, request));
              return request.future;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'old');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(requests.single.$1, 'old');
      await tester.enterText(find.byType(TextField), 'new');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      requests[1].$2.completeError(StateError('private backend details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not search online music. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend'), findsNothing);
      await tester.tap(find.text('Retry online search'));
      await tester.pump();
      expect(requests.map((request) => request.$1), ['old', 'new', 'new']);
      final fresh = onlineSong('new123');
      requests[2].$2.complete([fresh]);
      await tester.pumpAndSettle();
      requests[0].$2.complete([onlineSong('old123')]);
      await tester.pumpAndSettle();
      expect(find.text(fresh.title), findsOneWidget);
      expect(find.text(onlineSong('old123').title), findsNothing);
      expect(service.songs, [fresh]);
      expect(find.text('Retry online search'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Local filter invalidates pending online work and never submits',
    (tester) async {
      final service = _LocalCatalogService();
      addTearDown(service.dispose);
      final pending = Completer<List<Song>>();
      var requests = 0;
      await tester.pumpWidget(
        app(
          SearchScreen(
            audioService: service,
            onSongTap: (_) {},
            onFavoriteTap: (_) {},
            searchOnline: (_) {
              requests++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'house');
      await tester.pump();
      await tester.tap(find.text('Search online'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Local'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      pending.complete([onlineSong()]);
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(service.songs, isEmpty);
      expect(find.text('Local house'), findsOneWidget);
      expect(find.text('Search online'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pump();
      expect(find.text(onlineSong().title), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'discovery retries and plays the full trending queue with offline access',
    (tester) async {
      final service = _LocalCatalogService();
      addTearDown(service.dispose);
      final results = [onlineSong(), onlineSong('def456')];
      var loads = 0;
      var localTaps = 0;
      Song? selected;
      List<Song>? queue;
      final searches = <String>[];
      await tester.pumpWidget(
        app(
          HomeScreen(
            audioService: service,
            onSongTap: (song, [songs]) {
              selected = song;
              queue = songs;
            },
            onPlaylistPlayTap: (_) {},
            onLocalTap: () => localTaps++,
            onSearchTap: searches.add,
            loadOnlineTracks: () async {
              if (++loads == 1) throw StateError('private discovery error');
              return results;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Discover music'), findsOneWidget);
      await tester.tap(find.text('Discover music'));
      expect(searches, ['']);
      await tester.scrollUntilVisible(find.text('Retry discovery'), 200);
      await tester.tap(find.text('Retry discovery'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(service.songs, results);
      final verticalScroll = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.text('Play trending'),
        -200,
        scrollable: verticalScroll,
      );
      await tester.tap(find.text('Play trending'));
      expect(selected, results.first);
      expect(queue, results);
      await tester.scrollUntilVisible(
        find.text('Your offline collection'),
        250,
        scrollable: verticalScroll,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Your offline collection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your offline collection'));
      expect(localTaps, 1);
      expect(find.textContaining('private discovery'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'MainContainer opens native online playback and retains pause in mini player',
    (tester) async {
      final player = TestAudioPlayer();
      final resolved = <String>[];
      final service = AudioService(
        audioPlayer: player,
        resolveOnlineAudio: (id) async {
          resolved.add(id);
          return Uri.https('api.audius.co', '/v1/tracks/$id/stream');
        },
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(app(MainContainer(audioService: service)));
      // Default Home discovery is HTTP-blocked by Flutter; drain its timeout.
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      final songs = [onlineSong(), onlineSong('def456')];
      await tester.runAsync(() async {
        tester
            .widget<HomeScreen>(find.byType(HomeScreen))
            .onSongTap(songs.first, songs);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.byType(NowPlayingScreen), findsOneWidget);
      expect(service.queue, songs);
      expect(service.currentSong, songs.first);
      expect(resolved, ['abc123']);
      expect(service.playbackError, isNull);
      expect(service.isLoading, isFalse);
      expect(player.sources, hasLength(1));
      expect(player.sources.single.uri.scheme, 'https');
      expect((player.sources.single.tag as MediaItem).id, songs.first.identity);
      expect(service.isPlaying, isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Pause'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(service.isPlaying, isFalse);
      expect(player.pauseCalls, 1);
      await tester.tap(find.byTooltip('Minimize player'));
      await tester.pumpAndSettle();
      final mini = tester.widget<MiniPlayer>(find.byType(MiniPlayer));
      expect(mini.song, songs.first);
      expect(mini.isPlaying, isFalse);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Play'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(service.isPlaying, isTrue);
      expect(resolved, ['abc123']);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Next track'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(service.currentSong, songs.last);
      expect(resolved, ['abc123', 'def456']);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Close song'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(service.currentSong, isNull);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(
        player.disposed,
        isFalse,
        reason: 'MainContainer does not own injected services',
      );
    },
  );
}
