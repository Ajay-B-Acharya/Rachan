import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/online_music_service.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';

class SearchScreen extends StatefulWidget {
  final AudioService audioService;
  final ValueChanged<Song> onSongTap;
  final ValueChanged<Song> onFavoriteTap;
  final void Function(Song, List<Song>)? onQueueTap;
  final Future<List<Song>> Function(String)? searchOnline;

  const SearchScreen({
    super.key,
    required this.audioService,
    required this.onSongTap,
    required this.onFavoriteTap,
    this.onQueueTap,
    this.searchOnline,
  });
  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  String? _cachedQuery;
  int _revision = -1;
  int _request = 0;
  List<Song> _matches = [];
  List<Song> _online = [];
  bool _loading = false;
  String? _error;
  bool _submitted = false;
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _request++;
    _controller.dispose();
    super.dispose();
  }

  void setQuery(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
  }

  void _changed() {
    final query = _controller.text.trim();
    if (_query != query) {
      setState(() {
        _query = query;
        _request++;
        _online = [];
        _submitted = false;
        _loading = false;
        _error = null;
      });
    }
  }

  Future<void> _search() async {
    if (_query.isEmpty || _filter == 2) return;
    final request = ++_request;
    final query = _query;
    setState(() {
      _loading = true;
      _error = null;
      _submitted = true;
    });
    try {
      final results =
          await (widget.searchOnline?.call(query) ??
              OnlineMusicService.instance.search(query));
      if (!mounted || request != _request) return;
      widget.audioService.registerSongs(results);
      setState(() {
        _online = results;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'Could not search online music. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Find your sound.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Discover on Audius. Keep your device favorites.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search songs, artists, or genres',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _controller.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in [(0, 'All'), (1, 'Online'), (2, 'Local')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: _filter == entry.$1,
                        showCheckmark: false,
                        selectedColor: AppColors.accent,
                        labelStyle: TextStyle(
                          color: _filter == entry.$1
                              ? AppColors.background
                              : AppColors.textSecondary,
                        ),
                        onSelected: (_) => setState(() {
                          _filter = entry.$1;
                          if (_filter == 2) {
                            _request++;
                            _loading = false;
                          }
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.audioService,
                builder: (context, _) {
                  if (_cachedQuery != _query ||
                      _revision != widget.audioService.localSongsRevision) {
                    _cachedQuery = _query;
                    _revision = widget.audioService.localSongsRevision;
                    final lower = _query.toLowerCase();
                    _matches = widget.audioService.localSongs
                        .where(
                          (song) =>
                              lower.isEmpty ||
                              song.title.toLowerCase().contains(lower) ||
                              song.artist.toLowerCase().contains(lower) ||
                              song.album.toLowerCase().contains(lower),
                        )
                        .toList();
                  }
                  return CustomScrollView(
                    slivers: [
                      if (_filter != 2) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: _query.isEmpty
                                ? Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: AppColors.backgroundSurface,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'A new favorite awaits.',
                                          style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(height: 9),
                                        Text(
                                          'Search independent artists, original music, and edits from Audius. Public, full-length tracks only.',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                      onPressed: _loading ? null : _search,
                                      icon: const Icon(
                                        Icons.search_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _error == null
                                            ? 'Search online'
                                            : 'Retry online search',
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        if (_loading)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        if (_error != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        if (_online.isNotEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Online results · Audius',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        _songs(_online),
                        if (_submitted &&
                            !_loading &&
                            _error == null &&
                            _online.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 24),
                              child: Text(
                                'No public tracks found. Try another artist or genre.',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ),
                          ),
                      ],
                      if (_filter != 1) ...[
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'On your device',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_matches.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Text(
                                _query.isEmpty
                                    ? 'Scan your songs in the Local tab.'
                                    : 'No local results found',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        _songs(_matches),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 28)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _songs(List<Song> songs) => SliverList.builder(
    itemCount: songs.length,
    itemBuilder: (context, index) {
      final song = songs[index].copyWith(
        isFavorite: widget.audioService.isSongFavorite(songs[index]),
      );
      final active = widget.audioService.currentSong == song;
      return SongTile(
        song: song,
        isActive: active,
        isPlaying: active && widget.audioService.isPlaying,
        onTap: () {
          if (widget.onQueueTap != null) {
            widget.onQueueTap!(song, songs);
          } else {
            widget.onSongTap(song);
          }
        },
        onFavoriteTap: () => widget.onFavoriteTap(song),
      );
    },
  );
}
