import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/models/playlist.dart';
import 'package:harmoniq/models/youtube_video.dart';
import 'package:harmoniq/screens/library_screen.dart';
import 'package:harmoniq/screens/local_screen.dart';
import 'package:harmoniq/widgets/song_tile.dart';
import 'package:harmoniq/screens/home_screen.dart';
import 'package:harmoniq/screens/now_playing_screen.dart';
import 'package:harmoniq/services/audio_service.dart';
import 'package:harmoniq/theme/app_theme.dart';
import 'package:harmoniq/widgets/bottom_nav.dart';
import 'package:harmoniq/widgets/mini_player.dart';
import 'package:harmoniq/widgets/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _track(int id, {bool longMetadata = false}) => Song(
  id: id,
  title: longMetadata
      ? 'A very long track title with many words that must remain readable $id'
      : 'Track $id',
  artist: longMetadata
      ? 'An exceptionally long artist name with several collaborators'
      : 'Artist $id',
  album: longMetadata
      ? 'An extended album name that should truncate inside the player header'
      : 'Album $id',
  duration: const Duration(minutes: 3),
  // Playback methods below are overridden; no audio source is ever loaded.
  audioPath: '',
  gradientId: id,
);

Song _youtubeTrack(String videoId, {bool longMetadata = false}) {
  final metadata = _track(0, longMetadata: longMetadata);
  return Song.fromYoutube(
    YoutubeVideo(
      id: videoId,
      title: longMetadata ? metadata.title : 'YouTube $videoId',
      artist: metadata.artist,
      thumbnailUrl: '',
      duration: metadata.duration,
    ),
  );
}

/// Keeps the real ChangeNotifier contract, but never invokes player playback.
class _FakeAudioService extends AudioService {
  List<Song> testQueue = [];
  int index = -1;
  bool playing = false;
  bool loading = false;
  bool? playIntent;
  String? error;
  int retries = 0;
  final List<Duration> seekRequests = [];
  List<Song> testLocalSongs = [];
  List<Song> testSongs = [];
  List<Song> testFavorites = [];
  List<Playlist> testPlaylists = [];
  final List<String> playRequests = [];
  final List<int> skipRequests = [];

  @override
  Song? get currentSong => index < 0 ? null : testQueue[index];
  @override
  List<Song> get queue => testQueue;
  @override
  int get currentQueueIndex => index;
  @override
  bool get isPlaying => playing;
  @override
  bool get isLoading => loading;
  @override
  bool get wantsToPlay => playIntent ?? playing;
  @override
  String? get playbackError => error;
  @override
  bool get canSeek => currentSong != null && !loading && error == null;
  @override
  List<Song> get localSongs => testLocalSongs;
  @override
  List<Song> get songs => testSongs;
  @override
  List<Song> get favorites => testFavorites;
  @override
  List<Playlist> get playlists => testPlaylists;

  void updatePlayback({
    required bool isLoading,
    required bool wantsToPlay,
    String? playbackError,
  }) {
    loading = isLoading;
    playIntent = wantsToPlay;
    error = playbackError;
    notifyListeners();
  }

  @override
  Future<void> retryPlayback() async {
    retries++;
    updatePlayback(isLoading: true, wantsToPlay: true);
  }

  void externalJump(int nextIndex) {
    index = nextIndex;
    playbackPositionNotifier.value = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    playRequests.add(song.identity);
    if (contextQueue != null) testQueue = List.of(contextQueue);
    externalJump(
      testQueue.indexWhere((item) => item.identity == song.identity),
    );
  }

  @override
  Future<void> skipToIndex(int nextIndex) async {
    skipRequests.add(nextIndex);
    externalJump(nextIndex);
  }

  @override
  Future<void> togglePlay() async {
    if (loading) {
      playIntent = !wantsToPlay;
    } else {
      playing = !playing;
      playIntent = playing;
    }
    notifyListeners();
  }

  @override
  Future<void> next() async => externalJump((index + 1) % testQueue.length);

  @override
  Future<void> previous() async =>
      externalJump((index - 1 + testQueue.length) % testQueue.length);

  @override
  Future<void> seek(Duration position) async {
    seekRequests.add(position);
    playbackPositionNotifier.value = position;
  }

