import 'youtube_video.dart';

enum SongSource { local, legacy, youtube }

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
  final String? videoId;
  final String? licenseUrl;
  final bool audioDownloadAllowed;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required String audioPath,
    this.isFavorite = false,
    required this.gradientId,
    this.albumArtUrl,
    this.source = SongSource.local,
    this.videoId,
    this.licenseUrl,
    this.audioDownloadAllowed = false,
  }) : audioPath = source == SongSource.youtube ? '' : audioPath;

  factory Song.fromYoutube(YoutubeVideo video) {
    // Stable artwork selection only; this hash is never used as track identity.
    final gradient = video.id.codeUnits.fold<int>(
      0,
      (hash, unit) => (hash * 31 + unit) & 0x7fffffff,
    );
    return Song(
      id: 0,
      title: video.title,
      artist: video.artist,
      album: 'YouTube',
      duration: video.duration,
      audioPath: '',
      gradientId: gradient,
      albumArtUrl: video.thumbnailUrl,
      source: SongSource.youtube,
      videoId: video.id,
    );
  }

  String get identity => source == SongSource.youtube
      ? 'youtube:${videoId ?? ''}'
      : '${source.name}:$id';

  bool get isOnline => source != SongSource.local;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': duration.inMilliseconds,
    'audioPath': source == SongSource.youtube ? '' : audioPath,
    'isFavorite': isFavorite,
    'gradientId': gradientId,
    'albumArtUrl': albumArtUrl,
    'source': source.name,
    if (videoId != null) 'videoId': videoId,
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
      // Missing source predates source tagging and represents a local file.
      // Unknown nonlocal tags must never silently become playable local songs.
      source: json['source'] == null || json['source'] == 'local'
          ? SongSource.local
          : json['source'] == 'youtube'
          ? SongSource.youtube
          : SongSource.legacy,
      videoId: json['videoId'] as String?,
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
    String? videoId,
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
      videoId: videoId ?? this.videoId,
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
