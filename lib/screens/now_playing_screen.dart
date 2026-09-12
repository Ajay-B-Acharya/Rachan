import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../theme/app_colors.dart';
import '../widgets/album_art.dart';
import '../widgets/glass_card.dart';

class NowPlayingScreen extends StatefulWidget {
  final AudioService audioService;
  final VoidCallback onClose;

  const NowPlayingScreen({
    super.key,
    required this.audioService,
    required this.onClose,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  AudioService get _svc => widget.audioService;

  late PageController _carouselController;

  // Drag state tracked in a ValueNotifier so only the slider builder rerenders
  // on each pointer-move event — not the entire NowPlayingScreen.
  final _dragPositionNotifier = ValueNotifier<_DragState>(const _DragState());

  // Local copies of the values we care about — updated by listener
  late Song? _song;
  late bool _isPlaying;
  late List<Song> _queue;
  late int _queueIndex;
  late bool _shuffle;
  late bool _repeat;

  @override
  void initState() {
    super.initState();
    _syncFromService();
    _carouselController = PageController(
      initialPage: _queueIndex >= 0 ? _queueIndex : 0,
      viewportFraction: 0.76,
    );
    _svc.addListener(_onServiceChanged);
  }

  void _syncFromService() {
    _song = _svc.currentSong;
    _isPlaying = _svc.isPlaying;
    _queue = _svc.queue.isNotEmpty ? _svc.queue : (_song != null ? [_song!] : []);
    _queueIndex = _svc.currentQueueIndex;
    _shuffle = _svc.shuffleEnabled;
    _repeat = _svc.repeatEnabled;
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final newSong = _svc.currentSong;
    final newIdx = _svc.currentQueueIndex;
    final newQueue = _svc.queue.isNotEmpty
        ? _svc.queue
        : (newSong != null ? [newSong] : <Song>[]);

    // Sync carousel when queue index changes externally (notification prev/next)
    if (newIdx != _queueIndex &&
        newIdx >= 0 &&
        newIdx < newQueue.length &&
        _carouselController.hasClients &&
        _carouselController.page?.round() != newIdx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _carouselController.hasClients &&
            _carouselController.page?.round() != newIdx) {
          _carouselController.animateToPage(
            newIdx,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }

    setState(() {
      _song = newSong;
      _isPlaying = _svc.isPlaying;
      _queue = newQueue;
      _queueIndex = newIdx;
      _shuffle = _svc.shuffleEnabled;
      _repeat = _svc.repeatEnabled;
    });
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceChanged);
    _carouselController.dispose();
    _dragPositionNotifier.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _nextTitle() {
    if (_queue.isEmpty || _queueIndex == -1) return 'None';
    if (_shuffle) return 'Random Track';
    final next = _queueIndex + 1;
    if (next >= _queue.length) return _repeat ? _queue[0].title : 'End of Queue';
    return _queue[next].title;
  }

  @override
  Widget build(BuildContext context) {
    final song = _song;
    if (song == null) {
      return const Scaffold(body: Center(child: Text('No song playing')));
    }

    final colors = AppColors.getGradientForId(song.gradientId);
    final duration = song.duration;
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) widget.onClose();
        },
        child: Stack(
          children: [
            // ── Atmospheric gradient — RepaintBoundary isolates it completely.
            //    Only repaints when the song (and thus color) changes, which is
            //    a rare discrete event, not a per-frame event.
            Positioned.fill(
              child: RepaintBoundary(
                child: Container(
                  key: ValueKey(song.gradientId),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.4),
                      radius: 1.25,
                      colors: [
                        colors[0].withValues(alpha: 0.55),
                        colors[1].withValues(alpha: 0.25),
                        AppColors.background,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Vignette overlay — static, painted once
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.28),
                        Colors.black.withValues(alpha: 0.62),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Main content — uses local setState, NOT AudioService listeners
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ── Top bar ──────────────────────────────────────────────
                    Column(
                      children: [
                        const SizedBox(height: 6),
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  onPressed: widget.onClose,
                                  splashRadius: 24,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  onPressed: () async {
                                    await _svc.stopAndClear();
                                    widget.onClose();
                                  },
                                  splashRadius: 24,
                                  tooltip: 'Close song',
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Text(
                                  'PLAYING FROM QUEUE',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5,
                                        fontSize: 9.5,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (song.isOnline) ...[
                                      Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: AppColors.accentLight
                                                .withValues(alpha: 0.4),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: const Text(
                                          'JAMENDO',
                                          style: TextStyle(
                                            color: AppColors.accentLight,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                    Text(
                                      song.album,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: () => _showSongOptions(context, song),
                              splashRadius: 24,
                            ),
                          ],
                        ),
                      ],
                    ),

                    // ── Album art carousel ───────────────────────────────────
                    SizedBox(
                      height: screenW * 0.78,
                      child: PageView.builder(
                        controller: _carouselController,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _queue.length,
                        onPageChanged: (index) {
                          if (index != _queueIndex) {
                            _svc.skipToIndex(index);
                          }
                        },
                        itemBuilder: (context, index) {
                          final itemSong = _queue[index];
                          final isCurrent = index == _queueIndex;
                          return AnimatedScale(
                            duration: const Duration(milliseconds: 250),
                            scale: isCurrent ? 1.0 : 0.85,
                            curve: Curves.easeOutCubic,
                            child: Center(
                              child: Hero(
                                tag: isCurrent
                                    ? 'album-art-${itemSong.id}'
                                    : 'album-art-${itemSong.id}-np-$index',
                                child: AlbumArt(
                                  gradientId: itemSong.gradientId,
                                  size: screenW * 0.70,
                                  borderRadius: 22,
                                  showShadow: isCurrent,
                                  imageUrl: itemSong.albumArtUrl,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // ── Track info + seek + controls ─────────────────────────
                    Column(
                      children: [
                        // Song title + favourite
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 22,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                          fontSize: 15,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                song.isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: song.isFavorite
                                    ? AppColors.heartColor
                                    : Colors.white60,
                                size: 26,
                              ),
                              onPressed: () => _svc.toggleFavorite(song),
                              splashRadius: 26,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ── Seek bar — position updates go through
                        //    two nested ValueListenableBuilders:
                        //    outer = position ticks (60fps via ValueNotifier)
                        //    inner = drag state (only fires on user interaction)
                        //    → ZERO setState() calls during scrubbing ─
                        ValueListenableBuilder<_DragState>(
                          valueListenable: _dragPositionNotifier,
                          builder: (context, drag, child) {
                            final maxMs = duration.inMilliseconds > 0
                                ? duration.inMilliseconds.toDouble()
                                : 1.0;

                            return ValueListenableBuilder<Duration>(
                              valueListenable: _svc.playbackPositionNotifier,
                              builder: (context, currentPos, _) {
                                final currentMs = drag.isDragging
                                    ? drag.positionMs
                                    : currentPos.inMilliseconds.toDouble();

                                return Column(
                                  children: [
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 3.5,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                          overlayRadius: 14,
                                        ),
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor:
                                            Colors.white.withValues(alpha: 0.15),
                                        thumbColor: Colors.white,
                                      ),
                                      child: Slider(
                                        value: currentMs.clamp(0.0, maxMs),
                                        min: 0.0,
                                        max: maxMs,
                                        onChangeStart: (val) {
                                          _dragPositionNotifier.value =
                                              _DragState(isDragging: true, positionMs: val);
                                        },
                                        onChanged: (val) {
                                          _dragPositionNotifier.value =
                                              _DragState(isDragging: true, positionMs: val);
                                        },
                                        onChangeEnd: (val) {
                                          _dragPositionNotifier.value =
                                              const _DragState();
                                          _svc.seek(
                                            Duration(milliseconds: val.toInt()),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _fmt(Duration(
                                              milliseconds: currentMs.toInt(),
                                            )),
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            _fmt(duration),
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 10),

                        // ── Playback controls ────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.shuffle_rounded,
                                color: _shuffle
                                    ? AppColors.accent
                                    : Colors.white60,
                                size: 22,
                              ),
                              onPressed: _svc.toggleShuffle,
                              splashRadius: 22,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                              onPressed: _svc.previous,
                              splashRadius: 26,
                            ),
                            // Play / Pause button — animated icon swap
                            GestureDetector(
                              onTap: _svc.togglePlay,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      Colors.white.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.25),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    if (_isPlaying)
                                      BoxShadow(
                                        color: AppColors.accent
                                            .withValues(alpha: 0.35),
                                        blurRadius: 18,
                                        spreadRadius: 2,
                                      ),
                                  ],
                                ),
                                child: AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(
                                    scale: anim,
                                    child: child,
                                  ),
                                  child: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    key: ValueKey(_isPlaying),
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                              onPressed: _svc.next,
                              splashRadius: 26,
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.repeat_rounded,
                                color: _repeat
                                    ? AppColors.accent
                                    : Colors.white60,
                                size: 22,
                              ),
                              onPressed: _svc.toggleRepeat,
                              splashRadius: 22,
                            ),
                          ],
                        ),
                      ],
                    ),

                    // ── Up Next banner ───────────────────────────────────────
                    GestureDetector(
                      onTap: () => _showQueueBottomSheet(context),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.queue_music_rounded,
                              color: AppColors.textSecondary,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Up Next: ${_nextTitle()}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: AppColors.textSecondary,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Queue bottom sheet ───────────────────────────────────────────────────────
  void _showQueueBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (context, scrollController) => GlassCard(
          borderRadius: 24,
          blurSigma: 20,
          color: Colors.black.withValues(alpha: 0.78),
          borderColor: Colors.white.withValues(alpha: 0.12),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Playback Queue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_queue.length} songs',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _queue.length,
                  itemBuilder: (context, index) {
                    final s = _queue[index];
                    final isCurrent = _queueIndex == index;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AlbumArt(
                        gradientId: s.gradientId,
                        size: 40,
                        borderRadius: 6,
                        showShadow: false,
                        imageUrl: s.albumArtUrl,
                      ),
                      title: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? AppColors.accent : Colors.white,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        s.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Icon(
                              Icons.volume_up_rounded,
                              color: AppColors.accent,
                              size: 18,
                            )
                          : null,
                      onTap: () {
                        _svc.playSong(s, contextQueue: _queue);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Song options sheet ───────────────────────────────────────────────────────
  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassCard(
        borderRadius: 20,
        blurSigma: 15,
        color: Colors.black.withValues(alpha: 0.68),
        borderColor: Colors.white.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AlbumArt(
                  gradientId: song.gradientId,
                  size: 48,
                  borderRadius: 8,
                  showShadow: false,
                  imageUrl: song.albumArtUrl,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${song.artist} • ${song.source == SongSource.jamendo ? 'Jamendo' : 'Local'}",
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 20),
            ListTile(
              leading: Icon(
                song.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: song.isFavorite ? AppColors.heartColor : Colors.white70,
              ),
              title: Text(
                song.isFavorite
                    ? 'Remove from Favorites'
                    : 'Add to Favorites',
                style:
                    const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
              onTap: () {
                _svc.toggleFavorite(song);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.playlist_add_rounded,
                color: Colors.white70,
              ),
              title: const Text(
                'Add to Playlist',
                style: TextStyle(color: Colors.white, fontSize: 13.5),
              ),
              onTap: () {
                Navigator.pop(context);
                _showAddToPlaylistSelector(context, song);
              },
            ),
            if (song.isOnline) ...[
              ListTile(
                leading: const Icon(
                  Icons.public_rounded,
                  color: AppColors.accentLight,
                ),
                title: const Text(
                  'Source: Jamendo Music',
                  style: TextStyle(color: Colors.white, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Free streaming via official Jamendo API v3',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
              if (song.licenseUrl != null)
                ListTile(
                  leading: const Icon(
                    Icons.copyright_rounded,
                    color: Colors.greenAccent,
                  ),
                  title: const Text(
                    'License Information',
                    style: TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    song.licenseUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylistSelector(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassCard(
        borderRadius: 20,
        blurSigma: 15,
        color: Colors.black.withValues(alpha: 0.68),
        borderColor: Colors.white.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add to Playlist',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_svc.playlists.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No playlists available',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _svc.playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _svc.playlists[index];
                    return ListTile(
                      leading: AlbumArt(
                        gradientId: playlist.gradientId,
                        size: 36,
                        borderRadius: 6,
                        showShadow: false,
                      ),
                      title: Text(
                        playlist.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                        ),
                      ),
                      onTap: () {
                        _svc.addSongToPlaylist(song, playlist);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Added to '${playlist.name}'"),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Immutable value object for slider drag state.
/// Using a ValueNotifier<_DragState> instead of setState avoids
/// rebuilding the entire NowPlayingScreen on each pointer-move event.
class _DragState {
  final bool isDragging;
  final double positionMs;

  const _DragState({this.isDragging = false, this.positionMs = 0.0});
}
