/// Safe links to YouTube itself, independent of API configuration.
abstract final class YoutubeLinks {
  static final RegExp _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static const _hosts = {
    'youtube.com',
    'www.youtube.com',
    'music.youtube.com',
    'youtu.be',
  };

  static Uri get home => Uri.https('music.youtube.com', '/');

  static Uri search(String query) =>
      Uri.https('music.youtube.com', '/search', {'q': query.trim()});

  static Uri musicWatch(String videoId) =>
      watch(videoId).replace(host: 'music.youtube.com');

  static Uri watch(String videoId) {
    if (!_videoId.hasMatch(videoId)) {
      throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube video ID');
    }
    return Uri.https('www.youtube.com', '/watch', {'v': videoId});
  }

  /// Accepts an exact 11-character ID, watch/embed/shorts/live links, or youtu.be
  /// links. Hostnames are allowlisted exactly; lookalikes and redirect URLs
  /// are not accepted. Surrounding whitespace is harmless and is trimmed.
  static String? videoIdFromInput(String input) {
    final value = input.trim();
    if (_videoId.hasMatch(value)) return value;
    if (value.isEmpty || RegExp(r'[\s\\]').hasMatch(value)) return null;
    try {
      final uri = Uri.tryParse(
        value.contains('://') ? value : 'https://$value',
      );
      if (uri == null || !_isTrusted(uri)) return null;
      final segments = uri.pathSegments;
      String? id;
      if (uri.host.toLowerCase() == 'youtu.be') {
        if (segments.length == 1) id = segments.single;
      } else if (uri.path == '/watch') {
        final values = uri.queryParametersAll['v'];
        if (values?.length == 1) id = values!.single;
      } else if (segments.length == 2 &&
          const {'embed', 'shorts', 'live'}.contains(segments.first)) {
        id = segments[1];
      }
      return id != null && _videoId.hasMatch(id) ? id : null;
    } on FormatException {
      return null;
    }
  }

  static bool _isTrusted(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.userInfo.isEmpty &&
      _hosts.contains(uri.host.toLowerCase()) &&
      (!uri.hasPort ||
          (uri.scheme == 'https' && uri.port == 443) ||
          (uri.scheme == 'http' && uri.port == 80));

}
