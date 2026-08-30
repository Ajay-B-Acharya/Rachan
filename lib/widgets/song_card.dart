import 'package:flutter/material.dart';

import '../models/song.dart';
import 'album_art.dart';
import 'glass_card.dart';

class SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const SongCard({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 135,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stack with Artwork and Floating Glass Play Button
            Stack(
              children: [
                AlbumArt(
                  gradientId: song.gradientId,
                  size: 135,
                  borderRadius: 14,
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GlassCard(
                    borderRadius: 18,
                    blurSigma: 6,
                    padding: const EdgeInsets.all(5),
                    color: Colors.black.withOpacity(0.35),
                    borderColor: Colors.white.withOpacity(0.15),
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
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            // Artist Name
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
