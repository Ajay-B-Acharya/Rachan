/// YouTube metadata only. IDs are opaque strings, not local Song IDs, and no
/// audio or download URL is exposed.
class YoutubeVideo {
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration duration;

  const YoutubeVideo({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.duration = Duration.zero,
  });

  /// Accepts a search.list item or a videos.list item. Search results do not
  /// include contentDetails, so their duration remains zero.
  factory YoutubeVideo.fromSearchJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is String
        ? rawId
        : rawId is Map
        ? rawId['videoId']
        : null;
    if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
      throw const FormatException('Invalid YouTube video ID.');
    }
    final snippet = json['snippet'] is Map ? json['snippet'] as Map : const {};
    final thumbnails = snippet['thumbnails'] is Map
        ? snippet['thumbnails'] as Map
        : const {};
    var thumbnailUrl = '';
    for (final size in ['maxres', 'standard', 'high', 'medium', 'default']) {
      final image = thumbnails[size];
      final url = image is Map ? image['url'] : null;
      if (url is String && url.trim().isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
          thumbnailUrl = url;
          break;
        }
      }
    }
    final details = json['contentDetails'];
    return YoutubeVideo(
      id: id,
      title: _text(snippet['title'], 'Untitled video'),
      // The API supplies a channel title, not a verified recording artist.
      artist: _text(snippet['channelTitle'], 'Unknown channel'),
      thumbnailUrl: thumbnailUrl,
      duration: _duration(details is Map ? details['duration'] : null),
    );
  }

  static String _text(Object? value, String fallback) {
    if (value is! String || value.trim().isEmpty) return fallback;
    const entities = {
      'amp': '&',
      'quot': '"',
      'apos': "'",
      'lt': '<',
      'gt': '>',
      'nbsp': ' ',
    };
    return value.trim().replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|quot|apos|lt|gt|nbsp);'),
      (match) {
        final entity = match[1]!;
        if (!entity.startsWith('#')) return entities[entity]!;
        final code = entity.startsWith('#x')
            ? int.tryParse(entity.substring(2), radix: 16)
            : int.tryParse(entity.substring(1));
        if (code == null ||
            code <= 0 ||
            code > 0x10ffff ||
            (code >= 0xd800 && code <= 0xdfff)) {
          return match[0]!;
        }
        return String.fromCharCode(code);
      },
    );
  }

  static Duration _duration(Object? value) {
    if (value is! String) return Duration.zero;
    final match = RegExp(
      r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)$',
    ).firstMatch(value);
    if (match == null) return Duration.zero;
    final days = int.tryParse(match[1] ?? '0') ?? 0;
    final hours = int.tryParse(match[2] ?? '0') ?? 0;
    final minutes = int.tryParse(match[3] ?? '0') ?? 0;
    final seconds = double.tryParse(match[4] ?? '0') ?? 0;
    if (!seconds.isFinite) return Duration.zero;
    return Duration(
      days: days,
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }
}
