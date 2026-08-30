import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_colors.dart';
import 'album_art.dart';
import 'glass_card.dart';

class MiniPlayer extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;
  final Future<void> Function() onPlayPauseTap;
  final Future<void> Function() onNextTap;
  final double playbackProgress; // 0.0 to 1.0

  const MiniPlayer({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onTap,
    required this.onPlayPauseTap,
    required this.onNextTap,
    required this.playbackProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          borderRadius: 14,
          blurSigma: 12,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          color: Colors.black.withOpacity(0.45),
          borderColor: Colors.white.withOpacity(0.12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Thumbnail
                  Hero(
                    tag: 'album-art-${song.id}',
                    child: AlbumArt(
                      gradientId: song.gradientId,
                      size: 42,
                      borderRadius: 8,
                      showShadow: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title / Artist Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
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
                  // Play/Pause Action
                  IconButton(
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: onPlayPauseTap,
                    splashRadius: 24,
                  ),
                  // Skip Next Action
                  IconButton(
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: onNextTap,
                    splashRadius: 24,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Slim progress bar indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: playbackProgress.isNaN ? 0.0 : playbackProgress,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.accent,
                    ),
                    minHeight: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
