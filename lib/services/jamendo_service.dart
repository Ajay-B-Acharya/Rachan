import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/jamendo_config.dart';
import '../models/song.dart';

class _CacheEntry {
  final List<Song> songs;
  final DateTime timestamp;

  _CacheEntry(this.songs) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp) > const Duration(minutes: 15);
}

class JamendoService {
  static final JamendoService instance = JamendoService._internal();

  factory JamendoService() => instance;

  JamendoService._internal();

  final http.Client _client = http.Client();

  // In-memory cache for API queries with 15-minute TTL
  final Map<String, _CacheEntry> _cache = {};

  // Track cache by ID
  final Map<int, Song> _trackCache = {};

  /// Core request dispatcher to Jamendo API v3.0
  Future<List<Song>> _fetchTracks(
    Map<String, String> queryParameters, {
    String? cacheKey,
    bool forceRefresh = false,
  }) async {
    // Check in-memory cache first if key provided
    if (cacheKey != null && !forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired) {
        debugPrint('[JAMENDO_SERVICE] Returning cached results for key: $cacheKey');
        return cached.songs;
      }
    }

    // Prepare query parameters with mandatory client_id & format
    final Map<String, String> params = {
      'client_id': JamendoConfig.clientId,
      'format': JamendoConfig.defaultFormat,
      ...queryParameters,
    };

    final uri = Uri.parse('${JamendoConfig.apiBaseUrl}/tracks').replace(
      queryParameters: params,
    );

    debugPrint('[JAMENDO_SERVICE] GET: ${uri.toString().replaceAll(JamendoConfig.clientId, 'CLIENT_ID')}');

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'Harmoniq/1.0',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            json.decode(response.body) as Map<String, dynamic>;

        final headers = data['headers'] as Map<String, dynamic>?;
        final status = headers?['status'] as String?;
        if (status != 'success') {
          final errMsg = headers?['error_message'] ?? 'Unknown Jamendo API error';
          debugPrint('[JAMENDO_SERVICE] API error: $errMsg');
          return cacheKey != null && _cache.containsKey(cacheKey)
              ? _cache[cacheKey]!.songs
              : [];
        }

        final List<dynamic>? results = data['results'] as List<dynamic>?;
        if (results == null || results.isEmpty) {
          debugPrint('[JAMENDO_SERVICE] No tracks returned.');
          return [];
        }

        final List<Song> songs = [];
        for (final item in results) {
          if (item is Map<String, dynamic>) {
            final song = Song.fromJamendo(item);
            // Only add tracks that have valid streamable audio URLs
            if (song.audioPath.isNotEmpty) {
              songs.add(song);
              _trackCache[song.id] = song;
            }
          }
        }

        if (cacheKey != null) {
          _cache[cacheKey] = _CacheEntry(songs);
        }

        debugPrint('[JAMENDO_SERVICE] Successfully fetched ${songs.length} tracks.');
        return songs;
      } else {
        debugPrint('[JAMENDO_SERVICE] HTTP error: ${response.statusCode}');
        if (cacheKey != null && _cache.containsKey(cacheKey)) {
          return _cache[cacheKey]!.songs;
        }
        return [];
      }
    } on SocketException catch (e) {
      debugPrint('[JAMENDO_SERVICE] Network unreachable / offline: $e');
      if (cacheKey != null && _cache.containsKey(cacheKey)) {
        return _cache[cacheKey]!.songs;
      }
      return [];
    } on TimeoutException catch (e) {
      debugPrint('[JAMENDO_SERVICE] Request timed out: $e');
      if (cacheKey != null && _cache.containsKey(cacheKey)) {
        return _cache[cacheKey]!.songs;
      }
      return [];
    } catch (e, stack) {
      debugPrint('[JAMENDO_SERVICE] Unexpected error: $e\n$stack');
      if (cacheKey != null && _cache.containsKey(cacheKey)) {
        return _cache[cacheKey]!.songs;
      }
      return [];
    }
  }

  /// Search tracks by name, artist or tag
  Future<List<Song>> searchTracks(
    String query, {
    int limit = 25,
    int offset = 0,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final cacheKey = 'search_${trimmed.toLowerCase()}_${limit}_$offset';

    return _fetchTracks(
      {
        'namesearch': trimmed,
        'limit': limit.toString(),
        'offset': offset.toString(),
        'order': 'popularity_total',
      },
      cacheKey: cacheKey,
    );
  }

  /// Popular tracks of all time
  Future<List<Song>> getPopularTracks({
    int limit = 20,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    return _fetchTracks(
      {
        'order': 'popularity_total',
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
      cacheKey: 'popular_${limit}_$offset',
      forceRefresh: forceRefresh,
    );
  }

  /// Trending tracks (popularity this week)
  Future<List<Song>> getTrendingTracks({
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    return _fetchTracks(
      {
        'order': 'popularity_week',
        'limit': limit.toString(),
      },
      cacheKey: 'trending_$limit',
      forceRefresh: forceRefresh,
    );
  }

  /// Recently released/discovered tracks
  Future<List<Song>> getRecentlyDiscoveredTracks({
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    return _fetchTracks(
      {
        'order': 'releasedate_desc',
        'limit': limit.toString(),
      },
      cacheKey: 'recent_$limit',
      forceRefresh: forceRefresh,
    );
  }

  /// Recommended tracks (featured tracks on Jamendo)
  Future<List<Song>> getRecommendedTracks({
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    return _fetchTracks(
      {
        'featured': '1',
        'limit': limit.toString(),
      },
      cacheKey: 'recommended_$limit',
      forceRefresh: forceRefresh,
    );
  }

  /// Generic track fetcher with flexible parameters
  Future<List<Song>> getTracks({
    String? order,
    String? tags,
    String? namesearch,
    int limit = 20,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final Map<String, String> params = {
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (order != null) params['order'] = order;
    if (tags != null) params['fuzzytags'] = tags;
    if (namesearch != null) params['namesearch'] = namesearch;

    final cacheKey =
        'tracks_${order ?? ""}_${tags ?? ""}_${namesearch ?? ""}_${limit}_$offset';

    return _fetchTracks(
      params,
      cacheKey: cacheKey,
      forceRefresh: forceRefresh,
    );
  }

  /// Fetch a single track by its Jamendo ID
  Future<Song?> getTrackById(String id) async {
    final parsedId = int.tryParse(id);
    if (parsedId != null && _trackCache.containsKey(parsedId)) {
      return _trackCache[parsedId];
    }

    final tracks = await _fetchTracks(
      {'id': id, 'limit': '1'},
      cacheKey: 'track_$id',
    );

    if (tracks.isNotEmpty) {
      _trackCache[tracks.first.id] = tracks.first;
      return tracks.first;
    }
    return null;
  }
}
