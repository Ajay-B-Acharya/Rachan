import 'dart:math';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_colors.dart';
import 'album_art.dart';
import 'glass_card.dart';
import 'motion.dart';

class MiniPlayer extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final bool isLoading;
  final String? playbackError;
  final VoidCallback? onRetryTap;
  final bool? wantsToPlay;
  final VoidCallback onTap;
  final Future<void> Function() onPlayPauseTap;
  final Future<void> Function() onNextTap;
  final Future<void> Function()? onPreviousTap;
  final Future<void> Function()? onCloseTap;
  final ValueNotifier<Duration> positionNotifier;

  const MiniPlayer({
    super.key,
    required this.song,
    required this.isPlaying,
    this.isLoading = false,
    this.playbackError,
    this.onRetryTap,
    this.wantsToPlay,
    required this.onTap,
    required this.onPlayPauseTap,
    required this.onNextTap,
    this.onPreviousTap,
    this.onCloseTap,
    required this.positionNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final showPause = isLoading ? (wantsToPlay ?? isPlaying) : isPlaying;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: onTap,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -250) {
              onNextTap();
            } else if (velocity > 250 && onPreviousTap != null) {
              onPreviousTap!();
            }
          },
          child: GlassCard(
            borderRadius: 18,
            blurSigma: 0, // no BackdropFilter — sits over scrolling content
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            color: const Color(0xFF25232C),
            borderColor: isPlaying
                ? AppColors.accent.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Thumbnail with Hero animation
                    Hero(
                      tag: 'album-art-${song.identity}',
                      child: AlbumArt(
                        gradientId: song.gradientId,
                        imageUrl: song.source == SongSource.online
                            ? song.albumArtUrl
                            : null,
                        size: 44,
                        borderRadius: 10,
                        showShadow: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title / Artist Info + Live Equalizer
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                ),
                              ),
                              if (isPlaying &&
                                  !isLoading &&
                                  playbackError == null) ...[
                                const SizedBox(width: 8),
                                const MiniEqualizerBars(isPlaying: true),
                                const SizedBox(width: 4),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    // Play/Pause Action with micro-scale feedback
                    IconButton(
                      tooltip: showPause ? 'Pause' : 'Play',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.accent,
                      ),
                      icon: AnimatedSwitcher(
                        duration: motionDuration(context, 180),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          showPause
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey(showPause),
                          color: AppColors.background,
                          size: 28,
                        ),
                      ),
                      onPressed: onPlayPauseTap,
                      splashRadius: 24,
                    ),
                    // Skip Next Action
                    IconButton(
                      tooltip: 'Next track',
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: onNextTap,
                      splashRadius: 24,
                    ),
                    // Close / stop current song
                    if (onCloseTap != null)
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        onPressed: onCloseTap,
                        splashRadius: 20,
                        tooltip: 'Close song',
                      ),
                  ],
                ),
                if (isLoading || playbackError != null)
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            playbackError ??
                                (showPause
                                    ? 'Loading audio…'
                                    : 'Loading audio… · Paused'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        if (playbackError != null)
                          IconButton(
                            tooltip: onRetryTap != null
                                ? 'Retry playback'
                                : 'Open playback details',
                            onPressed: isLoading ? null : (onRetryTap ?? onTap),
                            icon: Icon(
                              onRetryTap != null
                                  ? Icons.refresh_rounded
                                  : Icons.error_outline_rounded,
                            ),
                            color: AppColors.accentLight,
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 7),
                // Isolated Progress Bar - listens only to positionNotifier (zero rebuilds for the parent)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: positionNotifier,
                      builder: (context, pos, _) {
                        final totalMs = song.duration.inMilliseconds;
                        final double progress = totalMs > 0
                            ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                            : 0.0;
                        return LinearProgressIndicator(
                          value: isLoading
                              ? null
                              : (progress.isNaN ? 0.0 : progress),
                          semanticsLabel: isLoading
                              ? 'Loading audio'
                              : 'Playback progress',
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.accent,
                          ),
                          minHeight: 2.5,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MiniEqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const MiniEqualizerBars({
    super.key,
    required this.isPlaying,
    this.color = AppColors.accentLight,
  });

  @override
  State<MiniEqualizerBars> createState() => _MiniEqualizerBarsState();
}

class _MiniEqualizerBarsState extends State<MiniEqualizerBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.isPlaying && !_reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(MiniEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
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
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            final t = (_controller.value + (i * 0.35)) % 1.0;
            final double height = widget.isPlaying && !_reduceMotion
                ? 4.0 + 8.0 * (0.3 + 0.7 * sin(t * pi).abs())
                : 4.0;
            return Container(
              width: 2.2,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}