  @override
  Future<void> stopAndClear() async {
    playing = false;
    externalJump(-1);
  }
}

Widget _app(Widget child, {double textScale = 1, bool reduceMotion = true}) =>
    MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: child,
    );

Future<void> _viewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeAudioService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = _FakeAudioService();
    // Finish favorites initialization outside the widget test's fake clock.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => service.dispose());

  for (final scale in [1.0, 1.5]) {
    testWidgets('home fits 320px at text scale $scale and opens local music', (
      tester,
    ) async {
      await _viewport(tester, const Size(320, 640));
      var localTaps = 0;
      try {
        await tester.pumpWidget(
          _app(
            HomeScreen(
              audioService: service,
              youtubeConfigured: false,
              onSongTap: (_, [queue]) {},
              onPlaylistPlayTap: (_) {},
              onLocalTap: () => localTaps++,
            ),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('next obsession.'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('The offline collection'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('The offline collection'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('The offline collection'));
        await tester.pumpAndSettle();
        expect(localTaps, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  testWidgets('bottom navigation exposes selected labels and all tab actions', (
    tester,
  ) async {
    await _viewport(tester, const Size(320, 640));
    final semantics = tester.ensureSemantics();
    try {
      var selected = 0;
      final taps = <int>[];
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: BottomNav(
                currentIndex: selected,
                onTap: (index) => setState(() {
                  selected = index;
                  taps.add(index);
                }),
              ),
            ),
          ),
          textScale: 1.5,
        ),
      );
      const labels = ['Home', 'Search', 'Library', 'Local'];
      for (var index = 0; index < labels.length; index++) {
        final target = find.bySemanticsLabel(labels[index]);
        expect(target, findsOneWidget);
        final data = tester.getSemantics(target).getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(
          data.flagsCollection.isSelected,
          index == selected ? Tristate.isTrue : Tristate.isFalse,
        );
        final inkWell = find.ancestor(
          of: find.text(labels[index]),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(inkWell).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(inkWell).height, greaterThanOrEqualTo(48));
        await tester.tap(find.text(labels[index]));
        await tester.pumpAndSettle();
        expect(selected, index);
        expect(
          tester
              .getSemantics(target)
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
      }
      expect(taps, [0, 1, 2, 3]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('EnterTransition is immediately visible with reduced motion', (
    tester,
  ) async {
    const childKey = ValueKey('entered-child');
    await tester.pumpWidget(
      _app(
        const EnterTransition(
          delay: Duration(seconds: 2),
          child: Text('Ready', key: childKey),
        ),
      ),
    );
    expect(find.byKey(childKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(EnterTransition),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('EnterTransition still animates when motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const EnterTransition(child: Text('Animated')), reduceMotion: false),
    );
    final opacity = find.descendant(
      of: find.byType(EnterTransition),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(320, 480), const Size(844, 390)]) {
    testWidgets('full player fits $size with long metadata and scaled text', (
      tester,
    ) async {
      await _viewport(tester, size);
      service.testQueue = [_track(0, longMetadata: true), _track(1)];
      service.index = 0;
      var closes = 0;
      await tester.pumpWidget(
        _app(
          NowPlayingScreen(audioService: service, onClose: () => closes++),
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.text(service.currentSong!.title));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
      await tester.ensureVisible(find.byTooltip('Play'));
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(service.isPlaying, isTrue);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.ensureVisible(find.text('UP NEXT'));
      await tester.tap(find.text('UP NEXT'));
      await tester.pumpAndSettle();
      expect(find.text('Your queue'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final queueRouteContext = tester.element(find.text('Your queue'));
      Navigator.of(queueRouteContext).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Stop and close'));
      await tester.tap(find.byTooltip('Stop and close'));
      await tester.pumpAndSettle();
      expect(service.currentSong, isNull);
      expect(closes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('external queue jumps do not play intermediate carousel pages', (
    tester,
  ) async {
    await _viewport(tester, const Size(400, 900));
    service.testQueue = List.generate(5, _track);
    service.index = 0;
    await tester.pumpWidget(
      _app(NowPlayingScreen(audioService: service, onClose: () {})),
    );
    await tester.pumpAndSettle();
    service.externalJump(1);
    service.externalJump(4);
    await tester.pumpAndSettle();
    final carousel = find.byType(PageView);
    expect(tester.widget<PageView>(carousel).controller!.page, 4);
    expect(service.skipRequests, isEmpty);
    expect(service.playRequests, isEmpty);
    expect(find.text('Track 4'), findsOneWidget);

    // A genuine drag still selects exactly the adjacent track.
    await tester.drag(carousel, const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(service.skipRequests, [3]);
    expect(service.currentQueueIndex, 3);

    await tester.ensureVisible(find.text('UP NEXT'));
    await tester.tap(find.text('UP NEXT'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Track 0'));
    await tester.pumpAndSettle();
    expect(service.playRequests, [_track(0).identity]);
    expect(service.skipRequests, [3]);
    expect(service.currentQueueIndex, 0);
    expect(tester.widget<PageView>(carousel).controller!.page, 0);
    expect(find.text('Your queue'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('YouTube loading keeps pause intent and gates seeking', (
    tester,
  ) async {
    await _viewport(tester, const Size(400, 1000));
    service.testQueue = [_youtubeTrack('abcdefghijk')];
    service.index = 0;
    service.loading = true;
    service.playIntent = true;
    await tester.pumpWidget(
      _app(NowPlayingScreen(audioService: service, onClose: () {})),
    );
    expect(find.text('YOUTUBE · AUDIO'), findsOneWidget);
    expect(find.text('Loading audio…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(
      tester.widget<Hero>(find.byType(Hero).first).tag,
      'album-art-${service.currentSong!.identity}',
    );
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(service.wantsToPlay, isFalse);
    expect(find.text('Loading audio… · Paused'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();
    expect(service.seekRequests, isEmpty);

    service.updatePlayback(isLoading: false, wantsToPlay: false);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(service.seekRequests, isNotEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('full player wraps long errors and retries at 320px', (
    tester,
  ) async {
    await _viewport(tester, const Size(320, 480));
    service.testQueue = [_youtubeTrack('abcdefghijk', longMetadata: true)];
    service.index = 0;
    service.error =
        'Could not load audio. Check your connection and try again. ' * 5;
    await tester.pumpWidget(
      _app(
        NowPlayingScreen(audioService: service, onClose: () {}),
        textScale: 1.5,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(service.error!), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await tester.ensureVisible(find.text('Retry playback'));
    await tester.tap(find.text('Retry playback'));
    await tester.pump();
    expect(service.retries, 1);
    expect(find.text('Loading audio…'), findsOneWidget);
    expect(find.text('Retry playback'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mini loading and long errors preserve independent controls', (
    tester,
  ) async {
    await _viewport(tester, const Size(320, 640));
    var opens = 0;
    var retries = 0;
    var toggles = 0;
    var loading = true;
    var wantsToPlay = true;
    String? error;
    late StateSetter update;
    final song = _youtubeTrack('abcdefghijk', longMetadata: true);
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              bottomNavigationBar: MiniPlayer(
                song: song,
                isPlaying: false,
                isLoading: loading,
                wantsToPlay: wantsToPlay,
                playbackError: error,
                onRetryTap: () => retries++,
                positionNotifier: service.playbackPositionNotifier,
                onTap: () => opens++,
                onPlayPauseTap: () async {
                  toggles++;
                  setState(() => wantsToPlay = !wantsToPlay);
                },
                onNextTap: () async {},
                onCloseTap: () async {},
              ),
            );
          },
        ),
        textScale: 1.5,
      ),
    );
    expect(find.text('Loading audio…'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      'album-art-${song.identity}',
    );
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(toggles, 1);
    expect(wantsToPlay, isFalse);
    expect(find.text('Loading audio… · Paused'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    update(() {
      loading = false;
      error =
          'Audio unavailable. Please check your connection and try again. ' * 8;
    });
    await tester.pumpAndSettle();
    final message = tester.widget<Text>(find.text(error!));
    expect(message.maxLines, 2);
    expect(message.overflow, TextOverflow.ellipsis);
    await tester.tap(find.byTooltip('Retry playback'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(opens, 0);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Next track'), findsOneWidget);
    expect(find.byTooltip('Close song'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'library keeps colliding source IDs and accepts YouTube favorites and playlists',
    (tester) async {
      await _viewport(tester, const Size(500, 900));
      final local = _track(0);
      final youtube = _youtubeTrack('abcdefghijk');
      final secondYoutube = _youtubeTrack('lmnopqrstuv');
      final legacy = _track(0)
          .copyWith(source: SongSource.legacy, title: 'Old favorite');
      service.testLocalSongs = [local];
      service.testSongs = [
        local.copyWith(title: 'Duplicate local'),
        youtube,
        secondYoutube,
        legacy,
      ];
      service.testFavorites = [youtube, legacy];
      service.testPlaylists = [
        Playlist(
          id: 1,
          name: 'Online playlist',
          songs: [youtube],
          gradientId: 0,
        ),
      ];
      service.testQueue = [youtube];
      service.index = 0;
      final taps = <String>[];
      await tester.pumpWidget(
        _app(
          LibraryScreen(
            audioService: service,
            onSongTap: (song) => taps.add(song.identity),
            onFavoriteTap: (_) {},
            onCreatePlaylist: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tiles = tester.widgetList<SongTile>(find.byType(SongTile)).toList();
      expect(tiles.map((tile) => tile.song.identity), [
        local.identity,
        youtube.identity,
        secondYoutube.identity,
        legacy.identity,
      ]);
      expect(
        tiles.where((tile) => tile.isActive).single.song.identity,
        youtube.identity,
      );
      expect(find.text('Duplicate local'), findsNothing);
      await tester.tap(find.text(secondYoutube.title));
      await tester.pumpAndSettle();
      expect(taps, [secondYoutube.identity]);
      await tester.ensureVisible(find.text('Favorites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YOUTUBE (1)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Previous-source favorites are saved'),
        findsNothing,
      );
      await tester.tap(find.text(youtube.title));
      await tester.pumpAndSettle();
      expect(taps.last, youtube.identity);
      await tester.tap(find.text('ALL (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(legacy.title));
      await tester.pumpAndSettle();
      expect(taps.length, 2);
      expect(
        find.textContaining('Previous source unavailable.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Online playlist'));
      await tester.pumpAndSettle();
      expect(taps, [
        secondYoutube.identity,
        youtube.identity,
        youtube.identity,
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'local highlights source-aware identity and retains local actions',
    (tester) async {
      await _viewport(tester, const Size(400, 800));
      final local = _track(0);
      service.testLocalSongs = [local];
      service.testQueue = [_youtubeTrack('abcdefghijk'), local];
      service.index = 0;
      var plays = 0;
      var favorites = 0;
      await tester.pumpWidget(
        _app(
          LocalScreen(
            audioService: service,
            onSongTap: (_) => plays++,
            onFavoriteTap: (_) => favorites++,
            onScanTap: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SongTile>(find.byType(SongTile)).isActive, isFalse);
      await tester.tap(find.text(local.title));
      await tester.tap(find.byTooltip('Add favorite'));
      expect([plays, favorites], [1, 1]);
      service.externalJump(1);
      await tester.pumpAndSettle();
      expect(tester.widget<SongTile>(find.byType(SongTile)).isActive, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('mini player actions remain separate and progress is clamped', (
    tester,
  ) async {
    await _viewport(tester, const Size(320, 640));
    var opens = 0;
    var toggles = 0;
    var nexts = 0;
    var closes = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          bottomNavigationBar: MiniPlayer(
            song: _track(0, longMetadata: true),
            isPlaying: true,
            positionNotifier: service.playbackPositionNotifier,
            onTap: () => opens++,
            onPlayPauseTap: () async => toggles++,
            onNextTap: () async => nexts++,
            onCloseTap: () async => closes++,
          ),
        ),
        textScale: 1.5,
      ),
    );
    await tester.pumpAndSettle();
    for (final tooltip in ['Pause', 'Next track', 'Close song']) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
    }
    expect([toggles, nexts, closes], [1, 1, 1]);
    expect(opens, 0);
    await tester.tap(find.text(_track(0, longMetadata: true).artist));
    expect(opens, 1);
    service.playbackPositionNotifier.value = const Duration(hours: 1);
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
