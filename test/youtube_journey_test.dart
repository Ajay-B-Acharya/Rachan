import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/models/youtube_video.dart';
import 'package:harmoniq/screens/home_screen.dart';
import 'package:harmoniq/screens/search_screen.dart';
import 'package:harmoniq/services/audio_service.dart';
import 'package:harmoniq/theme/app_theme.dart';
import 'package:harmoniq/widgets/song_tile.dart';
import 'package:harmoniq/widgets/youtube_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _nextVideo = YoutubeVideo(
  id: 'M7lc1UVf-VE',
  title: 'Second injected track',
  artist: 'Another test channel',
  thumbnailUrl: '',
);

const _video = YoutubeVideo(
  id: 'dQw4w9WgXcQ',
  title: 'Injected music video',
  artist: 'Test channel',
  // Never fetch a thumbnail or mount a network-backed player in these tests.
  thumbnailUrl: '',
);

Widget _app(Widget child, {double textScale = 1.5}) => MaterialApp(
  theme: AppTheme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: true,
    ),
    child: child!,
  ),
  home: child,
);

void _viewport(WidgetTester tester, {Size size = const Size(320, 640)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectNoExternalControls() {
  for (final label in [
    'Open YouTube Music',
    'Continue in YouTube Music',
    'Open in YouTube',
    'Open in YouTube Music',
  ]) {
    expect(find.text(label, skipOffstage: false), findsNothing);
    expect(find.byTooltip(label, skipOffstage: false), findsNothing);
  }
  expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
}

void _expectUnchangedCatalog(
  AudioService service, {
  List<int> localIds = const [],
}) {
  expect(service.songs.map((song) => song.id), localIds);
  expect(service.localSongs.map((song) => song.id), localIds);
  expect(service.favorites, isEmpty);
  expect(service.playlists.every((playlist) => playlist.songs.isEmpty), isTrue);
  expect(service.queue, isEmpty);
  expect(service.currentSong, isNull);
}

void _expectEmptyCatalog(AudioService service) {
  _expectUnchangedCatalog(service);
  expect(find.byType(SongTile), findsNothing);
  expect(find.byType(YoutubeCard), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const localChannel = MethodChannel('com.example.harmoniq/local_music');
  late AudioService service;
  late List<String> searches;
  late List<YoutubeVideo> videoTaps;
  late List<Song> songTaps;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = AudioService();
    searches = [];
    videoTaps = [];
    songTaps = [];
    // Finish persisted-favorite initialization outside the fake widget clock.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localChannel, null);
  });

  SearchScreen searchScreen({
    required bool configured,
    Future<List<YoutubeVideo>> Function(String)? search,
    void Function(YoutubeVideo, List<YoutubeVideo>)? onVideoQueueTap,
  }) => SearchScreen(
    audioService: service,
    youtubeConfigured: configured,
    // Inject availability and results; never reach the native or API catalog.
    searchVideos: (query) async {
      searches.add(query);
      return search == null ? [_video] : await search(query);
    },
    onVideoTap: videoTaps.add,
    onVideoQueueTap: onVideoQueueTap,
    onSongTap: songTaps.add,
    onFavoriteTap: (_) => fail('YouTube journeys must not favorite a Song'),
  );

  testWidgets(
    'in-app discovery at 320px and 1.5 scale submits, selects a video, and clears',
    (tester) async {
      _viewport(tester);
      try {
        // Availability can come from native no-key discovery, not just an API key.
        await tester.pumpWidget(_app(searchScreen(configured: true)));
        await tester.pumpAndSettle();
        expect(find.text('Play here. Stay here.'), findsOneWidget);
        _expectNoExternalControls();
        _expectEmptyCatalog(service);
        expect(tester.takeException(), isNull);

        const query = 'Björk & R&B + live / mix? #1';
        await tester.enterText(find.byType(TextField), '  $query  ');
        await tester.pump(const Duration(seconds: 1));
        expect(searches, isEmpty, reason: 'Typing must not start discovery');
        expect(find.text('Search YouTube'), findsOneWidget);
        _expectNoExternalControls();
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(searches, [query]);
        expect(find.text('Play this song'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(YoutubeCard), findsOneWidget);
        expect(videoTaps, isEmpty);
        _expectNoExternalControls();
        _expectUnchangedCatalog(service);

        await _tapVisible(tester, find.text(_video.title));
        expect(videoTaps, [_video]);
        expect(songTaps, isEmpty);
        _expectUnchangedCatalog(service);

        await _tapVisible(tester, find.byTooltip('Clear search'));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '',
        );
        expect(find.byTooltip('Clear search'), findsNothing);
        expect(find.byType(CustomScrollView), findsNothing);
        expect(find.text('Play here. Stay here.'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Recent searches'),
          150,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Recent searches'), findsOneWidget);
        expect(find.text('No local results found'), findsNothing);
        _expectNoExternalControls();
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(searches, [query]);
        expect(videoTaps, [_video]);
        expect(songTaps, isEmpty);
        _expectEmptyCatalog(service);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  for (final onlineOnly in [false, true]) {
    testWidgets(
      '${onlineOnly ? 'YouTube' : 'All'} results dispatch the selected track and ordered queue instead of fallback',
      (tester) async {
        _viewport(tester);
        final selected = <YoutubeVideo>[];
        final queues = <List<YoutubeVideo>>[];
        try {
          await tester.pumpWidget(
            _app(
              searchScreen(
                configured: true,
                search: (_) async => [_video, _nextVideo],
                onVideoQueueTap: (video, queue) {
                  selected.add(video);
                  queues.add(List.of(queue));
                },
              ),
            ),
          );
          await tester.enterText(find.byType(TextField), 'injected');
          if (onlineOnly) {
            await _tapVisible(
              tester,
              find.widgetWithText(ChoiceChip, 'YouTube'),
            );
          }
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          final firstCard = find.byWidgetPredicate(
            (widget) => widget is YoutubeCard && widget.video == _video,
          );
          expect(firstCard, findsOneWidget);
          expect(
            find.descendant(
              of: firstCard,
              matching: find.text('YOUTUBE · AUDIO'),
            ),
            findsOneWidget,
          );
          expect(tester.getSize(firstCard).height, lessThan(180));
          expect(find.byType(AspectRatio), findsNothing);
          await tester.scrollUntilVisible(
            find.text(_nextVideo.title),
            100,
            scrollable: find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          );
          await _tapVisible(tester, find.text(_nextVideo.title));
          expect(searches, ['injected']);
          expect(selected, [_nextVideo]);
          expect(queues, [
            [_video, _nextVideo],
          ]);
          expect(videoTaps, isEmpty, reason: 'Queue callback takes precedence');
          expect(songTaps, isEmpty);
          _expectUnchangedCatalog(service);
          _expectNoExternalControls();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  for (final withQueue in [false, true]) {
    testWidgets(
      'home recommendations preserve ${withQueue ? 'ordered queue dispatch' : 'single-track callback fallback'}',
      (tester) async {
        _viewport(tester, size: const Size(800, 1200));
        final selected = <YoutubeVideo>[];
        final queues = <List<YoutubeVideo>>[];
        try {
          await tester.pumpWidget(
            _app(
              HomeScreen(
                audioService: service,
                youtubeConfigured: true,
                loadVideos: () async => [_video, _nextVideo],
                onVideoTap: videoTaps.add,
                onVideoQueueTap: withQueue
                    ? (video, queue) {
                        selected.add(video);
                        queues.add(List.of(queue));
                      }
                    : null,
                onSongTap: (song, [queue]) => songTaps.add(song),
                onPlaylistPlayTap: (_) => fail('Must not play a fake playlist'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text(_nextVideo.title),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await _tapVisible(tester, find.text(_nextVideo.title));
          expect(find.text('YOUTUBE · AUDIO'), findsNWidgets(2));
          if (withQueue) {
            expect(selected, [_nextVideo]);
            expect(queues, [
              [_video, _nextVideo],
            ]);
            expect(videoTaps, isEmpty);
          } else {
            expect(videoTaps, [_nextVideo]);
            expect(selected, isEmpty);
            expect(queues, isEmpty);
          }
          expect(songTaps, isEmpty);
          _expectUnchangedCatalog(service);
          _expectNoExternalControls();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  for (final host in ['www.youtube.com', 'music.youtube.com']) {
    testWidgets(
      'no-key $host link at 320px and 1.5 scale dispatches a video without search',
      (tester) async {
        _viewport(tester);
        try {
          await tester.pumpWidget(_app(searchScreen(configured: false)));
          await tester.pumpAndSettle();
          expect(find.text('No external app will be opened.'), findsOneWidget);
          _expectNoExternalControls();
          await tester.enterText(
            find.byType(TextField),
            'unavailable discovery',
          );
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(searches, isEmpty);
          expect(videoTaps, isEmpty);
          expect(find.text('Search YouTube'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          _expectNoExternalControls();
          _expectEmptyCatalog(service);
          // A single editing update models pasting a complete URL.
          await tester.enterText(
            find.byType(TextField),
            ' https://$host/watch?v=${_video.id}&list=ignored&t=42 ',
          );
          await tester.pumpAndSettle();
          expect(searches, isEmpty);
          expect(videoTaps, isEmpty);
          _expectNoExternalControls();
          // Keep the in-app action reachable in the narrow, scaled viewport.
          await tester.scrollUntilVisible(
            find.text('Play this song'),
            150,
            scrollable: find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          );
          expect(find.text('Play this song'), findsOneWidget);

          await _tapVisible(tester, find.text('Play this song'));
          expect(videoTaps, hasLength(1));
          final dispatched = videoTaps.single;
          expect(dispatched.id, _video.id);
          expect(dispatched.title, 'YouTube track');
          expect(dispatched.artist, 'YouTube');
          expect(
            dispatched.thumbnailUrl,
            'https://i.ytimg.com/vi/${_video.id}/hqdefault.jpg',
          );
          expect(dispatched.duration, Duration.zero);
          expect(searches, isEmpty);
          _expectNoExternalControls();
          expect(songTaps, isEmpty);
          _expectEmptyCatalog(service);

          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(videoTaps.map((video) => video.id), [_video.id, _video.id]);
          _expectNoExternalControls();
          await _tapVisible(tester, find.byTooltip('Clear search'));
          expect(find.text('Play this song'), findsNothing);
          expect(find.text('Play here. Stay here.'), findsOneWidget);
          expect(find.byTooltip('Clear search'), findsNothing);
          expect(find.text('Recent searches'), findsNothing);
          _expectNoExternalControls();
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(videoTaps, hasLength(2));
          expect(searches, isEmpty);
          _expectEmptyCatalog(service);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  testWidgets(
    'unavailable discovery home skips loading and refresh and opens in-app search',
    (tester) async {
      _viewport(tester);
      var loads = 0;
      final searchOpens = <String>[];
      try {
        await tester.pumpWidget(
          _app(
            HomeScreen(
              audioService: service,
              youtubeConfigured: false,
              loadVideos: () async {
                loads++;
                return [_video];
              },
              onSearchTap: searchOpens.add,
              onVideoTap: videoTaps.add,
              onSongTap: (song, [queue]) => songTaps.add(song),
              onPlaylistPlayTap: (_) => fail('Must not play a fake playlist'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(loads, 0);
        expect(find.text('In the spotlight'), findsNothing);
        expect(find.byTooltip('Refresh tracks'), findsNothing);
        _expectEmptyCatalog(service);

        await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(loads, 0, reason: 'Refresh must honor disabled discovery');
        _expectNoExternalControls();
        await _tapVisible(tester, find.byTooltip('Search music'));
        expect(searchOpens, ['']);
        await _tapVisible(tester, find.text('Find your next song'));
        expect(searchOpens, ['', '']);
        _expectNoExternalControls();
        await tester.scrollUntilVisible(
          find.text('YouTube · in-app'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('YouTube · in-app'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('After hours'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await _tapVisible(tester, find.text('After hours'));
        expect(searchOpens, ['', '', 'Late night R&B']);
        await tester.scrollUntilVisible(
          find.text('Find a song'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await _tapVisible(tester, find.text('Find a song'));
        expect(searchOpens, ['', '', 'Late night R&B', '']);
        _expectNoExternalControls();
        expect(loads, 0);
        expect(videoTaps, isEmpty);
        expect(songTaps, isEmpty);
        _expectEmptyCatalog(service);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'configured All, Local, and YouTube filters keep sources separate',
    (tester) async {
      _viewport(tester, size: const Size(400, 1000));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localChannel, (call) async {
            if (call.method == 'fetchLocalSongs') {
              return [
                {'id': 1, 'title': 'Local music track', 'path': ''},
              ];
            }
            return true;
          });
      await tester.runAsync(service.scanLocalSongs);
      expect(service.localSongs, hasLength(1));
      try {
        await tester.pumpWidget(
          _app(searchScreen(configured: true), textScale: 1),
        );
        await tester.enterText(find.byType(TextField), 'music');
        await tester.pump(const Duration(seconds: 1));
        expect(searches, isEmpty);
        expect(find.text('Local music track'), findsOneWidget);
        await _tapVisible(tester, find.text('Search YouTube'));
        expect(searches, ['music']);
        expect(find.text(_video.title), findsOneWidget);
        expect(find.text('Local music track'), findsOneWidget);

        await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'YouTube'));
        expect(find.text(_video.title), findsOneWidget);
        expect(find.byType(SongTile), findsNothing);
        await _tapVisible(tester, find.text(_video.title));
        expect(videoTaps, [_video]);
        expect(songTaps, isEmpty);

        await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'Local'));
        expect(find.byType(YoutubeCard), findsNothing);
        expect(find.text('Search YouTube'), findsNothing);
        _expectNoExternalControls();
        expect(find.text('Local music track'), findsOneWidget);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(searches, ['music']);
        await _tapVisible(tester, find.text('Local music track'));
        expect(songTaps.single.id, 1);
        expect(videoTaps, [_video]);

        await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'All'));
        expect(find.text(_video.title), findsOneWidget);
        expect(find.text('Local music track'), findsOneWidget);
        _expectUnchangedCatalog(service, localIds: [1]);
        _expectNoExternalControls();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'Local switch ignores in-flight YouTube ${fails ? 'failure' : 'result'} even after switching back',
      (tester) async {
        _viewport(tester, size: const Size(800, 1000));
        final pending = Completer<List<YoutubeVideo>>();
        try {
          await tester.pumpWidget(
            _app(
              searchScreen(configured: true, search: (_) => pending.future),
              textScale: 1,
            ),
          );
          await tester.enterText(find.byType(TextField), 'music');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          expect(searches, ['music']);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          // Do not settle while the deliberately unresolved request is loading.
          await tester.tap(find.widgetWithText(ChoiceChip, 'Local'));
          await tester.pumpAndSettle();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('No local results found'), findsOneWidget);
          if (fails) {
            pending.completeError(StateError('Late injected failure'));
          } else {
            pending.complete([_video]);
          }
          await tester.pumpAndSettle();
          await _tapVisible(tester, find.widgetWithText(ChoiceChip, 'YouTube'));
          expect(searches, ['music']);
          expect(find.byType(YoutubeCard), findsNothing);
          expect(find.text(_video.title), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('Retry YouTube search'), findsNothing);
          expect(
            find.textContaining('Could not load YouTube results'),
            findsNothing,
          );
          expect(find.text('Search YouTube'), findsOneWidget);
          await _tapVisible(tester, find.byTooltip('Clear search'));
          expect(find.text('Recent searches'), findsNothing);
          expect(videoTaps, isEmpty);
          _expectNoExternalControls();
          expect(songTaps, isEmpty);
          _expectEmptyCatalog(service);
          expect(tester.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) pending.complete([]);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}
