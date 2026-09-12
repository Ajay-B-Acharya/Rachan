enum SongSource {
  local,
  jamendo,
}

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
    this.licenseUrl,
    this.audioDownloadAllowed = false,
  });

  bool get isOnline => source == SongSource.jamendo;

  factory Song.fromJamendo(Map<String, dynamic> json) {
    final int rawId = int.tryParse(json['id']?.toString() ?? '0') ?? 0;
    final int durationSec =
        int.tryParse(json['duration']?.toString() ?? '0') ?? 0;
    final String audioUrl = (json['audio'] as String?) ?? '';
    final String? artUrl =
        (json['image'] as String?) ?? (json['album_image'] as String?);
    final String? licenseUrl =
        (json['license_ccurl'] as String?)?.trim().isNotEmpty == true
            ? json['license_ccurl'] as String
            : null;
    final bool audioDownloadAllowed = json['audiodownload_allowed'] == true;

    return Song(
      id: rawId,
      title: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Unknown Track',
      artist: (json['artist_name'] as String?)?.trim().isNotEmpty == true
          ? json['artist_name'] as String
          : 'Unknown Artist',
      album: (json['album_name'] as String?)?.trim().isNotEmpty == true
          ? json['album_name'] as String
          : 'Jamendo Music',
      duration: Duration(seconds: durationSec),
      audioPath: audioUrl,
      isFavorite: false,
      gradientId: rawId.abs(),
      albumArtUrl: artUrl,
      source: SongSource.jamendo,
      licenseUrl: licenseUrl,
      audioDownloadAllowed: audioDownloadAllowed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': duration.inMilliseconds,
        'audioPath': audioPath,
        'isFavorite': isFavorite,
        'gradientId': gradientId,
        'albumArtUrl': albumArtUrl,
        'source': source.name,
        'licenseUrl': licenseUrl,
        'audioDownloadAllowed': audioDownloadAllowed,
      };

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? 'Unknown Album',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      audioPath: json['audioPath'] as String? ?? '',
      isFavorite: json['isFavorite'] as bool? ?? false,
      gradientId: json['gradientId'] as int? ?? 0,
      albumArtUrl: json['albumArtUrl'] as String?,
      source: json['source'] == 'jamendo' ? SongSource.jamendo : SongSource.local,
      licenseUrl: json['licenseUrl'] as String?,
      audioDownloadAllowed: json['audioDownloadAllowed'] as bool? ?? false,
    );
  }

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
      licenseUrl: licenseUrl ?? this.licenseUrl,
      audioDownloadAllowed:
          audioDownloadAllowed ?? this.audioDownloadAllowed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
