import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/main.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/models/youtube_video.dart';
import 'package:harmoniq/screens/home_screen.dart';
import 'package:harmoniq/screens/now_playing_screen.dart';
import 'package:harmoniq/screens/search_screen.dart';
import 'package:harmoniq/services/audio_service.dart';
import 'package:harmoniq/theme/app_theme.dart';
import 'package:harmoniq/widgets/mini_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _firstTrack = YoutubeVideo(
  id: 'dQw4w9WgXcQ',
  title: 'First native track',
  artist: 'Test artist',
  thumbnailUrl: '',
  duration: Duration(minutes: 3),
);
const _secondTrack = YoutubeVideo(
  id: 'M7lc1UVf-VE',
  title: 'Second native track',
  artist: 'Another artist',
  thumbnailUrl: '',
  duration: Duration(minutes: 4),
);

// Exercise MainContainer's real routing without a resolver, audio stream, or
// platform player. AudioService's resolver/state-machine tests live elsewhere.
class _RoutingAudioService extends AudioService {
  final requests = <Song>[];
  List<Song> _requestedQueue = [];
  Song? _selected;
  var disposed = false;

  @override
  Song? get currentSong => _selected;

  @override
  List<Song> get queue => List.unmodifiable(_requestedQueue);

  @override
  int get currentQueueIndex =>
      _selected == null ? -1 : _requestedQueue.indexOf(_selected!);

  @override
  bool get isPlaying => _selected != null;

  @override
  bool get isLoading => false;

  @override
  bool get wantsToPlay => isPlaying;

  @override
  bool get canSeek => _selected != null;

  @override
  String? get playbackError => null;

  @override
  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    requests.add(song);
    _selected = song;
    _requestedQueue = List.of(contextQueue ?? [song]);
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  testWidgets('Splash reaches YouTube home and mood opens search', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('next obsession.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('After hours'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('After hours'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Late night R&B',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final fromSearch in [false, true]) {
    testWidgets(
      '${fromSearch ? 'Search' : 'Home'} result callbacks open native player with converted queue and persistent mini player',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _RoutingAudioService();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
              home: MainContainer(audioService: service),
            ),
          );
          // Widget tests block HTTP. Drain no-key discovery's bounded timeout;
          // routing uses injected metadata and never waits for a live service.
          await tester.pump(const Duration(seconds: 21));
          await tester.pumpAndSettle();
          final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
          expect(home.audioService, same(service));
          void Function(YoutubeVideo, List<YoutubeVideo>)? playQueue;
          ValueChanged<YoutubeVideo>? playSingle;
          if (fromSearch) {
            await tester.tap(find.byTooltip('Search music'));
            await tester.pumpAndSettle();
            final search = tester.widget<SearchScreen>(
              find.byType(SearchScreen),
            );
            expect(search.audioService, same(service));
            playQueue = search.onVideoQueueTap;
            playSingle = search.onVideoTap;
          } else {
            playQueue = home.onVideoQueueTap;
            playSingle = home.onVideoTap;
          }
          expect(playQueue, isNotNull);
          expect(playSingle, isNotNull);
          // Card taps and fallback dispatch are independently tested by the
          // journey suite; here verify their actual MainContainer wiring.
          playQueue!(_secondTrack, [_firstTrack, _secondTrack]);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(service.requests, hasLength(1));
          expect(service.currentSong!.source, SongSource.youtube);
          expect(service.currentSong!.videoId, _secondTrack.id);
          expect(service.currentSong!.title, _secondTrack.title);
          expect(service.currentSong!.artist, _secondTrack.artist);
          expect(service.currentSong!.duration, _secondTrack.duration);
          expect(service.currentSong!.audioPath, isEmpty);
          expect(service.queue.map((song) => song.videoId), [
            _firstTrack.id,
            _secondTrack.id,
          ]);
          expect(
            service.queue.every((song) => song.source == SongSource.youtube),
            isTrue,
          );
          expect(service.currentQueueIndex, 1);
          expect(find.byType(NowPlayingScreen), findsOneWidget);
          expect(
            tester
                .widget<NowPlayingScreen>(find.byType(NowPlayingScreen))
                .audioService,
            same(service),
          );
          expect(find.text('NOW PLAYING'), findsOneWidget);
          expect(find.text('YOUTUBE · AUDIO'), findsOneWidget);
          expect(find.text(_secondTrack.title), findsOneWidget);
          expect(find.byTooltip('Pause'), findsOneWidget);
          expect(find.byType(Slider), findsOneWidget);

          await tester.tap(find.byTooltip('Minimize player'));
          await tester.pumpAndSettle();
          expect(find.byType(NowPlayingScreen), findsNothing);
          expect(find.byType(MiniPlayer), findsOneWidget);
          expect(
            tester.widget<MiniPlayer>(find.byType(MiniPlayer)).song,
            service.currentSong,
          );
          await tester.tap(find.text(_secondTrack.title));
          await tester.pumpAndSettle();
          expect(find.byType(NowPlayingScreen), findsOneWidget);
          expect(
            service.requests,
            hasLength(1),
            reason: 'Reopening must not restart playback',
          );
          await tester.tap(find.byTooltip('Minimize player'));
          await tester.pumpAndSettle();

          playSingle!(_firstTrack);
          await tester.pumpAndSettle();
          expect(find.byType(NowPlayingScreen), findsOneWidget);
          expect(service.requests, hasLength(2));
          expect(service.currentSong!.videoId, _firstTrack.id);
          expect(service.queue.map((song) => song.videoId), [_firstTrack.id]);
          expect(service.currentQueueIndex, 0);
          if (fromSearch) {
            await tester.tap(find.byTooltip('Minimize player'));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextField),
              'https://music.youtube.com/watch?v=${_secondTrack.id}',
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Play this song'));
            await tester.pumpAndSettle();
            expect(find.byType(NowPlayingScreen), findsOneWidget);
            expect(service.requests, hasLength(3));
            expect(service.currentSong!.source, SongSource.youtube);
            expect(service.currentSong!.videoId, _secondTrack.id);
            expect(service.currentSong!.title, 'YouTube track');
            expect(
              service.currentSong!.albumArtUrl,
              'https://i.ytimg.com/vi/${_secondTrack.id}/hqdefault.jpg',
            );
            expect(service.queue.map((song) => song.videoId), [
              _secondTrack.id,
            ]);
            expect(find.text('YouTube track'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(
            service.disposed,
            isFalse,
            reason: 'Injected service is caller-owned',
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          service.dispose();
        }
      },
    );
  }
}
