import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/jamendo_service.dart';
import '../theme/app_colors.dart';
import '../widgets/album_art.dart';
import '../widgets/glass_card.dart';
import '../widgets/song_card.dart';

class HomeScreen extends StatefulWidget {
  final AudioService audioService;
  final Function(Song, [List<Song>? queue]) onSongTap;
  final Function(Playlist) onPlaylistPlayTap;

  const HomeScreen({
    super.key,
    required this.audioService,
    required this.onSongTap,
    required this.onPlaylistPlayTap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final JamendoService _jamendoService = JamendoService.instance;

  List<Song> _trendingTracks = [];
  List<Song> _recentTracks = [];
  List<Song> _recommendedTracks = [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOnlineMusic();
  }

  Future<void> _loadOnlineMusic({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // Fetch trending, recent & recommended in parallel for optimal speed
      final results = await Future.wait([
        _jamendoService.getTrendingTracks(limit: 15, forceRefresh: forceRefresh),
        _jamendoService.getRecentlyDiscoveredTracks(
          limit: 15,
          forceRefresh: forceRefresh,
        ),
        _jamendoService.getRecommendedTracks(
          limit: 15,
          forceRefresh: forceRefresh,
        ),
      ]);

      if (!mounted) return;

      final trending = results[0];
      final recent = results[1];
      final recommended = results[2];

      // Register all fetched tracks into global audio service catalog
      widget.audioService.registerSongs([
        ...trending,
        ...recent,
        ...recommended,
      ]);

      setState(() {
        _trendingTracks = trending;
        _recentTracks = recent;
        _recommendedTracks = recommended;
        _isLoading = false;
        if (trending.isEmpty && recent.isEmpty && recommended.isEmpty) {
          _errorMessage =
              'Could not reach Jamendo servers. Check your internet connection.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network connection issue. Tap to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF140F26), AppColors.background],
            stops: [0.0, 0.45],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.backgroundSurface,
            onRefresh: () => _loadOnlineMusic(forceRefresh: true),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),

                  // ── Header ────────────────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Discover online and local music',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => _loadOnlineMusic(forceRefresh: true),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: AppColors.getGradientForId(3),
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 19,
                            backgroundColor: AppColors.backgroundSurface,
                            child: const Icon(
                              Icons.refresh_rounded,
                              color: AppColors.accent,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── Network Error Banner ──────────────────────────────────────
                  if (_errorMessage != null) ...[
                    GestureDetector(
                      onTap: () => _loadOnlineMusic(forceRefresh: true),
                      child: GlassCard(
                        borderRadius: 14,
                        blurSigma: 0,
                        color: Colors.red.withValues(alpha: 0.12),
                        borderColor: Colors.red.withValues(alpha: 0.3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wifi_off_rounded,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            const Text(
                              'Retry',
                              style: TextStyle(
                                color: AppColors.accentLight,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── ONLINE SECTION 1: Trending / Popular ─────────────────────
                  _buildSectionHeader(
                    title: 'Trending / Popular',
                    tag: 'ONLINE',
                    tagColor: AppColors.accentLight,
                    onSeeAll: () {},
                  ),
                  const SizedBox(height: 14),
                  _buildTrackCarousel(
                    tracks: _trendingTracks,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 32),

                  // ── ONLINE SECTION 2: Recently Discovered ───────────────────
                  _buildSectionHeader(
                    title: 'Recently Discovered',
                    tag: 'JAMENDO',
                    tagColor: const Color(0xFF38ef7d),
                    onSeeAll: () {},
                  ),
                  const SizedBox(height: 14),
                  _buildTrackCarousel(
                    tracks: _recentTracks,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 32),

                  // ── ONLINE SECTION 3: Recommended ────────────────────────────
                  _buildSectionHeader(
                    title: 'Recommended For You',
                    tag: 'FEATURED',
                    tagColor: const Color(0xFFFF512F),
                    onSeeAll: () {},
                  ),
                  const SizedBox(height: 14),
                  _buildTrackCarousel(
                    tracks: _recommendedTracks,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 32),

                  // ── DEVICE MUSIC SECTION (If available) ──────────────────────
                  ListenableBuilder(
                    listenable: widget.audioService,
                    builder: (context, _) {
                      final local = widget.audioService.localSongs;
                      if (local.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            title: 'From Your Device',
                            tag: 'LOCAL',
                            tagColor: Colors.amberAccent,
                            onSeeAll: () {},
                          ),
                          const SizedBox(height: 14),
                          _buildTrackCarousel(
                            tracks: local,
                            isLoading: false,
                          ),
                          const SizedBox(height: 32),
                        ],
                      );
                    },
                  ),

                  // ── Made For You (Playlists) ─────────────────────────────────
                  Text(
                    'Made For You',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                        ),
                  ),
                  const SizedBox(height: 16),

                  ListenableBuilder(
                    listenable: widget.audioService,
                    builder: (context, child) {
                      final currentPlaylists = widget.audioService.playlists;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: currentPlaylists.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.15,
                        ),
                        itemBuilder: (context, index) {
                          final playlist = currentPlaylists[index];
                          return GestureDetector(
                            onTap: () => widget.onPlaylistPlayTap(playlist),
                            child: GlassCard(
                              borderRadius: 14,
                              blurSigma: 0,
                              padding: const EdgeInsets.all(12),
                              color: Colors.white.withValues(alpha: 0.04),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      AlbumArt(
                                        gradientId: playlist.gradientId,
                                        size: 44,
                                        borderRadius: 8,
                                        showShadow: true,
                                        overlayIcon:
                                            Icons.playlist_play_rounded,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.12),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        playlist.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${playlist.songs.length} songs',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                              fontSize: 11,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 130),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String tag,
    required Color tagColor,
    required VoidCallback onSeeAll,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                  ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tagColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: tagColor.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  color: tagColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrackCarousel({
    required List<Song> tracks,
    required bool isLoading,
  }) {
    if (isLoading) {
      return SizedBox(
        height: 190,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          itemBuilder: (context, index) {
            return Container(
              width: 135,
              margin: const EdgeInsets.only(right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 135,
                    height: 135,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                        width: 1,
                      ),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 60,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    if (tracks.isEmpty) {
      return Container(
        height: 80,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No tracks available currently.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      );
    }

    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final song = tracks[index];
          return SongCard(
            song: song,
            onTap: () => widget.onSongTap(song, tracks),
          );
        },
      ),
    );
  }
}
