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

// ── Animated logo splash ───────────────────────────────────────────────────────
class _AnimatedLogo extends StatefulWidget {
  const _AnimatedLogo();

  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.78, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6)),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: child,
        ),
      ),
      // child is constant — only animation values change each frame
      child: Image.asset('assets/logo.png', width: 160, height: 160),
    );
  }
}

// ── Splash ────────────────────────────────────────────────────────────────────
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
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (ctx, a1, a2) => const MainContainer(),
            transitionsBuilder: (ctx, animation, a2, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
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
            const _AnimatedLogo(),
            const SizedBox(height: 20),
            const Text(
              'MUSIC LIVES WITH YOU',
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

// ── MainContainer ─────────────────────────────────────────────────────────────
//
// KEY PERFORMANCE RULES:
//
//  1. `_pages` is built ONCE in initState and never recreated. PageView keeps
//     all four screens alive across swipes — zero teardown/rebuild on tab
//     change.
//
//  2. `build()` only calls setState for `_currentIndex`. It does NOT listen to
//     AudioService at all. The bottom overlay has its own ListenableBuilder
//     so only MiniPlayer + BottomNav rebuild on audio state changes.
//
//  3. Audio position ticks go to `playbackPositionNotifier` (ValueNotifier),
//     consumed by ValueListenableBuilder inside MiniPlayer and NowPlayingScreen
//     only — zero notifyListeners() per tick.
//
class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;
  late final PageController _pageController;
  late final AudioService _audioService;

  // Pages are constructed ONCE. They each hold a reference to _audioService
  // and subscribe internally with their own ListenableBuilder — so no page
  // is ever rebuilt from here.
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    _pageController = PageController();

    _pages = [
      HomeScreen(
        audioService: _audioService,
        onSongTap: (song, [queue]) =>
            _audioService.playSong(song, contextQueue: queue ?? _audioService.songs),
        onPlaylistPlayTap: (playlist) {
          if (playlist.songs.isNotEmpty) {
            _audioService.playSong(
              playlist.songs[0],
              contextQueue: playlist.songs,
            );
          }
        },
      ),
      SearchScreen(
        audioService: _audioService,
        onSongTap: (song) =>
            _audioService.playSong(song, contextQueue: _audioService.songs),
        onFavoriteTap: _audioService.toggleFavorite,
      ),
      LibraryScreen(
        audioService: _audioService,
        onSongTap: (song) =>
            _audioService.playSong(song, contextQueue: _audioService.songs),
        onFavoriteTap: _audioService.toggleFavorite,
        onCreatePlaylist: _audioService.createPlaylist,
      ),
      LocalScreen(
        audioService: _audioService,
        onSongTap: (song) => _audioService.playSong(
          song,
          contextQueue: _audioService.localSongs,
        ),
        onFavoriteTap: _audioService.toggleFavorite,
        onScanTap: _audioService.scanLocalSongs,
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    _audioService.dispose();
    super.dispose();
  }

  void _onTabTap(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Page view: children never change after initState ───────────────
          PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentIndex = index),
            children: _pages,
          ),

          // ── Bottom overlay: only this slim section rebuilds on audio events.
          //    MiniPlayer's progress bar uses ValueListenableBuilder so even
          //    position ticks don't cause a rebuild here.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ListenableBuilder(
              listenable: _audioService,
              builder: (context, child) {
                final song = _audioService.currentSong;
                final isPlaying = _audioService.isPlaying;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (song != null)
                      MiniPlayer(
                        song: song,
                        isPlaying: isPlaying,
                        positionNotifier:
                            _audioService.playbackPositionNotifier,
                        onTap: _openNowPlaying,
                        onPlayPauseTap: _audioService.togglePlay,
                        onNextTap: _audioService.next,
                        onPreviousTap: _audioService.previous,
                        onCloseTap: _audioService.stopAndClear,
                      ),
                    const SizedBox(height: 10),
                    BottomNav(
                      currentIndex: _currentIndex,
                      onTap: _onTabTap,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
