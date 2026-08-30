import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';
import '../widgets/glass_card.dart';

class LocalScreen extends StatelessWidget {
  final List<Song> localSongs;
  final bool isScanning;
  final Song? currentSong;
  final Function(Song) onSongTap;
  final Function(Song) onFavoriteTap;
  final Future<void> Function() onScanTap;

  const LocalScreen({
    super.key,
    required this.localSongs,
    required this.isScanning,
    required this.currentSong,
    required this.onSongTap,
    required this.onFavoriteTap,
    required this.onScanTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F1A1C), AppColors.background],
            stops: [0.0, 0.45],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Local Music",
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                    ),
                    if (!isScanning)
                      IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: onScanTap,
                        splashRadius: 24,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              strokeWidth: 3,
            ),
            const SizedBox(height: 20),
            Text(
              "Scanning device for audio files...",
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      );
    }

    if (localSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_android_rounded,
              size: 56,
              color: AppColors.textMuted.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              "No local songs loaded",
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: AppColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                "Rachan requires permissions to search and list local audio files saved on your mobile storage.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onScanTap,
              child: GlassCard(
                borderRadius: 12,
                blurSigma: 6,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                color: AppColors.accent.withOpacity(0.12),
                borderColor: AppColors.accent.withOpacity(0.25),
                child: const Text(
                  "Scan Storage / Grant Access",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: localSongs.length + 1,
      itemBuilder: (context, index) {
        if (index == localSongs.length) {
          return const SizedBox(height: 130);
        }
        final song = localSongs[index];
        final isActive = currentSong?.id == song.id;
        return SongTile(
          song: song,
          isActive: isActive,
          onTap: () => onSongTap(song),
          onFavoriteTap: () => onFavoriteTap(song),
        );
      },
    );
  }
}
