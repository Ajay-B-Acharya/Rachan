import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/song.dart';

enum OnlineMusicFailure {
  offline,
  timeout,
  authentication,
  rateLimited,
  unavailable,
  invalidResponse,
  invalidTrack,
}

/// Fixed, user-safe messages only: never include response bodies, keys or URLs.
class OnlineMusicException implements Exception {
  final OnlineMusicFailure kind;

  const OnlineMusicException(this.kind);

  String get message => switch (kind) {
    OnlineMusicFailure.offline => 'Cannot connect to online music. Check your internet connection and retry.',
    OnlineMusicFailure.timeout =>
      'The online music server took too long to respond. Please retry.',
    OnlineMusicFailure.authentication => 'Audius requires a valid API key for this request. Configure AUDIUS_API_KEY and retry.',
    OnlineMusicFailure.rateLimited =>
      'Online music is receiving too many requests. Please try again later.',
    OnlineMusicFailure.unavailable =>
      'The online music server is unavailable. Please try again later.',
    OnlineMusicFailure.invalidResponse =>
      'The online music server returned an unexpected response. Please retry.',
    OnlineMusicFailure.invalidTrack =>
      'This track is no longer available for full streaming. Try another song.',
  };

  @override
  String toString() => message;
}

class _CatalogEntry {
  final List<Song> songs;
  final DateTime expiresAt;

  const _CatalogEntry(this.songs, this.expiresAt);
}

/// Public Audius discovery and official streaming endpoints, with no scraper,
/// stored signed redirects, embedded credentials, or automatic retry loop.
class OnlineMusicService {
  static final OnlineMusicService instance = OnlineMusicService();
  static const _appName = 'Harmoniq';
  static const _cacheTtl = Duration(minutes: 5);
  static const _requestTimeout = Duration(seconds: 10);
  static const _maxCacheEntries = 20;

  final http.Client _client;
  final String _apiKey;
  final DateTime Function() _now;
  final _cache = <String, _CatalogEntry>{};
  final _inflight = <String, Future<List<Song>>>{};

  OnlineMusicService({
    http.Client? client,
    String? apiKey,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _apiKey = (apiKey ?? const String.fromEnvironment('AUDIUS_API_KEY'))
           .trim(),
       _now = now ?? DateTime.now;

  Uri _endpoint(String path, [Map<String, String> query = const {}]) =>
      Uri.https('api.audius.co', '/v1$path', {
        'app_name': _appName,
        // Matches official SDK addAppInfoMiddleware; not an auth header.
        if (_apiKey.isNotEmpty) 'api_key': _apiKey,
        ...query,
      });

  Future<List<Song>> trending({bool refresh = false}) => _catalog(
    'trending',
    _endpoint('/tracks/trending', {'limit': '50'}),
    refresh: refresh,
  );

  Future<List<Song>> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Future.value(const <Song>[]);
    return _catalog(
      'search:$trimmed',
      _endpoint('/tracks/search', {'query': trimmed, 'limit': '50'}),
    );
  }

  Future<List<Song>> _catalog(String key, Uri uri, {bool refresh = false}) {
    final pending = _inflight[key];
    if (pending != null) return pending;
    final cached = _cache.remove(key);
    if (cached != null && !refresh && _now().isBefore(cached.expiresAt)) {
      _cache[key] = cached;
      return Future.value(cached.songs);
    }
    final future = _fetchCatalog(uri)
        .then((songs) {
          final now = _now();
          _cache.removeWhere((_, entry) => !now.isBefore(entry.expiresAt));
          _cache[key] = _CatalogEntry(songs, now.add(_cacheTtl));
          while (_cache.length > _maxCacheEntries) {
            _cache.remove(_cache.keys.first);
          }
          return songs;
        })
        .whenComplete(() {
          _inflight.remove(key);
        });
    _inflight[key] = future;
    return future;
  }

  Future<List<Song>> _fetchCatalog(Uri uri) async {
    final data = await _metadata(uri);
    if (data is! List) {
      throw const OnlineMusicException(OnlineMusicFailure.invalidResponse);
    }
    final songs = <String, Song>{};
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        final song = Song.fromAudius(entry);
        songs[song.identity] = song;
      } on FormatException {
        // Restricted, deleted, unlisted, malformed and preview-only entries are
        // not playable discoveries. A valid empty result is not a network error.
      }
    }
    return List<Song>.unmodifiable(songs.values);
  }

  /// Revalidate every load/retry; discovery caches must not authorize playback.
  /// Native media playback follows the official endpoint's CDN redirects.
  Future<Uri> streamUri(String trackId) async {
    if (!Song.isValidProviderId(trackId)) {
      throw const OnlineMusicException(OnlineMusicFailure.invalidTrack);
    }
    final data = await _metadata(_endpoint('/tracks/$trackId'));
    if (data is! Map<String, dynamic>) {
      throw const OnlineMusicException(OnlineMusicFailure.invalidResponse);
    }
    try {
      final song = Song.fromAudius(data);
      if (song.providerId != trackId) {
        throw const FormatException('Track ID does not match.');
      }
    } on FormatException {
      throw const OnlineMusicException(OnlineMusicFailure.invalidTrack);
    }
    // Optional public API key follows SDK query syntax. Never set native global
    // auth headers or persist this endpoint (or its signed CDN redirect).
    return _endpoint('/tracks/$trackId/stream');
  }

  Future<dynamic> _metadata(Uri uri) async {
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_requestTimeout);
      switch (response.statusCode) {
        case 200:
          break;
        case 401:
        case 403:
          throw const OnlineMusicException(OnlineMusicFailure.authentication);
        case 404:
        case 410:
          throw const OnlineMusicException(OnlineMusicFailure.invalidTrack);
        case 429:
          throw const OnlineMusicException(OnlineMusicFailure.rateLimited);
        default:
          throw const OnlineMusicException(OnlineMusicFailure.unavailable);
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic> || !body.containsKey('data')) {
        throw const OnlineMusicException(OnlineMusicFailure.invalidResponse);
      }
      return body['data'];
    } on OnlineMusicException {
      rethrow;
    } on TimeoutException {
      throw const OnlineMusicException(OnlineMusicFailure.timeout);
    } on FormatException {
      throw const OnlineMusicException(OnlineMusicFailure.invalidResponse);
    } catch (_) {
      throw const OnlineMusicException(OnlineMusicFailure.offline);
    }
  }
}
