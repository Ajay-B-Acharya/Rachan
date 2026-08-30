import 'dart:math';

import 'package:flutter/material.dart';

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

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rachan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}

// Custom animated wave splash loader
class WavesSplash extends StatefulWidget {
  const WavesSplash({super.key});

  @override
  State<WavesSplash> createState() => _WavesSplashState();
}

class _WavesSplashState extends State<WavesSplash>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(5, (index) {
            double factor =
                (sin((_controller.value * pi) + (index * 0.45)) + 1) / 2;
            double height = 12 + (30 * factor);

            return Container(
              width: 5,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.accent,
                    AppColors.accentLight.withOpacity(0.5),
                  ],
                ),
              ),
            );
          }),
        );
      },
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
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const MainContainer(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const WavesSplash(),
            const SizedBox(height: 24),
            ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  colors: [
                    AppColors.accentLight,
                    AppColors.accent,
                    AppColors.accentLight.withOpacity(0.8),
                  ],
                ).createShader(bounds);
              },
              child: const Text(
                "RACHAN",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Your Personal Music Sanctuary",
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;
  late final AudioService _audioService;

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _audioService,
      builder: (context, _) {
        final currentSong = _audioService.currentSong;

        final screens = [
          HomeScreen(
            songs: _audioService.songs,
            playlists: _audioService.playlists,
            currentSong: currentSong,
            onSongTap: (song) =>
                _audioService.playSong(song, contextQueue: _audioService.songs),
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
            songs: _audioService.songs,
            currentSong: currentSong,
            onSongTap: (song) =>
                _audioService.playSong(song, contextQueue: _audioService.songs),
            onFavoriteTap: _audioService.toggleFavorite,
          ),
          LibraryScreen(
            songs: _audioService.songs,
            playlists: _audioService.playlists,
            currentSong: currentSong,
            onSongTap: (song) =>
                _audioService.playSong(song, contextQueue: _audioService.songs),
            onFavoriteTap: _audioService.toggleFavorite,
            onCreatePlaylist: _audioService.createPlaylist,
          ),
          LocalScreen(
            localSongs: _audioService.localSongs,
            isScanning: _audioService.isScanning,
            currentSong: currentSong,
            onSongTap: (song) => _audioService.playSong(
              song,
              contextQueue: _audioService.localSongs,
            ),
            onFavoriteTap: _audioService.toggleFavorite,
            onScanTap: _audioService.scanLocalSongs,
          ),
        ];

        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              IndexedStack(index: _currentIndex, children: screens),
              // Mini Player and Navigation overlay
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentSong != null)
                      MiniPlayer(
                        song: currentSong,
                        isPlaying: _audioService.isPlaying,
                        playbackProgress:
                            currentSong.duration.inMilliseconds > 0
                            ? (_audioService.playbackPosition.inMilliseconds /
                                      currentSong.duration.inMilliseconds)
                                  .clamp(0.0, 1.0)
                            : 0.0,
                        onTap: _openNowPlaying,
                        onPlayPauseTap: _audioService.togglePlay,
                        onNextTap: _audioService.next,
                      ),
                    const SizedBox(height: 10),
                    BottomNav(
                      currentIndex: _currentIndex,
                      onTap: (index) {
                        setState(() {
                          _currentIndex = index;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            NowPlayingScreen(
              audioService: _audioService,
              onClose: () => Navigator.pop(context),
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          final tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }
}
