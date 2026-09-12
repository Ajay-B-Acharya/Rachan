import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_colors.dart';
import 'album_art.dart';
import 'glass_card.dart';

class SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const SongCard({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 135,
          margin: const EdgeInsets.only(right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stack with Artwork, Online indicator and Floating Glass Play Button
              Stack(
                children: [
                  AlbumArt(
                    gradientId: song.gradientId,
                    size: 135,
                    borderRadius: 14,
                    imageUrl: song.albumArtUrl,
                  ),
                  // Online Jamendo badge indicator
                  if (song.isOnline)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.public_rounded,
                              color: AppColors.accentLight,
                              size: 10,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'JAMENDO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: GlassCard(
                      borderRadius: 18,
                      blurSigma: 0, // no BackdropFilter in scrolling list
                      padding: const EdgeInsets.all(5),
                      color: Colors.black.withValues(alpha: 0.45),
                      borderColor: Colors.white.withValues(alpha: 0.20),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Song Title
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
              ),
              const SizedBox(height: 2),
              // Artist Name
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
