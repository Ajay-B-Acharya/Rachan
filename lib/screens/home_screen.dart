import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../models/youtube_video.dart';
import '../services/audio_service.dart';
import '../services/youtube_catalog.dart';
import '../theme/app_colors.dart';
import '../widgets/album_art.dart';
import '../widgets/motion.dart';
import '../widgets/youtube_card.dart';

class HomeScreen extends StatefulWidget {
  final AudioService audioService;
  final Function(Song, [List<Song>? queue]) onSongTap;
  final Function(Playlist) onPlaylistPlayTap;
  final VoidCallback? onLocalTap;
  final ValueChanged<String>? onSearchTap;
  final ValueChanged<YoutubeVideo>? onVideoTap;
  final void Function(YoutubeVideo, List<YoutubeVideo>)? onVideoQueueTap;
  final bool? youtubeConfigured;
  final Future<List<YoutubeVideo>> Function()? loadVideos;

  const HomeScreen({
    super.key,
    required this.audioService,
    required this.onSongTap,
    required this.onPlaylistPlayTap,
    this.onLocalTap,
    this.onSearchTap,
    this.onVideoTap,
    this.onVideoQueueTap,
    this.youtubeConfigured,
    this.loadVideos,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<YoutubeVideo> _videos = [];
  bool _loading = false;
  String? _error;
  bool get _configured =>
      widget.youtubeConfigured ?? YoutubeCatalog.instance.isAvailable;

  @override
  void initState() {
    super.initState();
    if (_configured) _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!_configured || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final videos =
          await (widget.loadVideos?.call() ??
              YoutubeCatalog.instance.discover(forceRefresh: refresh));
      if (mounted) {
        setState(() {
          _videos = videos;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is YoutubeSourceException
              ? error.message
              : 'Discovery is unavailable. Try a search or paste a video link.';
          _loading = false;
        });
      }
    }
  }

  void _playResult(YoutubeVideo video) {
    if (widget.onVideoQueueTap != null) {
      widget.onVideoQueueTap!(video, _videos);
    } else {
      widget.onVideoTap?.call(video);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _load(refresh: true),
          child: CustomScrollView(
            key: const PageStorageKey('home-scroll'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
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
                          icon: const Icon(Icons.search_rounded, size: 22),
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
                    delay: const Duration(milliseconds: 70),
                    child: _hero(),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _sourcePill(
                        Icons.play_circle_fill_rounded,
                        'YouTube · in-app',
                        const Color(0xFFFF7878),
                      ),
                      _sourcePill(
                        Icons.offline_pin_outlined,
                        'Your files. Always yours.',
                        AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                sliver: SliverToBoxAdapter(
                  child: _heading(
                    'Pick a frequency.',
                    'A soundtrack for wherever your head is.',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      190 + (MediaQuery.textScalerOf(context).scale(140) - 140),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      _mood(
                        'After hours',
                        'Late night R&B',
                        '01',
                        const Color(0xFFBBAAFF),
                        const Color(0xFF30283E),
                      ),
                      _mood(
                        'Tunnel vision',
                        'Focus instrumental music',
                        '02',
                        const Color(0xFFBCD8C6),
                        const Color(0xFF223B35),
                      ),
                      _mood(
                        'Full volume',
                        'Alternative rock music',
                        '03',
                        const Color(0xFFF5AD8F),
                        const Color(0xFF442D29),
                      ),
                      _mood(
                        'Soft landing',
                        'Acoustic chill music',
                        '04',
                        const Color(0xFFE8D99D),
                        const Color(0xFF3C3729),
                      ),
                    ],
                  ),
                ),
              ),
              if (_configured) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: _heading(
                            'In the spotlight',
                            'Find a track. Make it your soundtrack.',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh tracks',
                          onPressed: _loading
                              ? null
                              : () => _load(refresh: true),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
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
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _load(refresh: true),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!_loading && _error == null && _videos.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'No tracks available right now.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                if (_videos.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height:
                          118 +
                          (MediaQuery.textScalerOf(context).scale(74) - 74),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        scrollDirection: Axis.horizontal,
                        itemCount: _videos.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(width: 16),
                        itemBuilder: (_, index) => SizedBox(
                          width: 324,
                          child: YoutubeCard(
                            video: _videos[index],
                            onTap: () => _playResult(_videos[index]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
                sliver: SliverToBoxAdapter(child: _bridgeCard()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                sliver: SliverToBoxAdapter(
                  child: ListenableBuilder(
                    listenable: widget.audioService,
                    builder: (context, _) {
                      final local = widget.audioService.localSongs;
                      return Pressable(
                        onTap: widget.onLocalTap,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSurface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              AlbumArt(
                                gradientId: 1,
                                size: 56,
                                borderRadius: 12,
                                showShadow: false,
                                overlayIcon: Icons.library_music_outlined,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'The offline collection',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      local.isEmpty
                                          ? 'Your music, without the Wi-Fi.'
                                          : '${local.length} tracks, ready when you are.',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFFD8CDFA),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Stack(
      children: [
        const Positioned(
          right: -44,
          top: -20,
          bottom: -20,
          width: 255,
          child: IgnorePointer(child: CustomPaint(painter: _RecordPainter())),
        ),
        Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LESS SCROLL. MORE SOUL.',
                style: TextStyle(
                  color: Color(0xFF4C3E66),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'Meet your\nnext obsession.',
                style: TextStyle(
                  color: Color(0xFF201B2A),
                  fontSize: 38,
                  height: 1.03,
                  letterSpacing: -1.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Deep cuts. Big feelings.\nA whole world of music.',
                style: TextStyle(
                  color: Color(0xFF51465E),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 25),
              FilledButton.icon(
                onPressed: () => widget.onSearchTap?.call(''),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF201B2A),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Find your next song'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sourcePill(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white10),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    ],
  );

  Widget _mood(
    String title,
    String query,
    String number,
    Color ink,
    Color background,
  ) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: SizedBox(
      width: 174 + (MediaQuery.textScalerOf(context).scale(174) - 174),
      child: Pressable(
        onTap: () => widget.onSearchTap?.call(query),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    number,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  Icon(Icons.arrow_outward_rounded, color: ink, size: 18),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  color: ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Find your mix',
                style: TextStyle(
                  color: ink.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _bridgeCard() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.link_rounded, color: Color(0xFFFF9990), size: 23),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Already have a favorite?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _configured
              ? 'Search for an artist, pick a track, and listen with Harmoniq’s own player.'
              : 'Paste a YouTube link to listen on Android. Online audio playback is unavailable in the browser preview.',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => widget.onSearchTap?.call(''),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('Find a song'),
        ),
      ],
    ),
  );
}

class _RecordPainter extends CustomPainter {
  const _RecordPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.8, size.height * 0.55);
    final paint = Paint()
      ..color = const Color(0x182D2047)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double r = 28; r < 220; r += 12) {
      canvas.drawCircle(center, r, paint);
    }
    canvas.drawCircle(center, 22, Paint()..color = const Color(0x202D2047));
  }

  @override
  bool shouldRepaint(covariant _RecordPainter oldDelegate) => false;
}
