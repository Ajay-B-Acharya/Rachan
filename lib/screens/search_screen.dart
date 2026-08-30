import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';
import '../widgets/glass_card.dart';

class SearchScreen extends StatefulWidget {
  final List<Song> songs;
  final Song? currentSong;
  final Function(Song) onSongTap;
  final Function(Song) onFavoriteTap;

  const SearchScreen({
    super.key,
    required this.songs,
    required this.currentSong,
    required this.onSongTap,
    required this.onFavoriteTap,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Song> _filteredSongs = [];
  bool _isSearching = false;

  // Recent Searches Mock Data
  final List<String> _recentSearches = ["Midnight", "Rayan", "Chill"];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredSongs = [];
        _isSearching = false;
      });
      return;
    }

    final results = widget.songs.where((song) {
      return song.title.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          song.album.toLowerCase().contains(query);
    }).toList();

    setState(() {
      _filteredSongs = results;
      _isSearching = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0C1420), AppColors.background],
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
                Text(
                  "Search",
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 20),
                // Search Input Field
                GlassCard(
                  borderRadius: 14,
                  blurSigma: 8,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: Colors.white.withOpacity(0.05),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: "Search songs, artists, albums...",
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Results or Default View
                Expanded(
                  child: _isSearching
                      ? _buildSearchResults()
                      : _buildDefaultView(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_filteredSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: AppColors.textMuted.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              "No results found",
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              "Double check the spelling or try another query",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 100),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _filteredSongs.length + 1,
      itemBuilder: (context, index) {
        if (index == _filteredSongs.length) {
          return const SizedBox(height: 130);
        }
        final song = _filteredSongs[index];
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

  Widget _buildDefaultView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Recent Searches",
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _recentSearches.clear();
                    });
                  },
                  child: const Text(
                    "Clear All",
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentSearches.length,
              itemBuilder: (context, index) {
                final search = _recentSearches[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(
                    Icons.history_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                  title: Text(
                    search,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () {
                      setState(() {
                        _recentSearches.removeAt(index);
                      });
                    },
                    splashRadius: 16,
                  ),
                  onTap: () {
                    _searchController.text = search;
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: search.length),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          Text(
            "Browse Genres",
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.6,
            children: [
              _buildGenreCard("Pop", AppColors.getGradientForId(0)),
              _buildGenreCard("Electronic", AppColors.getGradientForId(1)),
              _buildGenreCard("Lofi & Chill", AppColors.getGradientForId(5)),
              _buildGenreCard("Rock & Retro", AppColors.getGradientForId(7)),
            ],
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }

  Widget _buildGenreCard(String title, List<Color> gradient) {
    return GestureDetector(
      onTap: () {
        // Set search query based on genre click
        _searchController.text = title.split(' ')[0];
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              bottom: 12,
              left: 12,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: Icon(
                Icons.music_note_rounded,
                size: 56,
                color: Colors.white.withOpacity(0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
