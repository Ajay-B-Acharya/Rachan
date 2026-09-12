import 'package:flutter/material.dart';

import '../models/youtube_video.dart';
import '../theme/app_colors.dart';
import 'motion.dart';

class YoutubeCard extends StatelessWidget {
  final YoutubeVideo video;
  final VoidCallback onTap;
  const YoutubeCard({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundSurface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(
                      color: Color(0xFF30283E),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: AppColors.accent,
                        size: 28,
                      ),
                    ),
                    if (video.thumbnailUrl.isNotEmpty)
                      Image.network(
                        video.thumbnailUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 204,
                        errorBuilder: (_, error, stack) =>
                            const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    video.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'YOUTUBE · AUDIO',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.accent,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.play_circle_fill_rounded,
              color: AppColors.accent,
              size: 32,
            ),
          ],
        ),
      ),
    ),
  );
}
