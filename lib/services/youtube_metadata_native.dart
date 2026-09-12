import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_video.dart';
import 'youtube_service.dart';

bool get isSupported =>
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isMacOS ||
    Platform.isWindows ||
    Platform.isLinux;

/// One public search page, metadata only; no pagination or player requests.
/// [client] permits network-free transport tests and is owned by this request.
Future<List<YoutubeVideo>> searchYoutubeMetadata(
  String query, {
  http.Client? client,
}) async {
  final transport = _MetadataHttpClient(client);
  final youtube = YoutubeExplode(httpClient: transport);
  try {
    final results = await youtube.search
        .search(query)
        .timeout(const Duration(seconds: 20));
    return List<YoutubeVideo>.unmodifiable(
      results.map(
        (video) => YoutubeVideo(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          thumbnailUrl: video.thumbnails.highResUrl,
          duration: video.duration ?? Duration.zero,
        ),
      ),
    );
  } on TimeoutException {
    throw const YoutubeSourceException(
      'YouTube took too long to respond. Please try again later.',
    );
  } catch (_) {
    // The library wraps failures when its client has closed. Retain our safe
    // explanation, never a raw request URL or response body.
    throw transport.failure ??
        const YoutubeSourceException(
          'Unable to read YouTube public metadata. YouTube may be unavailable '
          'or its search page may have changed. Please try again later.',
        );
  } finally {
    youtube.close();
  }
}

/// youtube_explode_dart 3.1.0 defaults to a browser User-Agent, a consent
/// cookie, and retries. This adapter uses neither identity/consent spoofing nor
/// repeated network attempts. Successful responses use the normal parser.
class _MetadataHttpClient extends YoutubeHttpClient {
  bool _requested = false;
  YoutubeSourceException? failure;

  _MetadataHttpClient(super.client);

  @override
  Map<String, String> get headers => const {
    'user-agent': 'Harmoniq/1.0 (public YouTube metadata)',
    'accept': 'text/html',
    'accept-language': 'en-US,en;q=0.5',
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Do not follow consent/authentication/challenge redirects.
    request.followRedirects = false;
    return super.send(request);
  }

  @override
  Future<String> getString(
    dynamic url, {
    Map<String, String> headers = const {},
    bool validate = true,
  }) async {
    try {
      if (_requested) {
        throw const YoutubeSourceException(
          'Unable to read YouTube public metadata. Please try again later.',
        );
      }
      _requested = true;
      final response = await get(
        url is Uri ? url : Uri.parse(url as String),
        headers: headers,
      );
      final body = response.body;
      final location = response.headers['location'] ?? '';
      if (response.statusCode == 429 ||
          response.statusCode == 403 ||
          response.statusCode == 401 ||
          location.contains('/sorry/') ||
          RegExp(
            r"unusual traffic from your computer network|"
            r"sign in to confirm you(?:'|’|&#39;|&apos;)re not a bot|"
            r'confirm you are not a bot|id=["\x27]captcha-form',
            caseSensitive: false,
          ).hasMatch(body)) {
        throw const YoutubeSourceException(
          'YouTube rate-limited or blocked public metadata discovery. '
          'Please try again later. No bypass is attempted.',
        );
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const YoutubeSourceException(
          'YouTube redirected public discovery, possibly for consent or '
          'sign-in. Discovery cannot bypass this step. Try again later.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const YoutubeSourceException(
          'YouTube public metadata is temporarily unavailable. '
          'Please try again later.',
        );
      }
      return body;
    } catch (error) {
      failure = error is YoutubeSourceException
          ? error
          : const YoutubeSourceException(
              'Unable to reach YouTube. Check your connection and '
              'try again later.',
            );
      // SearchPage.get retries exceptions by default. Closing on failure makes
      // that loop exit immediately, without a second network request.
      close();
      throw failure!;
    }
  }
}
