import '../models/youtube_video.dart';
import 'youtube_service.dart';

bool get isSupported => false;

Future<List<YoutubeVideo>> searchYoutubeMetadata(String query) async {
  throw const YoutubeSourceException(
    'YouTube discovery without an API key is unsupported on web. '
    'Supply YOUTUBE_API_KEY at build time. No CORS proxy is used.',
  );
}
