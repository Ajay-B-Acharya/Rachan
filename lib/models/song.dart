enum SongSource { local, legacy, online }

class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String audioPath;
  final bool isFavorite;
  final int gradientId;
  final String? albumArtUrl;
  final SongSource source;
  // Audius's opaque ID, not an integer hash or a persisted stream redirect.
  final String? providerId;
  // Retains the stable key of a saved, now-unavailable source.
  final String? legacyId;
  final String? licenseUrl;
  final bool audioDownloadAllowed;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.audioPath,
    this.isFavorite = false,
    required this.gradientId,
    this.albumArtUrl,
    this.source = SongSource.local,
    this.providerId,
    this.legacyId,
    this.licenseUrl,
    this.audioDownloadAllowed = false,
  });

  static bool isValidProviderId(Object? value) =>
      value is String &&
      value.isNotEmpty &&
      value.length <= 64 &&
      !RegExp(r'[^a-zA-Z0-9]').hasMatch(value);

  String get identity {
    if (source == SongSource.online) return 'online:audius:$providerId';
    if (source == SongSource.legacy && legacyId != null) {
      return 'legacy:key:$legacyId';
    }
    return '${source.name}:$id';
  }

  bool get isOnline => source != SongSource.local;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': duration.inMilliseconds,
    // Online playback always resolves a fresh official endpoint.
    'audioPath': source == SongSource.online ? '' : audioPath,
    'isFavorite': isFavorite,
    'gradientId': gradientId,
    'albumArtUrl': albumArtUrl,
    'source': source.name,
    if (source == SongSource.online && isValidProviderId(providerId))
      'providerId': providerId,
    if (legacyId != null) 'legacyId': legacyId,
    'licenseUrl': licenseUrl,
    'audioDownloadAllowed': audioDownloadAllowed,
  };

  factory Song.fromJson(Map<String, dynamic> json) {
    final tag = json['source'];
    final online = tag == 'online' && isValidProviderId(json['providerId']);
    final source = tag == null || tag == 'local'
        ? SongSource.local
        : online
        ? SongSource.online
        : SongSource.legacy;
    final oldKey = json['legacyId'] ?? json['videoId'] ?? json['providerId'];
    return Song(
      id: source == SongSource.online ? 0 : _integer(json['id']),
      title: _text(json['title'], 'Unknown Title'),
      artist: _text(json['artist'], 'Unknown Artist'),
      album: _text(json['album'], 'Unknown Album'),
      duration: Duration(milliseconds: _integer(json['durationMs'])),
      audioPath: source == SongSource.online
          ? ''
          : _text(json['audioPath'], ''),
      isFavorite: json['isFavorite'] == true,
      gradientId: _integer(json['gradientId']),
      albumArtUrl: json['albumArtUrl'] is String
          ? json['albumArtUrl'] as String
          : null,
      // Unknown/old nonlocal tags never become playable local files.
      source: source,
      providerId: online ? json['providerId'] as String : null,
      legacyId: source == SongSource.legacy && oldKey is String ? oldKey : null,
      licenseUrl: json['licenseUrl'] is String
          ? json['licenseUrl'] as String
          : null,
      audioDownloadAllowed: json['audioDownloadAllowed'] == true,
    );
  }

  /// Only public full-length Audius tracks are admitted to the catalog.
  factory Song.fromAudius(Map<String, dynamic> json) {
    final conditions = json['stream_conditions'];
    final access = json['access'];
    final duration = json['duration'];
    if (!isValidProviderId(json['id']) ||
        json['is_streamable'] != true ||
        json['is_available'] == false ||
        json['is_delete'] != false ||
        json['is_unlisted'] != false ||
        json['is_stream_gated'] != false ||
        (conditions != null && !(conditions is Map && conditions.isEmpty)) ||
        (access != null && !(access is Map && access['stream'] == true)) ||
        !_isUnrestricted(json['allowed_api_keys']) ||
        !_isUnrestricted(json['access_authorities']) ||
        json['preview_only'] == true ||
        json['is_preview_only'] == true ||
        json['is_preview'] == true ||
        duration is! num ||
        !duration.isFinite ||
        duration <= 0 ||
        duration > 86400) {
      throw const FormatException('Track is not available for full streaming.');
    }
    final user = json['user'];
    final artwork = json['artwork'];
    String? artUrl;
    if (artwork is Map) {
      for (final size in ['1000x1000', '480x480', '150x150']) {
        final value = artwork[size];
        final uri = value is String ? Uri.tryParse(value) : null;
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty) {
          artUrl = uri.toString();
          break;
        }
      }
    }
    return Song(
      id: 0,
      providerId: json['id'] as String,
      source: SongSource.online,
      title: _text(json['title'], 'Unknown Title'),
      artist: user is Map
          ? _text(user['name'], 'Unknown Artist')
          : 'Unknown Artist',
      album: 'Audius',
      duration: Duration(milliseconds: (duration * 1000).round()),
      audioPath: '',
      gradientId: 0,
      albumArtUrl: artUrl,
    );
  }

  static bool _isUnrestricted(Object? value) =>
      value == null || (value is List && value.isEmpty);

  static String _text(Object? value, String fallback) =>
      value is String && value.trim().isNotEmpty ? value.trim() : fallback;

  static int _integer(Object? value) => value is int ? value : 0;

  Song copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? audioPath,
    bool? isFavorite,
    int? gradientId,
    String? albumArtUrl,
    SongSource? source,
    String? providerId,
    String? legacyId,
    String? licenseUrl,
    bool? audioDownloadAllowed,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      audioPath: audioPath ?? this.audioPath,
      isFavorite: isFavorite ?? this.isFavorite,
      gradientId: gradientId ?? this.gradientId,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      source: source ?? this.source,
      providerId: providerId ?? this.providerId,
      legacyId: legacyId ?? this.legacyId,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      audioDownloadAllowed: audioDownloadAllowed ?? this.audioDownloadAllowed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song &&
          runtimeType == other.runtimeType &&
          identity == other.identity;

  @override
  int get hashCode => identity.hashCode;
}
