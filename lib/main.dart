import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'services/audio_service.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/local_screen.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/mini_player.dart';
import 'widgets/motion.dart';
import 'models/song.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.harmoniq.channel.audio',
    androidNotificationChannelName: 'Harmoniq Audio Playback',
    androidNotificationOngoing: true,
    androidShowNotificationBadge: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harmoniq',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissionsOnce();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (ctx, a1, a2) => const MainContainer(),
            transitionsBuilder: (ctx, animation, a2, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: motionDuration(context, 320),
          ),
        );
      }
    });
  }

  Future<void> _checkAndRequestPermissionsOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyAsked =
          prefs.getBool('has_prompted_app_permissions') ?? false;
      if (!alreadyAsked) {
        const platform = MethodChannel('com.example.harmoniq/local_music');
        await platform.invokeMethod('requestAllPermissions');
        await prefs.setBool('has_prompted_app_permissions', true);
      }
    } catch (e) {
      debugPrint('[PERMISSIONS] Initial check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EnterTransition(
              child: Image.asset(
                'assets/logo.png',
                width: 240,
                height: 240,
                cacheWidth: 720,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'YOUR MUSIC. YOUR RHYTHM.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainContainer extends StatefulWidget {
  final AudioService? audioService;
  const MainContainer({super.key, this.audioService});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;
  late final PageController _pageController;
  late final AudioService _audioService;

  late final List<Widget> _pages;
  final _searchKey = GlobalKey<SearchScreenState>();

  @override
  void initState() {
    super.initState();
    _audioService = widget.audioService ?? AudioService();
    _pageController = PageController();
    unawaited(_scanIfAllowed());

    _pages = [
      HomeScreen(
        onLocalTap: () => _onTabTap(3),
        onSearchTap: _openSearch,
        audioService: _audioService,
        onSongTap: (song, [queue]) =>
            _playSong(song, contextQueue: queue ?? _audioService.songs),
        onPlaylistPlayTap: (playlist) {
          final local = playlist.songs
              .where((song) => song.source != SongSource.legacy)
              .toList();
          if (local.isNotEmpty) _playSong(local.first, contextQueue: local);
        },
      ),
      SearchScreen(
        key: _searchKey,
        audioService: _audioService,
        onQueueTap: (song, queue) => _playSong(song, contextQueue: queue),
        onSongTap: (song) => _playSong(song, contextQueue: _audioService.songs),
        onFavoriteTap: _audioService.toggleFavorite,
      ),
      LibraryScreen(
        audioService: _audioService,
        onSongTap: (song) => _playSong(song, contextQueue: _audioService.songs),
        onFavoriteTap: _audioService.toggleFavorite,
        onCreatePlaylist: _audioService.createPlaylist,
      ),
      LocalScreen(
        audioService: _audioService,
        onSongTap: (song) =>
            _playSong(song, contextQueue: _audioService.localSongs),
        onFavoriteTap: _audioService.toggleFavorite,
        onScanTap: _audioService.scanLocalSongs,
      ),
    ];
  }

  Future<void> _scanIfAllowed() async {
    try {
      const channel = MethodChannel('com.example.harmoniq/local_music');
      final allowed =
          await channel.invokeMethod<bool>('checkPermission') ?? false;
      if (mounted && allowed && _audioService.localSongs.isEmpty) {
        await _audioService.scanLocalSongs();
      }
    } on PlatformException {
      // Permissions can still be requested explicitly from the Local tab.
    } on MissingPluginException {
      // Device scanning is available on Android only.
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    if (widget.audioService == null) _audioService.dispose();
    super.dispose();
  }

  void _onTabTap(int index) {
    if (index == _currentIndex) return;
    if (MediaQuery.disableAnimationsOf(context) ||
        (index - _currentIndex).abs() > 1) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _playSong(Song song, {List<Song>? contextQueue}) async {
    if (song.source == SongSource.legacy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This saved track is from the previous source.'),
          action: SnackBarAction(
            label: 'Search device',
            onPressed: () => _openSearch('${song.title} ${song.artist}'),
          ),
        ),
      );
      return;
    }
    unawaited(_audioService.playSong(song, contextQueue: contextQueue));
    _openNowPlaying();
  }

  void _openSearch(String query) {
    _pageController.jumpToPage(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchKey.currentState?.setQuery(query);
    });
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (ctx, a1, a2) => NowPlayingScreen(
          audioService: _audioService,
          onClose: () => Navigator.pop(context),
        ),
        transitionsBuilder: (ctx, animation, a2, child) {
          final tween = Tween(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeInOutCubic));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: motionDuration(context, 340),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            children: List.generate(
              _pages.length,
              (index) => _RetainedPage(
                child: TickerMode(
                  enabled: index == _currentIndex,
                  child: _pages[index],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListenableBuilder(
                listenable: _audioService,
                builder: (context, child) {
                  final song = _audioService.currentSong;
                  final player = song == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 10),
                          child: MiniPlayer(
                            song: song,
                            isPlaying: _audioService.isPlaying,
                            isLoading: _audioService.isLoading,
                            playbackError: _audioService.playbackError,
                            wantsToPlay: _audioService.wantsToPlay,
                            onRetryTap: _audioService.retryPlayback,
                            positionNotifier:
                                _audioService.playbackPositionNotifier,
                            onTap: _openNowPlaying,
                            onPlayPauseTap: _audioService.togglePlay,
                            onNextTap: _audioService.next,
                            onPreviousTap: _audioService.previous,
                            onCloseTap: _audioService.stopAndClear,
                          ),
                        );
                  if (MediaQuery.disableAnimationsOf(context)) return player;
                  return AnimatedSize(
                    duration: motionDuration(context),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: player,
                  );
                },
              ),
              BottomNav(currentIndex: _currentIndex, onTap: _onTabTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetainedPage extends StatefulWidget {
  final Widget child;
  const _RetainedPage({required this.child});

  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
