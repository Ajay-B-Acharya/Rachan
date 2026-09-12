import 'dart:async';

import '../models/youtube_video.dart';
import 'youtube_metadata_stub.dart'
    if (dart.library.io) 'youtube_metadata_native.dart'
    as metadata;
import 'youtube_service.dart';

export 'youtube_service.dart' show YoutubeSourceException;

typedef YoutubeMetadataSearch = Future<List<YoutubeVideo>> Function(
  String query,
);

/// Metadata discovery only. Playback remains with the official YouTube player.
class YoutubeCatalog {
  static final YoutubeCatalog instance = YoutubeCatalog();
  static const discoveryQuery = 'music official video';
  static const _cacheLifetime = Duration(minutes: 10);
  static const _requestTimeout = Duration(seconds: 20);
  static const _maxCacheEntries = 20;
  static const _maxInFlight = 8;

  final YoutubeService _officialService;
  final YoutubeMetadataSearch _metadataSearch;
  final bool _platformSupported;
  final DateTime Function() _now;
  final _cache = <String, _CachedVideos>{};
  final _inFlight = <String, Future<List<YoutubeVideo>>>{};

  YoutubeCatalog({
    YoutubeMetadataSearch? metadataSearch,
    YoutubeService? officialService,
    bool? platformSupported,
    DateTime Function()? now,
  }) : _metadataSearch = metadataSearch ?? metadata.searchYoutubeMetadata,
       _officialService = officialService ?? YoutubeService.instance,
       _platformSupported = platformSupported ?? metadata.isSupported,
       _now = now ?? DateTime.now;

  bool get isAvailable => _officialService.isConfigured || _platformSupported;

  String get sourceDescription => _officialService.isConfigured
      ? 'YouTube Data API · Public music discovery'
      : _platformSupported
      ? 'YouTube public search · Music discovery'
      : 'YouTube discovery on web requires YOUTUBE_API_KEY';

  Future<List<YoutubeVideo>> search(String query) async {
    _requireAvailable();
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return const [];
    if (normalized.length > 500) {
      throw const YoutubeSourceException(
        'Please shorten your YouTube search to 500 characters or fewer.',
      );
    }
    final official = _officialService.isConfigured;
    return _cached(
      '${official ? 'official' : 'public'}:search:$normalized',
      () => official
          ? _officialService.search(normalized)
          : _metadataSearch(normalized),
    );
  }

  /// Public music picks, never personalized recommendations. With an API key,
  /// use the official service's public music chart; otherwise use a fixed search
  /// preset, which must not be presented as a popularity chart.
  Future<List<YoutubeVideo>> discover({bool forceRefresh = false}) async {
    _requireAvailable();
    final official = _officialService.isConfigured;
    return _cached(
      official ? 'official:discover' : 'public:search:$discoveryQuery',
      () => official
          ? _officialService.trending(forceRefresh: forceRefresh)
          : _metadataSearch(discoveryQuery),
      forceRefresh: forceRefresh,
    );
  }

  void _requireAvailable() {
    if (!isAvailable) {
      throw const YoutubeSourceException(
        'YouTube discovery without an API key is unsupported on this platform. '
        'On web, supply YOUTUBE_API_KEY at build time.',
      );
    }
  }

  Future<List<YoutubeVideo>> _cached(
    String key,
    Future<List<YoutubeVideo>> Function() load, {
    bool forceRefresh = false,
  }) {
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final now = _now();
    _cache.removeWhere((_, entry) => !now.isBefore(entry.expiresAt));
    final cached = _cache.remove(key);
    if (cached != null && !forceRefresh) {
      _cache[key] = cached;
      return Future.value(cached.videos);
    }
    if (_inFlight.length >= _maxInFlight) {
      throw const YoutubeSourceException(
        'Too many YouTube requests are running. Please try again shortly.',
      );
    }
    // Defer even synchronous injected failures until the pending entry exists.
    final future = _loadAndCache(key, load);
    _inFlight[key] = future;
    return future;
  }

  Future<List<YoutubeVideo>> _loadAndCache(
    String key,
    Future<List<YoutubeVideo>> Function() load,
  ) async {
    try {
      final videos = List<YoutubeVideo>.unmodifiable(
        await Future.sync(load).timeout(_requestTimeout),
      );
      _cache[key] = _CachedVideos(videos, _now().add(_cacheLifetime));
      while (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      return videos;
    } on YoutubeSourceException {
      rethrow;
    } on TimeoutException {
      throw const YoutubeSourceException(
        'YouTube took too long to respond. Please try again later.',
      );
    } catch (_) {
      throw const YoutubeSourceException(
        'Unable to load YouTube metadata. Check your connection and '
        'try again later.',
      );
    } finally {
      _inFlight.remove(key);
    }
  }
}

class _CachedVideos {
  final List<YoutubeVideo> videos;
  final DateTime expiresAt;

  const _CachedVideos(this.videos, this.expiresAt);
}
