import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../theme/app_colors.dart';
import '../widgets/album_art.dart';
import '../widgets/glass_card.dart';

class NowPlayingScreen extends StatelessWidget {
  final AudioService audioService;
  final VoidCallback onClose;

  const NowPlayingScreen({
    super.key,
    required this.audioService,
    required this.onClose,
  });

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return "$minutes:${twoDigits(seconds)}";
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: audioService,
      builder: (context, _) {
        final song = audioService.currentSong;
        if (song == null) {
          return const Scaffold(body: Center(child: Text("No song playing")));
        }

        final isPlaying = audioService.isPlaying;
        final position = audioService.playbackPosition;
        final duration = song.duration;

        double progress = 0.0;
        if (duration.inMilliseconds > 0) {
          progress = position.inMilliseconds / duration.inMilliseconds;
          progress = progress.clamp(0.0, 1.0);
        }

        final colors = AppColors.getGradientForId(song.gradientId);

        return Scaffold(
          body: Stack(
            children: [
              // Immersive Blur Background
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                  child: Container(color: Colors.black.withOpacity(0.58)),
                ),
              ),

              // Content Layout
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Action Bar
                      Column(
                        children: [
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                onPressed: onClose,
                                splashRadius: 24,
                              ),
                              Column(
                                children: [
                                  Text(
                                    "NOW PLAYING",
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.5,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
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
                              IconButton(
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: () =>
                                    _showSongOptions(context, song),
                                splashRadius: 24,
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Scale Animated Album Art Container
                      AnimatedScale(
                        scale: isPlaying ? 1.0 : 0.92,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        child: Hero(
                          tag: 'album-art-${song.id}',
                          child: AlbumArt(
                            gradientId: song.gradientId,
                            size: MediaQuery.of(context).size.width * 0.72,
                            borderRadius: 20,
                            showShadow: true,
                          ),
                        ),
                      ),

                      // Track Metadata and Favorite Actions
                      Column(
                        children: [
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
                                onPressed: () =>
                                    audioService.toggleFavorite(song),
                                splashRadius: 26,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Progress Seek Slider and Times
                          Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3.5,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14,
                                  ),
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white.withOpacity(
                                    0.15,
                                  ),
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  value: position.inMilliseconds
                                      .toDouble()
                                      .clamp(
                                        0.0,
                                        duration.inMilliseconds > 0
                                            ? duration.inMilliseconds.toDouble()
                                            : 1.0,
                                      ),
                                  min: 0.0,
                                  max: duration.inMilliseconds > 0
                                      ? duration.inMilliseconds.toDouble()
                                      : 1.0,
                                  onChanged: (val) {
                                    audioService.seek(
                                      Duration(milliseconds: val.toInt()),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Audio Playback Controls
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  color: audioService.shuffleEnabled
                                      ? AppColors.accent
                                      : Colors.white60,
                                  size: 22,
                                ),
                                onPressed: audioService.toggleShuffle,
                                splashRadius: 22,
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                                onPressed: () => audioService.previous(),
                                splashRadius: 26,
                              ),
                              // Large Central Play/Pause
                              GestureDetector(
                                onTap: () => audioService.togglePlay(),
                                child: GlassCard(
                                  borderRadius: 36,
                                  blurSigma: 8,
                                  padding: const EdgeInsets.all(14),
                                  color: Colors.white.withOpacity(0.12),
                                  borderColor: Colors.white.withOpacity(0.20),
                                  child: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                                onPressed: () => audioService.next(),
                                splashRadius: 26,
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.repeat_rounded,
                                  color: audioService.repeatEnabled
                                      ? AppColors.accent
                                      : Colors.white60,
                                  size: 22,
                                ),
                                onPressed: audioService.toggleRepeat,
                                splashRadius: 22,
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Bottom Drawer Handle / Next Song Banner
                      Column(
                        children: [
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
                                    "Up Next: ${_getNextSongTitle()}",
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getNextSongTitle() {
    final queue = audioService.queue;
    final index = audioService.currentQueueIndex;
    if (queue.isEmpty || index == -1) return "None";

    int nextIndex = index + 1;
    if (audioService.shuffleEnabled) {
      return "Random Track";
    }

    if (nextIndex >= queue.length) {
      return audioService.repeatEnabled ? queue[0].title : "End of Queue";
    }

    return queue[nextIndex].title;
  }

  void _showQueueBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          builder: (context, scrollController) {
            return GlassCard(
              borderRadius: 24,
              blurSigma: 20,
              color: Colors.black.withOpacity(0.78),
              borderColor: Colors.white.withOpacity(0.12),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Playback Queue",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "${audioService.queue.length} songs",
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
                      itemCount: audioService.queue.length,
                      itemBuilder: (context, index) {
                        final song = audioService.queue[index];
                        final isCurrent =
                            audioService.currentQueueIndex == index;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: AlbumArt(
                            gradientId: song.gradientId,
                            size: 40,
                            borderRadius: 6,
                            showShadow: false,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? AppColors.accent
                                  : Colors.white,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            song.artist,
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
                            audioService.playSong(
                              song,
                              contextQueue: audioService.queue,
                            );
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSongOptions(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GlassCard(
          borderRadius: 20,
          blurSigma: 15,
          color: Colors.black.withOpacity(0.68),
          borderColor: Colors.white.withOpacity(0.12),
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
                          song.artist,
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
                  color: song.isFavorite
                      ? AppColors.heartColor
                      : Colors.white70,
                ),
                title: Text(
                  song.isFavorite
                      ? "Remove from Favorites"
                      : "Add to Favorites",
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                ),
                onTap: () {
                  audioService.toggleFavorite(song);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.playlist_add_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  "Add to Playlist",
                  style: TextStyle(color: Colors.white, fontSize: 13.5),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAddToPlaylistSelector(context, song);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddToPlaylistSelector(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GlassCard(
          borderRadius: 20,
          blurSigma: 15,
          color: Colors.black.withOpacity(0.68),
          borderColor: Colors.white.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Add to Playlist",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (audioService.playlists.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      "No playlists available",
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
                    itemCount: audioService.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = audioService.playlists[index];
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
                          audioService.addSongToPlaylist(song, playlist);
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
        );
      },
    );
  }
}
