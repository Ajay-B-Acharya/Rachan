import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/jamendo_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/song_tile.dart';

enum SearchFilter { all, local, online }

class SearchScreen extends StatefulWidget {
  final AudioService audioService;
  final Function(Song) onSongTap;
  final Function(Song) onFavoriteTap;

  const SearchScreen({
    super.key,
    required this.audioService,
    required this.onSongTap,
    required this.onFavoriteTap,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final JamendoService _jamendoService = JamendoService.instance;

  SearchFilter _selectedFilter = SearchFilter.all;

  List<Song> _localResults = [];
  List<Song> _onlineResults = [];

  bool _isSearching = false;
  bool _isOnlineLoading = false;
  String? _onlineError;

  Timer? _debounceTimer;

  final List<String> _recentSearches = [
    'Rock',
    'Electronic',
    'Chillout',
    'Acoustic',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _debounceTimer?.cancel();
      setState(() {
        _localResults = [];
        _onlineResults = [];
        _isSearching = false;
        _isOnlineLoading = false;
        _onlineError = null;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();

    // Instant local results filter
    final localMatches = widget.audioService.localSongs.where((song) {
      return song.title.toLowerCase().contains(lowerQuery) ||
          song.artist.toLowerCase().contains(lowerQuery) ||
          song.album.toLowerCase().contains(lowerQuery);
    }).toList();

    setState(() {
      _isSearching = true;
      _localResults = localMatches;
      _isOnlineLoading = true;
      _onlineError = null;
    });

    // Debounce online Jamendo search requests (450ms)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      _performOnlineSearch(query);
    });
  }

  Future<void> _performOnlineSearch(String query) async {
    if (!mounted) return;
    try {
      final results = await _jamendoService.searchTracks(query, limit: 30);
      if (!mounted) return;

      widget.audioService.registerSongs(results);

      setState(() {
        _onlineResults = results;
        _isOnlineLoading = false;
        _onlineError = null;
      });

      // Save to recent searches if found
      if (results.isNotEmpty && !_recentSearches.contains(query)) {
        _recentSearches.insert(0, query);
        if (_recentSearches.length > 8) _recentSearches.removeLast();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isOnlineLoading = false;
        _onlineError = 'Network error loading online results';
      });
    }
  }

  void _triggerSearchWithTag(String tag) {
    _searchController.text = tag;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: tag.length),
    );
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
                  'Search',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                ),
                const SizedBox(height: 18),

                // ── Search Input Field ────────────────────────────────────────
                GlassCard(
                  borderRadius: 14,
                  blurSigma: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: Colors.white.withValues(alpha: 0.05),
                  borderColor: Colors.white.withValues(alpha: 0.12),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, Jamendo...',
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
                              onPressed: _searchController.clear,
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Filter Chips (ALL, LOCAL, ONLINE) ─────────────────────────
                if (_isSearching) _buildFilterTabs(),

                const SizedBox(height: 12),

                // ── Body (Search Results or Default Categories) ───────────────
                Expanded(
                  child: _isSearching
                      ? _buildSearchResultsView()
                      : _buildDefaultView(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          _buildFilterChip('ALL', SearchFilter.all),
          const SizedBox(width: 8),
          _buildFilterChip('LOCAL', SearchFilter.local),
          const SizedBox(width: 8),
          _buildFilterChip('ONLINE (JAMENDO)', SearchFilter.online),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, SearchFilter filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsView() {
    return ListenableBuilder(
      listenable: widget.audioService,
      builder: (context, _) {
        final currentSong = widget.audioService.currentSong;
        final isPlaying = widget.audioService.isPlaying;

        final hasLocal = _localResults.isNotEmpty;
        final hasOnline = _onlineResults.isNotEmpty;

        if (!hasLocal && !hasOnline && !_isOnlineLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 56,
                  color: AppColors.textMuted.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'No results found',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try searching for a genre or different keyword',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          );
        }

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            // ── LOCAL SECTION ─────────────────────────────────────────────────
            if ((_selectedFilter == SearchFilter.all ||
                    _selectedFilter == SearchFilter.local) &&
                hasLocal) ...[
              _buildSectionTitle(
                'Local Device Tracks',
                _localResults.length,
                Colors.amberAccent,
              ),
              const SizedBox(height: 8),
              ..._localResults.map((song) {
                final isActive = currentSong?.id == song.id;
                return SongTile(
                  song: song,
                  isActive: isActive,
                  isPlaying: isActive && isPlaying,
                  onTap: () => widget.onSongTap(song),
                  onFavoriteTap: () => widget.onFavoriteTap(song),
                );
              }),
              const SizedBox(height: 20),
            ],

            // ── ONLINE JAMENDO SECTION ────────────────────────────────────────
            if (_selectedFilter == SearchFilter.all ||
                _selectedFilter == SearchFilter.online) ...[
              _buildSectionTitle(
                'Jamendo Online Tracks',
                _onlineResults.length,
                AppColors.accentLight,
              ),
              const SizedBox(height: 8),

              if (_isOnlineLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.accent),
                    ),
                  ),
                )
              else if (_onlineError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          _onlineError!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _performOnlineSearch(
                            _searchController.text.trim(),
                          ),
                          child: const Text('Retry Online Search'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (!hasOnline)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No online Jamendo tracks found for this query.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              else
                ..._onlineResults.map((song) {
                  final isActive = currentSong?.id == song.id;
                  return SongTile(
                    song: song,
                    isActive: isActive,
                    isPlaying: isActive && isPlaying,
                    onTap: () => widget.onSongTap(song),
                    onFavoriteTap: () => widget.onFavoriteTap(song),
                  );
                }),
            ],

            const SizedBox(height: 130),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, int count, Color accentColor) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14.5,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: accentColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
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
                  'Recent Searches',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                TextButton(
                  onPressed: () => setState(() => _recentSearches.clear()),
                  child: const Text(
                    'Clear All',
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
                    onPressed: () =>
                        setState(() => _recentSearches.removeAt(index)),
                    splashRadius: 16,
                  ),
                  onTap: () => _triggerSearchWithTag(search),
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          Text(
            'Explore Jamendo Genres',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 14),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.6,
            children: [
              _buildGenreCard('Rock', AppColors.getGradientForId(7)),
              _buildGenreCard('Electronic', AppColors.getGradientForId(1)),
              _buildGenreCard('Pop', AppColors.getGradientForId(0)),
              _buildGenreCard('Chillout', AppColors.getGradientForId(5)),
              _buildGenreCard('Acoustic', AppColors.getGradientForId(3)),
              _buildGenreCard('Hip Hop', AppColors.getGradientForId(6)),
            ],
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }

  Widget _buildGenreCard(String title, List<Color> gradient) {
    return GestureDetector(
      onTap: () => _triggerSearchWithTag(title),
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
              color: gradient[0].withValues(alpha: 0.15),
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
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
