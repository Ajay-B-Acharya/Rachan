import 'package:flutter/material.dart';

import '../models/song.dart';
import '../models/playlist.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';
import '../widgets/album_art.dart';

class LibraryScreen extends StatefulWidget {
  final List<Song> songs;
  final List<Playlist> playlists;
  final Song? currentSong;
  final Function(Song) onSongTap;
  final Function(Song) onFavoriteTap;
  final Function(String) onCreatePlaylist;

  const LibraryScreen({
    super.key,
    required this.songs,
    required this.playlists,
    required this.currentSong,
    required this.onSongTap,
    required this.onFavoriteTap,
    required this.onCreatePlaylist,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedCategoryIndex = 0;
  final List<String> _categories = [
    "Songs",
    "Playlists",
    "Albums",
    "Favorites",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E0C1C), AppColors.background],
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
                // Title and Add Playlist Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Your Library",
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                    ),
                    if (_selectedCategoryIndex == 1) // Playlists tab
                      IconButton(
                        icon: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: _showCreatePlaylistDialog,
                        splashRadius: 24,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                // Categories Row Selector
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = _selectedCategoryIndex == index;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCategoryIndex = index;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accent
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : Colors.white.withOpacity(0.08),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // Category Contents
                Expanded(child: _buildCategoryContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryContent() {
    switch (_selectedCategoryIndex) {
      case 0:
        return _buildSongsList();
      case 1:
        return _buildPlaylistsView();
      case 2:
        return _buildAlbumsView();
      case 3:
        return _buildFavoritesList();
      default:
        return Container();
    }
  }

  Widget _buildSongsList() {
    if (widget.songs.isEmpty) {
      return _buildEmptyState(
        Icons.music_note_rounded,
        "Your library is empty",
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: widget.songs.length + 1,
      itemBuilder: (context, index) {
        if (index == widget.songs.length) {
          return const SizedBox(height: 130);
        }
        final song = widget.songs[index];
        final isActive = widget.currentSong?.id == song.id;
        return SongTile(
          song: song,
          isActive: isActive,
          onTap: () => widget.onSongTap(song),
          onFavoriteTap: () => widget.onFavoriteTap(song),
        );
      },
    );
  }

  Widget _buildPlaylistsView() {
    if (widget.playlists.isEmpty) {
      return _buildEmptyState(
        Icons.playlist_add_rounded,
        "No playlists created yet",
      );
    }

    // Fixed child ratio grid layout
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: widget.playlists.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final playlist = widget.playlists[index];
        return GestureDetector(
          onTap: () {
            if (playlist.songs.isNotEmpty) {
              widget.onSongTap(playlist.songs[0]);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "This playlist is empty! Add songs from the catalog.",
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AlbumArt(
                  gradientId: playlist.gradientId,
                  size: double.infinity,
                  borderRadius: 12,
                  overlayIcon: Icons.playlist_play_rounded,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "${playlist.songs.length} songs",
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumsView() {
    // Dynamic grouping of albums
    final albums = <String, List<Song>>{};
    for (var song in widget.songs) {
      if (!albums.containsKey(song.album)) {
        albums[song.album] = [];
      }
      albums[song.album]!.add(song);
    }

    if (albums.isEmpty) {
      return _buildEmptyState(Icons.album_rounded, "No albums found");
    }

    final albumKeys = albums.keys.toList();

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: albumKeys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final albumName = albumKeys[index];
        final albumSongs = albums[albumName]!;
        final gradId = albumSongs[0].gradientId;

        return GestureDetector(
          onTap: () {
            widget.onSongTap(albumSongs[0]);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AlbumArt(
                  gradientId: gradId,
                  size: double.infinity,
                  borderRadius: 12,
                  overlayIcon: Icons.album_rounded,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                albumName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                albumSongs[0].artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFavoritesList() {
    final favorites = widget.songs.where((song) => song.isFavorite).toList();

    if (favorites.isEmpty) {
      return _buildEmptyState(
        Icons.favorite_outline_rounded,
        "No favorites yet",
        subtitle: "Tap the heart on any song to add it here",
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: favorites.length + 1,
      itemBuilder: (context, index) {
        if (index == favorites.length) {
          return const SizedBox(height: 130);
        }
        final song = favorites[index];
        final isActive = widget.currentSong?.id == song.id;
        return SongTile(
          song: song,
          isActive: isActive,
          onTap: () => widget.onSongTap(song),
          onFavoriteTap: () => widget.onFavoriteTap(song),
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String message, {String? subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: AppColors.textMuted.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: AppColors.textSecondary, fontSize: 14.5),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "New Playlist",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: textController,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Playlist name",
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final name = textController.text.trim();
                if (name.isNotEmpty) {
                  widget.onCreatePlaylist(name);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: const Text("Create", style: TextStyle(fontSize: 13)),
            ),
          ],
        );
      },
    );
  }
}
