import 'package:flutter/material.dart';

import '../models/song.dart';
import '../models/playlist.dart';
import '../theme/app_colors.dart';
import '../widgets/song_card.dart';
import '../widgets/album_art.dart';
import '../widgets/glass_card.dart';

class HomeScreen extends StatelessWidget {
  final List<Song> songs;
  final List<Playlist> playlists;
  final Song? currentSong;
  final Function(Song) onSongTap;
  final Function(Playlist) onPlaylistPlayTap;

  const HomeScreen({
    super.key,
    required this.songs,
    required this.playlists,
    required this.currentSong,
    required this.onSongTap,
    required this.onPlaylistPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting = "Good evening";
    if (hour < 12) {
      greeting = "Good morning";
    } else if (hour < 17) {
      greeting = "Good afternoon";
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF140F26), AppColors.background],
            stops: [0.0, 0.45],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Discover your next favorite song",
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                        ),
                      ],
                    ),
                    // Profile Button (with visual glow)
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Profile settings coming soon!"),
                            duration: Duration(milliseconds: 1200),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: AppColors.getGradientForId(3),
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 19,
                          backgroundColor: AppColors.backgroundSurface,
                          child: const Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.accent,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Recently Played Section
                Text(
                  "Recently Played",
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 19),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 190,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return SongCard(song: song, onTap: () => onSongTap(song));
                    },
                  ),
                ),
                const SizedBox(height: 32),
                // Made For You Section
                Text(
                  "Made For You",
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 19),
                ),
                const SizedBox(height: 16),
                // Playlists Grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: playlists.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.15,
                  ),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return GestureDetector(
                      onTap: () => onPlaylistPlayTap(playlist),
                      child: GlassCard(
                        borderRadius: 14,
                        blurSigma: 10,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white.withOpacity(0.04),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                AlbumArt(
                                  gradientId: playlist.gradientId,
                                  size: 44,
                                  borderRadius: 8,
                                  showShadow: true,
                                  overlayIcon: Icons.playlist_play_rounded,
                                ),
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.08),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.12),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playlist.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${playlist.songs.length} songs",
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 130), // Padding to clear the mini-player
              ],
            ),
          ),
        ),
      ),
    );
  }
}
