/// Public YouTube Data API configuration supplied at build time.
///
/// Run with `--dart-define=YOUTUBE_API_KEY=...`. Restrict the key to the
/// YouTube Data API and the intended application in Google Cloud Console.
abstract final class YoutubeConfig {
  static const String apiKey = String.fromEnvironment('YOUTUBE_API_KEY');
  static const String apiHost = 'www.googleapis.com';
  static const String apiPath = '/youtube/v3';
}
