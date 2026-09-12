import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';
import '../widgets/album_art.dart';

class LibraryScreen extends StatefulWidget {
  final AudioService audioService;
  final Function(Song) onSongTap;
  final Function(Song) onFavoriteTap;
  final Function(String) onCreatePlaylist;

  const LibraryScreen({
    super.key,
    required this.audioService,
    required this.onSongTap,
    required this.onFavoriteTap,
    required this.onCreatePlaylist,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedCategoryIndex = 0;
  int _favoriteFilterIndex =
      0; // 0 = All, 1 = Local, 2 = Previous source, 3 = Online
  final List<String> _categories = [
    'Songs',
    'Playlists',
    'Albums',
    'Favorites',
  ];

  AudioService? _cachedService;
  int _cachedCatalogRevision = -1;
  int _cachedLocalRevision = -1;
  List<Song> _librarySongs = [];
  Map<String, List<Song>> _albumMap = {};
  List<String> _albumKeys = [];

  void _refreshLibraryCache() {
    final service = widget.audioService;
    if (identical(service, _cachedService) &&
        service.catalogRevision == _cachedCatalogRevision &&
        service.localSongsRevision == _cachedLocalRevision) {
      return;
    }
    _cachedService = service;
    _cachedCatalogRevision = service.catalogRevision;
    _cachedLocalRevision = service.localSongsRevision;

    // Local metadata takes precedence, matching the existing library order.
    final localIdentities = service.localSongs
        .map((song) => song.identity)
        .toSet();
    _librarySongs = [
      ...service.localSongs,
      ...service.songs.where(
        (song) => !localIdentities.contains(song.identity),
      ),
    ];
    _albumMap = {};
    for (final song in _librarySongs) {
      _albumMap.putIfAbsent(song.album, () => []).add(song);
    }
    _albumKeys = _albumMap.keys.toList();
  }

  @override
  Widget build(BuildContext context) {
    // The scaffold chrome (title, category chips) is pure local state.
    // Only the Expanded content list needs AudioService — listener is scoped there.
    return Scaffold(
      body: Material(
        color: AppColors.background,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),

                // ── Title + add button ────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Library',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                    ),
                    if (_selectedCategoryIndex == 1)
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

                // ── Category chips — local setState only ──────────────────────
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final isSelected = _selectedCategoryIndex == index;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedCategoryIndex = index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accent
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _categories[index],
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

                // ── Content — only this rebuilds on AudioService changes ───────
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.audioService,
                    builder: (context, child) => _buildCategoryContent(
                      playlists: widget.audioService.playlists,
                      currentSong: widget.audioService.currentSong,
                      isPlaying: widget.audioService.isPlaying,
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

  Widget _buildCategoryContent({
    required List<Playlist> playlists,
    required Song? currentSong,
    required bool isPlaying,
  }) {
    _refreshLibraryCache();
    switch (_selectedCategoryIndex) {
      case 0:
        return _buildSongsList(_librarySongs, currentSong, isPlaying);
      case 1:
        return _buildPlaylistsView(playlists);
      case 2:
        return _buildAlbumsView();
      case 3:
        return _buildFavoritesList(
          widget.audioService.favorites,
          currentSong,
          isPlaying,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _onSongTap(Song song) {
    if (song.source != SongSource.legacy) {
      widget.onSongTap(song);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Previous source unavailable. "${song.title}" by ${song.artist} '
          'is saved for reference and cannot be played.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildSongsList(
    List<Song> allSongs,
    Song? currentSong,
    bool isPlaying,
  ) {
    if (allSongs.isEmpty) {
      return _buildEmptyState(
        Icons.music_note_rounded,
        'Your library is empty',
        subtitle: 'Scan your device in the Local tab to add music',
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: allSongs.length + 1,
      itemBuilder: (context, index) {
        if (index == allSongs.length) return const SizedBox(height: 130);
        final song = allSongs[index];
        final isActive = currentSong?.identity == song.identity;
        return SongTile(
          song: song,
          isActive: isActive,
          isPlaying: isActive && isPlaying,
          onTap: () => _onSongTap(song),
          onFavoriteTap: () => widget.onFavoriteTap(song),
        );
      },
    );
  }

  Song _firstPlayableOrSaved(List<Song> songs) => songs.firstWhere(
    (song) => song.source != SongSource.legacy,
    orElse: () => songs.first,
  );

  Widget _buildPlaylistsView(List<Playlist> playlists) {
    if (playlists.isEmpty) {
      return _buildEmptyState(
        Icons.playlist_add_rounded,
        'No playlists created yet',
      );
    }
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: playlists.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final firstSong = playlist.songs.isEmpty
            ? null
            : _firstPlayableOrSaved(playlist.songs);
        return GestureDetector(
          onTap: () {
            if (firstSong != null) {
              _onSongTap(firstSong);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This playlist is empty! Add songs from the catalog.',
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
                child: LayoutBuilder(
                  builder: (context, constraints) => AlbumArt(
                    gradientId: playlist.gradientId,
                    imageUrl: firstSong?.source == SongSource.online
                        ? firstSong?.albumArtUrl
                        : null,
                    size: constraints.biggest.shortestSide,
                    borderRadius: 12,
                    overlayIcon: Icons.playlist_play_rounded,
                  ),
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
                '${playlist.songs.length} songs',
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
    final albums = _albumMap;
    if (albums.isEmpty) {
      return _buildEmptyState(Icons.album_rounded, 'No albums found');
    }
    final albumKeys = _albumKeys;
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
        final firstSong = _firstPlayableOrSaved(albumSongs);
        return GestureDetector(
          onTap: () => _onSongTap(firstSong),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => AlbumArt(
                    gradientId: firstSong.gradientId,
                    imageUrl: firstSong.source == SongSource.online
                        ? firstSong.albumArtUrl
                        : null,
                    size: constraints.biggest.shortestSide,
                    borderRadius: 12,
                    overlayIcon: Icons.album_rounded,
                  ),
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
                firstSong.artist,
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

  Widget _buildFavoritesList(
    List<Song> allFavorites,
    Song? currentSong,
    bool isPlaying,
  ) {
    if (allFavorites.isEmpty) {
      _favoriteFilterIndex = 0;
      return _buildEmptyState(
        Icons.favorite_outline_rounded,
        'No favorites yet',
        subtitle: 'Tap the heart on a song to add it here',
      );
    }

    final localFavs = allFavorites
        .where((s) => s.source == SongSource.local)
        .toList();
    final legacyFavs = allFavorites
        .where((s) => s.source == SongSource.legacy)
        .toList();
    final onlineFavs = allFavorites
        .where((s) => s.source == SongSource.online)
        .toList();
    if ((legacyFavs.isEmpty && _favoriteFilterIndex == 2) ||
        (onlineFavs.isEmpty && _favoriteFilterIndex == 3)) {
      _favoriteFilterIndex = 0;
    }

    final filtered = switch (_favoriteFilterIndex) {
      1 => localFavs,
      2 => legacyFavs,
      3 => onlineFavs,
      _ => allFavorites,
    };

    return Column(
      children: [
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildFavFilterChip('ALL (${allFavorites.length})', 0),
              const SizedBox(width: 8),
              _buildFavFilterChip('LOCAL (${localFavs.length})', 1),
              if (onlineFavs.isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildFavFilterChip('ONLINE (${onlineFavs.length})', 3),
              ],
              if (legacyFavs.isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildFavFilterChip(
                  'Previous source (${legacyFavs.length})',
                  2,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (legacyFavs.isNotEmpty &&
            (_favoriteFilterIndex == 0 || _favoriteFilterIndex == 2)) ...[
          const Text(
            'Previous-source favorites are saved for reference but unavailable '
            'for playback.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(
                  Icons.favorite_border_rounded,
                  _favoriteFilterIndex == 1
                      ? 'No local favorite songs'
                      : 'No previous-source favorite songs',
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length + 1,
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      return const SizedBox(height: 130);
                    }
                    final song = filtered[index];
                    final isActive = currentSong?.identity == song.identity;
                    return SongTile(
                      song: song,
                      isActive: isActive,
                      isPlaying: isActive && isPlaying,
                      onTap: () => _onSongTap(song),
                      onFavoriteTap: () => widget.onFavoriteTap(song),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFavFilterChip(String label, int index) {
    final isSelected = _favoriteFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _favoriteFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.accentLight.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message, {String? subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 52,
            color: AppColors.textMuted.withValues(alpha: 0.4),
          ),
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
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'New Playlist',
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
            hintText: 'Playlist name',
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
              ),
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
              'Cancel',
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Create', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
