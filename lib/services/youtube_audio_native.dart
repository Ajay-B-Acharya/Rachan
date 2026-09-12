import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Uses the package's standard client only, with no alternate clients or bypass.
Future<Uri> resolveYoutubeAudio(String videoId) async {
  if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
    throw const FormatException('Invalid YouTube video ID.');
  }
  final client = YoutubeExplode();
  try {
    final manifest = await client.videos.streamsClient
        .getManifest(videoId)
        .timeout(const Duration(seconds: 20));
    final streams = manifest.audioOnly.toList();
    if (streams.isEmpty) {
      throw StateError('No audio-only stream available.');
    }
    final mp4 = streams.where((s) => s.container.name == 'mp4').toList();
    final candidates = mp4.isNotEmpty ? mp4 : streams;
    candidates.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final uri = candidates.first.url;
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('Invalid audio stream.');
    }
    return uri;
  } catch (_) {
    // Package/network exceptions may contain signed stream URLs.
    throw StateError('YouTube audio is unavailable. Please try again.');
  } finally {
    client.close();
  }
}
