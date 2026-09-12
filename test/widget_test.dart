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
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_service_test.dart' show TestAudioPlayer;

const track = Song(
  id: 7,
  title: 'My song',
  artist: 'My artist',
  album: 'My album',
  duration: Duration(minutes: 3),
  audioPath: '/music/song.mp3',
  gradientId: 1,
);

class LocalTestService extends AudioService {
  LocalTestService() : super(audioPlayer: TestAudioPlayer());

  Song? selected;
  bool disposed = false;
  @override
  List<Song> get localSongs => [track];
  @override
  List<Song> get songs => [track];
  @override
  Song? get currentSong => selected;
  @override
  List<Song> get queue => selected == null ? [] : [selected!];
  @override
  int get currentQueueIndex => selected == null ? -1 : 0;
  @override
  bool get isPlaying => selected != null;
  @override
  bool get wantsToPlay => isPlaying;
  @override
  bool get canSeek => selected != null;
  @override
  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    selected = song;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Splash opens discovery home without blocking on online music', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    // The framework blocks HTTP; expire the default discovery request as well.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Discover music'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Local home opens native player and keeps mini player', (
    tester,
  ) async {
    final service = LocalTestService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MainContainer(audioService: service),
      ),
    );
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    // The hero now discovers online music; exercise the retained local seam.
    tester.widget<HomeScreen>(find.byType(HomeScreen)).onSongTap(track, [
      track,
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.selected, track);
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Minimize player'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(service.disposed, isFalse);
    service.dispose();
  });

  testWidgets('Search filters local title artist album and clears', (
    tester,
  ) async {
    final service = LocalTestService();
    Song? played;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: SearchScreen(
          audioService: service,
          onSongTap: (song) => played = song,
          onFavoriteTap: (_) {},
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'MY ARTIST');
    await tester.pumpAndSettle();
    expect(find.text('My song'), findsOneWidget);
    await tester.tap(find.text('My song'));
    expect(played, track);
    await tester.enterText(find.byType(TextField), 'no matching song');
    await tester.pumpAndSettle();
    expect(find.text('No local results found'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('My song'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
}
