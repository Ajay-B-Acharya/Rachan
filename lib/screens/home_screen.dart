import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/online_music_service.dart';
import '../theme/app_colors.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/song_tile.dart';

class HomeScreen extends StatefulWidget {
  final AudioService audioService;
  final Function(Song, [List<Song>? queue]) onSongTap;
  final ValueChanged<Playlist> onPlaylistPlayTap;
  final VoidCallback? onLocalTap;
  final ValueChanged<String>? onSearchTap;
  final Future<List<Song>> Function()? loadOnlineTracks;

  const HomeScreen({
    super.key,
    required this.audioService,
    required this.onSongTap,
    required this.onPlaylistPlayTap,
    this.onLocalTap,
    this.onSearchTap,
    this.loadOnlineTracks,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> _trending = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs =
          await (widget.loadOnlineTracks?.call() ??
              OnlineMusicService.instance.trending(refresh: refresh));
      if (!mounted) return;
      widget.audioService.registerSongs(songs);
      setState(() {
        _trending = songs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Online music is unavailable right now. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          key: const PageStorageKey('home-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
              sliver: SliverToBoxAdapter(
                child: EnterTransition(
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/brand_mark.png',
                          width: 42,
                          height: 42,
                          cacheWidth: 126,
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Text(
                          'harmoniq',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Search music',
                        onPressed: () => widget.onSearchTap?.call(''),
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverToBoxAdapter(
                child: EnterTransition(
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8CDFA),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DISCOVER SOMETHING DIFFERENT',
                          style: TextStyle(
                            color: Color(0xFF51465E),
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Press play.\nBe here.',
                          style: TextStyle(
                            color: Color(0xFF201B2A),
                            fontSize: 40,
                            height: 1.05,
                            letterSpacing: -1.7,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Fresh sounds from Audius.\nYour next favorite is out there.',
                          style: TextStyle(
                            color: Color(0xFF51465E),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _trending.isEmpty
                              ? () => widget.onSearchTap?.call('')
                              : () => widget.onSongTap(
                                  _trending.first,
                                  _trending,
                                ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF201B2A),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            _trending.isEmpty
                                ? 'Discover music'
                                : 'Play trending',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                            'Electronic',
                            'Hip-Hop/Rap',
                            'House',
                            'Pop',
                            'Ambient',
                            'Jazz',
                          ]
                          .map(
                            (genre) => ActionChip(
                              label: Text(genre),
                              onPressed: () => widget.onSearchTap?.call(genre),
                              backgroundColor: AppColors.backgroundSurface,
                              side: BorderSide.none,
                            ),
                          )
                          .toList(),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trending on Audius',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Independent artists, edits, and new discoveries',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh online music',
                      onPressed: _loading ? null : () => _load(refresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading && _trending.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (_error != null)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      TextButton(
                        onPressed: () => _load(refresh: true),
                        child: const Text('Retry discovery'),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_loading && _error == null && _trending.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'No public tracks available right now.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            if (_trending.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      248 + (MediaQuery.textScalerOf(context).scale(64) - 64),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: _trending.length,
                    separatorBuilder: (_, index) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final song = _trending[index];
                      return SizedBox(
                        width: 156,
                        child: Pressable(
                          onTap: () => widget.onSongTap(song, _trending),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AlbumArt(
                                gradientId: song.gradientId,
                                size: 156,
                                borderRadius: 14,
                                showShadow: false,
                                imageUrl: song.albumArtUrl,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                song.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
              sliver: SliverToBoxAdapter(
                child: Pressable(
                  onTap: widget.onLocalTap,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSurface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.offline_pin_outlined,
                          color: AppColors.accent,
                          size: 26,
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your offline collection',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Device music, always with you.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: ListenableBuilder(
                  listenable: widget.audioService,
                  builder: (context, _) {
                    final favorites = widget.audioService.favorites
                        .where((s) => s.source != SongSource.legacy)
                        .take(5)
                        .toList();
                    if (favorites.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'On your favorites list',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        ...favorites.map(
                          (song) => SongTile(
                            song: song,
                            isActive: widget.audioService.currentSong == song,
                            isPlaying:
                                widget.audioService.currentSong == song &&
                                widget.audioService.isPlaying,
                            onTap: () => widget.onSongTap(song, favorites),
                            onFavoriteTap: () =>
                                widget.audioService.toggleFavorite(song),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 28),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Streaming provided by Audius. Catalog availability differs from Spotify.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
