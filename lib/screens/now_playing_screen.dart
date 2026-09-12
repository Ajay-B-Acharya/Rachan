import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../widgets/album_art.dart';

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
  static const _background = Color(0xFF101113);
  static const _surface = Color(0xFF1B1C20);
  static const _foreground = Color(0xFFF4F2EE);
  static const _muted = Color(0xFF9C9BA5);
  static const _primary = Color(0xFFBBAAFF);
  static const _border = Color(0xFF2D2E34);

  AudioService get _svc => widget.audioService;
  late final PageController _carouselController;
  bool _userCarouselDrag = false;
  bool _carouselSyncScheduled = false;

  // Progress ticks and pointer moves rebuild only the seek controls.
  final _dragPositionNotifier = ValueNotifier<_DragState>(const _DragState());
  late Song? _song;
  late bool _isPlaying;
  late bool _isLoading;
  late bool _wantsToPlay;
  late bool _canSeek;
  late String? _playbackError;
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
      viewportFraction: 0.9,
    );
    _svc.addListener(_onServiceChanged);
  }

  @override
  void didUpdateWidget(covariant NowPlayingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioService != widget.audioService) {
      oldWidget.audioService.removeListener(_onServiceChanged);
      _syncFromService();
      _dragPositionNotifier.value = const _DragState();
      _svc.addListener(_onServiceChanged);
      _scheduleCarouselSync();
    }
  }

  void _syncFromService() {
    _song = _svc.currentSong;
    _isPlaying = _svc.isPlaying;
    _isLoading = _svc.isLoading;
    _wantsToPlay = _svc.wantsToPlay;
    _canSeek = _svc.canSeek;
    _playbackError = _svc.playbackError;
    _queue = _svc.queue.isNotEmpty
        ? List<Song>.of(_svc.queue)
        : (_song != null ? [_song!] : <Song>[]);
    _queueIndex = _svc.currentQueueIndex;
    _shuffle = _svc.shuffleEnabled;
    _repeat = _svc.repeatEnabled;
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final previousIdentity = _song?.identity;
    final previousIndex = _queueIndex;
    final previousLength = _queue.length;
    setState(_syncFromService);
    if (previousIdentity != _song?.identity || !_canSeek) {
      _dragPositionNotifier.value = const _DragState();
    }
    if (previousIdentity != _song?.identity ||
        previousIndex != _queueIndex ||
        previousLength != _queue.length) {
      // A swipe already put the carousel on this page. Do not interrupt it.
      if (!_carouselController.hasClients ||
          _carouselController.page?.round() != _queueIndex) {
        _scheduleCarouselSync();
      }
    }
  }

  void _scheduleCarouselSync() {
    // External jumps must never play each intermediate page. Only a genuine
    // user drag can request playback; queued callbacks read the latest index.
    _userCarouselDrag = false;
    if (_carouselSyncScheduled) return;
    _carouselSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_carouselController.hasClients &&
          _queueIndex >= 0 &&
          _queueIndex < _queue.length) {
        _carouselController.jumpToPage(_queueIndex);
      }
      _carouselSyncScheduled = false;
    });
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceChanged);
    _carouselController.dispose();
    _dragPositionNotifier.dispose();
    super.dispose();
  }

  Duration _motionDuration(BuildContext context, int milliseconds) {
    final media = MediaQuery.of(context);
    return media.disableAnimations || media.accessibleNavigation
        ? Duration.zero
        : Duration(milliseconds: milliseconds);
  }

  String _fmt(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _nextTitle() {
    if (_queue.isEmpty || _queueIndex < 0) return 'No upcoming tracks';
    if (_shuffle) return 'Shuffle is on';
    final next = _queueIndex + 1;
    if (next >= _queue.length) {
      return _repeat ? _queue.first.title : 'End of queue';
    }
    return _queue[next].title;
  }

  Future<void> _stopAndClose() async {
    await _svc.stopAndClear();
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final song = _song;
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: song == null
            ? Center(
                child: TextButton.icon(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  label: const Text('No song playing · Close'),
                  style: TextButton.styleFrom(foregroundColor: _foreground),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final padding = constraints.maxWidth < 360 ? 16.0 : 24.0;
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: wide ? 1120 : 560,
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(padding, 8, padding, 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildHeader(song),
                              SizedBox(height: wide ? 24 : 20),
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: _buildArtwork(context),
                                    ),
                                    const SizedBox(width: 36),
                                    Expanded(
                                      flex: 5,
                                      child: _buildPlayback(context, song),
                                    ),
                                  ],
                                )
                              else ...[
                                _buildArtwork(context),
                                const SizedBox(height: 28),
                                _buildPlayback(context, song),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildHeader(Song song) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 300) widget.onClose();
      },
      child: Row(
        children: [
          IconButton(
            tooltip: 'Minimize player',
            onPressed: widget.onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            color: _foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _foreground, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Stop and close',
            onPressed: _stopAndClose,
            icon: const Icon(Icons.close_rounded, size: 21),
            color: _muted,
          ),
          IconButton(
            tooltip: 'Song options',
            onPressed: () => _showSongOptions(context, song),
            icon: const Icon(Icons.more_horiz_rounded),
            color: _foreground,
          ),
        ],
      ),
    );
  }

  Widget _buildArtwork(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final artSize = math.min(constraints.maxWidth * 0.86, 430.0);
        return SizedBox(
          height: artSize,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth != 0) return false;
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _userCarouselDrag = true;
              } else if (notification is ScrollEndNotification) {
                _userCarouselDrag = false;
              }
              return false;
            },
            child: PageView.builder(
              controller: _carouselController,
              physics: const PageScrollPhysics(),
              itemCount: _queue.length,
              onPageChanged: (index) {
                if (_userCarouselDrag &&
                    !_carouselSyncScheduled &&
                    index != _queueIndex) {
                  _svc.skipToIndex(index);
                }
              },
              itemBuilder: (context, index) {
                final item = _queue[index];
                final isCurrent = index == _queueIndex;
                return AnimatedScale(
                  scale: isCurrent ? 1 : 0.94,
                  duration: _motionDuration(context, 220),
                  curve: Curves.easeOutCubic,
                  child: Center(
                    child: RepaintBoundary(
                      child: HeroMode(
                        enabled: _motionDuration(context, 1) != Duration.zero,
                        child: Hero(
                          tag: isCurrent
                              ? 'album-art-${item.identity}'
                              : 'album-art-${item.identity}-np-$index',
                          child: AlbumArt(
                            gradientId: item.gradientId,
                            imageUrl: item.source == SongSource.online
                                ? item.albumArtUrl
                                : null,
                            size: artSize,
                            borderRadius: 16,
                            showShadow: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayback(BuildContext context, Song song) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _foreground,
                      fontSize: 28,
                      height: 1.15,
                      letterSpacing: -0.7,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: song.isFavorite ? 'Remove from favorites' : 'Favorite',
              onPressed: () => _svc.toggleFavorite(song),
              icon: Icon(
                song.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              color: song.isFavorite ? _primary : _muted,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          song.source == SongSource.online
              ? 'AUDIUS · STREAMING'
              : 'FROM YOUR LIBRARY',
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.4,
          ),
        ),
        if (_isLoading || _playbackError != null) ...[
          const SizedBox(height: 12),
          _buildPlaybackStatus(),
        ],
        const SizedBox(height: 20),
        _buildSeekBar(song.duration),
        const SizedBox(height: 20),
        _buildControls(context),
        const SizedBox(height: 28),
        _buildQueuePreview(),
      ],
    );
  }

  Widget _buildPlaybackStatus() {
    final error = _playbackError;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoading)
            Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _wantsToPlay ? 'Loading audio…' : 'Loading audio… · Paused',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          if (error != null) ...[
            Text(
              error,
              style: const TextStyle(color: _foreground, fontSize: 13),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _isLoading ? null : _svc.retryPlayback,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry playback'),
                  style: TextButton.styleFrom(foregroundColor: _primary),
                ),
                TextButton.icon(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Choose another track'),
                  style: TextButton.styleFrom(foregroundColor: _muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeekBar(Duration duration) {
    return ValueListenableBuilder<_DragState>(
      valueListenable: _dragPositionNotifier,
      builder: (context, drag, child) {
        final maxMs = math.max(duration.inMilliseconds.toDouble(), 1.0);
        return ValueListenableBuilder<Duration>(
          valueListenable: _svc.playbackPositionNotifier,
          builder: (context, position, child) {
            final currentMs =
                (drag.isDragging
                        ? drag.positionMs
                        : position.inMilliseconds.toDouble())
                    .clamp(0.0, maxMs);
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: _primary,
                    inactiveTrackColor: _border,
                    thumbColor: _foreground,
                    overlayColor: _primary.withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    value: currentMs,
                    max: maxMs,
                    semanticFormatterCallback: (value) =>
                        '${_fmt(Duration(milliseconds: value.toInt()))} of ${_fmt(duration)}',
                    onChangeStart: !_canSeek
                        ? null
                        : (value) {
                            _dragPositionNotifier.value = _DragState(
                              isDragging: true,
                              positionMs: value,
                            );
                          },
                    onChanged: !_canSeek
                        ? null
                        : (value) {
                            _dragPositionNotifier.value = _DragState(
                              isDragging: true,
                              positionMs: value,
                            );
                          },
                    onChangeEnd: !_canSeek
                        ? null
                        : (value) {
                            if (_svc.canSeek) {
                              _svc.seek(Duration(milliseconds: value.toInt()));
                            }
                            _dragPositionNotifier.value = const _DragState();
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(Duration(milliseconds: currentMs.toInt())),
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                      Text(
                        _fmt(duration),
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    final showPause = _isLoading ? _wantsToPlay : _isPlaying;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: _shuffle ? 'Turn shuffle off' : 'Turn shuffle on',
          isSelected: _shuffle,
          onPressed: _svc.toggleShuffle,
          icon: const Icon(Icons.shuffle_rounded, size: 21),
          color: _shuffle ? _primary : _muted,
        ),
        IconButton(
          tooltip: 'Previous track',
          onPressed: _svc.previous,
          icon: const Icon(Icons.skip_previous_rounded, size: 34),
          color: _foreground,
        ),
        SizedBox.square(
          dimension: 72,
          child: IconButton.filled(
            tooltip: showPause ? 'Pause' : 'Play',
            onPressed: _svc.togglePlay,
            style: IconButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: _background,
            ),
            icon: AnimatedSwitcher(
              duration: _motionDuration(context, 160),
              child: Icon(
                showPause ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(showPause),
                size: 34,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next track',
          onPressed: _svc.next,
          icon: const Icon(Icons.skip_next_rounded, size: 34),
          color: _foreground,
        ),
        IconButton(
          tooltip: _repeat ? 'Turn repeat off' : 'Turn repeat on',
          isSelected: _repeat,
          onPressed: _svc.toggleRepeat,
          icon: const Icon(Icons.repeat_rounded, size: 21),
          color: _repeat ? _primary : _muted,
        ),
      ],
    );
  }

  Widget _buildQueuePreview() {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _showQueueBottomSheet(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.queue_music_rounded, color: _primary, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'UP NEXT',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _nextTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _foreground, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  AnimationStyle _sheetMotion(BuildContext context) => AnimationStyle(
    duration: _motionDuration(context, 240),
    reverseDuration: _motionDuration(context, 180),
  );

  void _showQueueBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      sheetAnimationStyle: _sheetMotion(context),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListenableBuilder(
          listenable: _svc,
          builder: (context, child) => SafeArea(
            top: false,
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              itemCount: _queue.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Your queue',
                          style: TextStyle(
                            color: _foreground,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_queue.length} tracks',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }
                final queueIndex = index - 1;
                final song = _queue[queueIndex];
                final isCurrent = _queueIndex == queueIndex;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selected: isCurrent,
                  selectedTileColor: _primary.withValues(alpha: 0.08),
                  leading: AlbumArt(
                    gradientId: song.gradientId,
                    imageUrl: song.source == SongSource.online
                        ? song.albumArtUrl
                        : null,
                    size: 44,
                    borderRadius: 8,
                    showShadow: false,
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? _primary : _foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  trailing: isCurrent
                      ? Icon(
                          _isPlaying
                              ? Icons.volume_up_rounded
                              : Icons.pause_rounded,
                          color: _primary,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    _svc.playSong(song, contextQueue: _queue);
                    Navigator.pop(sheetContext);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      sheetAnimationStyle: _sheetMotion(context),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AlbumArt(
                    gradientId: song.gradientId,
                    imageUrl: song.source == SongSource.online
                        ? song.albumArtUrl
                        : null,
                    size: 52,
                    borderRadius: 8,
                    showShadow: false,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(color: _border, height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  song.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: song.isFavorite ? _primary : _muted,
                ),
                title: Text(
                  song.isFavorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  style: const TextStyle(color: _foreground, fontSize: 14),
                ),
                onTap: () {
                  _svc.toggleFavorite(song);
                  Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.playlist_add_rounded, color: _muted),
                title: const Text(
                  'Add to playlist',
                  style: TextStyle(color: _foreground, fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  // Use the screen context, not the dismissed sheet context.
                  _showAddToPlaylistSelector(context, song);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddToPlaylistSelector(BuildContext context, Song song) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      sheetAnimationStyle: _sheetMotion(context),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Add to playlist',
              style: TextStyle(
                color: _foreground,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (_svc.playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No playlists available',
                  style: TextStyle(color: _muted, fontSize: 14),
                ),
              )
            else
              for (final playlist in _svc.playlists)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AlbumArt(
                    gradientId: playlist.gradientId,
                    size: 40,
                    borderRadius: 8,
                    showShadow: false,
                  ),
                  title: Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _foreground, fontSize: 14),
                  ),
                  onTap: () {
                    _svc.addSongToPlaylist(song, playlist);
                    Navigator.pop(sheetContext);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text("Added to '${playlist.name}'"),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}

/// Immutable scrub state keeps drag events out of the screen's setState.
class _DragState {
  final bool isDragging;
  final double positionMs;

  const _DragState({this.isDragging = false, this.positionMs = 0.0});
}
