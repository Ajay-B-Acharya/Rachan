import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/youtube_config.dart';
import '../models/youtube_video.dart';

class YoutubeSourceException implements Exception {
  final String message;

  const YoutubeSourceException(this.message);

  @override
  String toString() => message;
}

/// Official YouTube Data API metadata only; no audio extraction or stream URLs.
class YoutubeService {
  static final YoutubeService instance = YoutubeService();
  static const _cacheLifetime = Duration(minutes: 10);
  static const _requestTimeout = Duration(seconds: 12);
  static const _maxCacheEntries = 20;
  static const _maxInFlight = 8;

  final http.Client _client;
  final String _apiKey;
  final _cache = <String, _CachedVideos>{};
  final _inFlight = <String, Future<List<YoutubeVideo>>>{};

  YoutubeService({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey = (apiKey ?? YoutubeConfig.apiKey).trim();

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<List<YoutubeVideo>> search(String query) async {
    _requireConfiguration();
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return const [];
    if (normalized.length > 500) {
      throw const YoutubeSourceException(
        'Please shorten your YouTube search to 500 characters or fewer.',
      );
    }
    return _cached(
      'search:$normalized',
      () => _request('search', {
        'part': 'snippet',
        'q': normalized,
        'type': 'video',
        'videoCategoryId': '10',
        'videoEmbeddable': 'true',
        'videoSyndicated': 'true',
        'maxResults': '12',
      }),
    );
  }

  /// Public most-popular music, not personalized recommendations.
  Future<List<YoutubeVideo>> trending({bool forceRefresh = false}) async {
    _requireConfiguration();
    return _cached(
      'trending',
      () => _request('videos', {
        'part': 'snippet,contentDetails,status',
        'chart': 'mostPopular',
        'videoCategoryId': '10',
        'maxResults': '12',
      }, requireEmbeddable: true),
      forceRefresh: forceRefresh,
    );
  }

  void _requireConfiguration() {
    if (!isConfigured) {
      throw const YoutubeSourceException(
        'YouTube discovery is not configured. Supply YOUTUBE_API_KEY with '
        '--dart-define at build time, or paste a video link to play here.',
      );
    }
  }

  Future<List<YoutubeVideo>> _cached(
    String key,
    Future<List<YoutubeVideo>> Function() load, {
    bool forceRefresh = false,
  }) {
    // Refreshes of the same source also share the running request.
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final now = DateTime.now();
    _cache.removeWhere((_, entry) => !now.isBefore(entry.expiresAt));
    final existing = _cache.remove(key);
    if (existing != null && !forceRefresh) {
      _cache[key] = existing;
      return Future.value(existing.videos);
    }
    if (_inFlight.length >= _maxInFlight) {
      throw const YoutubeSourceException(
        'Too many YouTube requests are running. Please try again shortly.',
      );
    }
    final future = _loadAndCache(key, load);
    _inFlight[key] = future;
    return future;
  }

  Future<List<YoutubeVideo>> _loadAndCache(
    String key,
    Future<List<YoutubeVideo>> Function() load,
  ) async {
    try {
      final videos = List<YoutubeVideo>.unmodifiable(await load());
      _cache[key] = _CachedVideos(videos, DateTime.now().add(_cacheLifetime));
      while (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      return videos;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<List<YoutubeVideo>> _request(
    String resource,
    Map<String, String> parameters, {
    bool requireEmbeddable = false,
  }) async {
    final uri = Uri.https(
      YoutubeConfig.apiHost,
      '${YoutubeConfig.apiPath}/$resource',
      {...parameters, 'key': _apiKey},
    );
    try {
      final response = await _client.get(uri).timeout(_requestTimeout);
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const YoutubeSourceException(
            'YouTube returned an invalid response. Please try again.',
          );
        }
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          (decoded is Map && decoded['error'] != null)) {
        throw _apiError(response.statusCode, decoded);
      }
      if (decoded is! Map || decoded['items'] is! List) {
        throw const YoutubeSourceException(
          'YouTube returned an invalid response. Please try again.',
        );
      }
      final videos = <YoutubeVideo>[];
      final ids = <String>{};
      for (final item in decoded['items'] as List) {
        if (item is! Map<String, dynamic>) continue;
        if (requireEmbeddable) {
          final status = item['status'];
          if (status is! Map || status['embeddable'] != true) continue;
        }
        try {
          final video = YoutubeVideo.fromSearchJson(item);
          if (ids.add(video.id)) videos.add(video);
        } on FormatException {
          // A malformed/non-video item must not invalidate valid results.
          continue;
        }
        if (videos.length == 12) break;
      }
      return videos;
    } on YoutubeSourceException {
      rethrow;
    } on TimeoutException {
      throw const YoutubeSourceException(
        'YouTube took too long to respond. Please try again.',
      );
    } catch (_) {
      // Never surface transport exceptions or response messages: they may
      // include the request URI (and therefore the application API key).
      throw const YoutubeSourceException(
        'Unable to reach YouTube. Check your connection and try again.',
      );
    }
  }

  YoutubeSourceException _apiError(int statusCode, Object? decoded) {
    final error = decoded is Map ? decoded['error'] : null;
    final errors = error is Map ? error['errors'] : null;
    final reasons = <String>{};
    if (errors is List) {
      for (final detail in errors) {
        if (detail is Map && detail['reason'] is String) {
          reasons.add(detail['reason'] as String);
        }
      }
    }
    final details = error is Map ? error['details'] : null;
    if (details is List) {
      for (final detail in details) {
        if (detail is Map && detail['reason'] is String) {
          reasons.add(detail['reason'] as String);
        }
      }
    }
    if (statusCode == 429 ||
        (error is Map && error['status'] == 'RESOURCE_EXHAUSTED') ||
        reasons.any(
          {
            'quotaExceeded',
            'dailyLimitExceeded',
            'dailyLimitExceededUnreg',
            'rateLimitExceeded',
            'userRateLimitExceeded',
          }.contains,
        )) {
      return const YoutubeSourceException(
        'YouTube API quota or rate limit has been reached. Try again later '
        'or paste a video link to play here.',
      );
    }
    if (statusCode == 401 ||
        statusCode == 403 ||
        reasons.any(
          {
            'keyInvalid',
            'API_KEY_INVALID',
            'API_KEY_SERVICE_BLOCKED',
            'API_KEY_HTTP_REFERRER_BLOCKED',
            'API_KEY_IP_ADDRESS_BLOCKED',
            'SERVICE_DISABLED',
            'authError',
            'accessNotConfigured',
            'ipRefererBlocked',
            'forbidden',
          }.contains,
        ) ||
        (error is Map && error['status'] == 'UNAUTHENTICATED')) {
      return const YoutubeSourceException(
        'YouTube API authorization failed. Check YOUTUBE_API_KEY, key '
        'restrictions, and that YouTube Data API v3 is enabled.',
      );
    }
    return const YoutubeSourceException(
      'YouTube is temporarily unavailable or rejected the request. '
      'Please try again later.',
    );
  }
}

class _CachedVideos {
  final List<YoutubeVideo> videos;
  final DateTime expiresAt;

  const _CachedVideos(this.videos, this.expiresAt);
}
