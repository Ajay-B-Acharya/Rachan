import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/models/youtube_video.dart';
import 'package:harmoniq/services/youtube_catalog.dart';
import 'package:harmoniq/services/youtube_metadata_native.dart' as native;
import 'package:harmoniq/services/youtube_metadata_stub.dart' as stub;
import 'package:harmoniq/services/youtube_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _video = YoutubeVideo(
  id: 'dQw4w9WgXcQ',
  title: 'Public music',
  artist: 'Music channel',
  thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
  duration: Duration(minutes: 3, seconds: 32),
);

Matcher _error(String text) => isA<YoutubeSourceException>().having(
  (error) => error.message,
  'message',
  contains(text),
);

YoutubeCatalog _catalog(
  YoutubeMetadataSearch search, {
  bool supported = true,
  DateTime Function()? now,
}) => YoutubeCatalog(
  metadataSearch: search,
  officialService: YoutubeService(apiKey: ''),
  platformSupported: supported,
  now: now,
);

class _TrackingClient extends MockClient {
  bool closed = false;
  int calls = 0;

  _TrackingClient(super.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    return super.send(request);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

String _searchPage({bool duration = true}) {
  final data = {
    'contents': {
      'twoColumnSearchResultsRenderer': {
        'primaryContents': {
          'sectionListRenderer': {
            'contents': [
              {
                'itemSectionRenderer': {
                  'contents': [
                    {
                      'videoRenderer': {
                        'videoId': _video.id,
                        'title': {
                          'runs': [
                            {'text': _video.title},
                          ],
                        },
                        'ownerText': {
                          'runs': [
                            {
                              'text': _video.artist,
                              'navigationEndpoint': {
                                'browseEndpoint': {
                                  'browseId': 'UC1234567890123456789012',
                                },
                              },
                            },
                          ],
                        },
                        if (duration) 'lengthText': {'simpleText': '3:32'},
                      },
                    },
                  ],
                },
              },
            ],
          },
        },
      },
    },
  };
  return '<html><script>var ytInitialData = ${jsonEncode(data)};</script></html>';
}

void main() {
  group('YoutubeCatalog', () {
    test('singleton and native availability need no key', () {
      expect(YoutubeCatalog.instance, same(YoutubeCatalog.instance));
      expect(_catalog((_) async => []).isAvailable, isTrue);
      expect(native.isSupported, isTrue);
      expect(stub.isSupported, isFalse);
    });

    test('unsupported web never invokes injected metadata', () async {
      final catalog = _catalog(
        (_) async => fail('Unexpected request'),
        supported: false,
      );
      expect(catalog.isAvailable, isFalse);
      await expectLater(catalog.search('music'), throwsA(_error('API key')));
      await expectLater(catalog.discover(), throwsA(_error('YOUTUBE_API_KEY')));
      await expectLater(
        stub.searchYoutubeMetadata('music'),
        throwsA(_error('unsupported on web')),
      );
    });

    test('official service takes priority even on web', () async {
      final paths = <String>[];
      final service = YoutubeService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response('{"items":[]}', 200);
        }),
      );
      final catalog = YoutubeCatalog(
        officialService: service,
        platformSupported: false,
        metadataSearch: (_) async => fail('Unexpected no-key fallback'),
      );
      expect(catalog.isAvailable, isTrue);
      expect(catalog.sourceDescription, contains('Data API'));
      await catalog.search('music');
      await catalog.discover();
      await catalog.discover();
      await catalog.discover(forceRefresh: true);
      expect(paths, [
        '/youtube/v3/search',
        '/youtube/v3/videos',
        '/youtube/v3/videos',
      ]);
    });

    test('official errors do not fall back to bypass quotas', () async {
      final catalog = YoutubeCatalog(
        officialService: YoutubeService(
          apiKey: 'test-key',
          client: MockClient((_) async => http.Response('', 429)),
        ),
        platformSupported: true,
        metadataSearch: (_) async => fail('Unexpected fallback'),
      );
      await expectLater(catalog.search('music'), throwsA(_error('quota')));
    });

    test('normalizes, deduplicates and caches immutable copies', () async {
      var calls = 0;
      final response = Completer<List<YoutubeVideo>>();
      final catalog = _catalog((query) {
        expect(query, 'jazz music');
        calls++;
        return response.future;
      });
      final first = catalog.search('  jazz \n music  ');
      final second = catalog.search('jazz music');
      final mutable = [_video];
      response.complete(mutable);
      final results = await first;
      expect(await second, same(results));
      mutable.clear();
      expect(results.single, same(_video));
      expect(() => results.clear(), throwsUnsupportedError);
      expect(await catalog.search('jazz music'), same(results));
      expect(calls, 1);
    });

    test('blank and overlong searches avoid network', () async {
      final catalog = _catalog((_) async => fail('Unexpected request'));
      expect(await catalog.search(' \n '), isEmpty);
      await expectLater(catalog.search('x' * 501), throwsA(_error('500')));
    });

    test('discovery preset shares cache and refreshes deduplicate', () async {
      var calls = 0;
      final refresh = Completer<List<YoutubeVideo>>();
      final catalog = _catalog((query) async {
        expect(query, 'music official video');
        calls++;
        return calls == 1 ? [_video] : refresh.future;
      });
      expect(
        catalog.sourceDescription.toLowerCase(),
        isNot(contains('trending')),
      );
      expect(
        catalog.sourceDescription.toLowerCase(),
        isNot(contains('personalized')),
      );
      await catalog.discover();
      await catalog.search(YoutubeCatalog.discoveryQuery);
      expect(calls, 1);
      final first = catalog.discover(forceRefresh: true);
      final second = catalog.discover(forceRefresh: true);
      refresh.complete([]);
      expect(await first, isEmpty);
      expect(await second, same(await first));
      expect(calls, 2);
    });

    test(
      'cache expires at ten minutes and hits do not extend lifetime',
      () async {
        var now = DateTime.utc(2026);
        var calls = 0;
        final catalog = _catalog((_) async {
          calls++;
          return [];
        }, now: () => now);
        await catalog.search('music');
        now = now.add(const Duration(minutes: 9));
        await catalog.search('music');
        expect(calls, 1);
        now = now.add(const Duration(minutes: 1));
        await catalog.search('music');
        expect(calls, 2);
      },
    );

    test('cache is bounded to twenty least-recently-used entries', () async {
      final calls = <String, int>{};
      final catalog = _catalog((query) async {
        calls[query] = (calls[query] ?? 0) + 1;
        return [];
      });
      for (var i = 0; i < 20; i++) {
        await catalog.search('query$i');
      }
      await catalog.search('query0');
      await catalog.search('query20');
      await catalog.search('query0');
      await catalog.search('query1');
      expect(calls['query0'], 1);
      expect(calls['query1'], 2);
    });

    test('synchronous failures release inflight and are not cached', () async {
      var calls = 0;
      final catalog = _catalog((_) {
        calls++;
        if (calls == 1) throw StateError('private transport detail');
        return Future.value([_video]);
      });
      await expectLater(
        catalog.search('music'),
        throwsA(_error('Unable to load')),
      );
      expect(await catalog.search('music'), [_video]);
      expect(calls, 2);
    });

    test('source errors are preserved without automatic retries', () async {
      var calls = 0;
      const blocked = YoutubeSourceException('YouTube blocked discovery');
      final catalog = _catalog((_) async {
        calls++;
        throw blocked;
      });
      await expectLater(catalog.discover(), throwsA(same(blocked)));
      expect(calls, 1);
    });

    test('inflight capacity is bounded and recovers', () async {
      final response = Completer<List<YoutubeVideo>>();
      final catalog = _catalog((_) => response.future);
      final pending = [for (var i = 0; i < 8; i++) catalog.search('query$i')];
      await expectLater(
        catalog.search('overflow'),
        throwsA(_error('Too many')),
      );
      response.complete([]);
      await Future.wait(pending);
      expect(await catalog.search('overflow'), isEmpty);
    });

    testWidgets('20 second timeout releases inflight without late caching', (
      tester,
    ) async {
      final response = Completer<List<YoutubeVideo>>();
      var calls = 0;
      final catalog = _catalog((_) {
        calls++;
        return calls == 1 ? response.future : Future.value([]);
      });
      final assertion = expectLater(
        catalog.search('music'),
        throwsA(_error('too long')),
      );
      await tester.pump(const Duration(seconds: 20));
      await assertion;
      response.complete([_video]);
      await tester.pump();
      expect(await catalog.search('music'), isEmpty);
      expect(calls, 2);
    });
  });

  group('native metadata adapter', () {
    for (final duration in [true, false]) {
      test(
        'maps public search metadata with duration=$duration and closes',
        () async {
          final client = _TrackingClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.host, 'www.youtube.com');
            expect(request.url.path, '/results');
            expect(request.url.queryParameters['search_query'], 'public music');
            expect(request.headers.containsKey('cookie'), isFalse);
            expect(request.headers.containsKey('authorization'), isFalse);
            expect(request.headers['user-agent'], startsWith('Harmoniq/'));
            expect(request.followRedirects, isFalse);
            return http.Response(_searchPage(duration: duration), 200);
          });
          final videos = await native.searchYoutubeMetadata(
            'public music',
            client: client,
          );
          final video = videos.single;
          expect(video.id, _video.id);
          expect(video.title, _video.title);
          expect(video.artist, _video.artist);
          expect(video.thumbnailUrl, _video.thumbnailUrl);
          expect(video.duration, duration ? _video.duration : Duration.zero);
          expect(() => videos.clear(), throwsUnsupportedError);
          expect(client.calls, 1);
          expect(client.closed, isTrue);
        },
      );
    }

    for (final status in [401, 403, 429, 503]) {
      test('HTTP $status fails once and closes without retries', () async {
        final client = _TrackingClient(
          (_) async => http.Response('private body', status),
        );
        await expectLater(
          native.searchYoutubeMetadata('music', client: client),
          throwsA(_error(status == 503 ? 'unavailable' : 'blocked')),
        );
        expect(client.calls, 1);
        expect(client.closed, isTrue);
      });
    }

    for (final body in [
      "Sign in to confirm you're not a bot",
      'Our systems have detected unusual traffic from your computer network',
    ]) {
      test('detects bot block in HTTP 200 response', () async {
        final client = _TrackingClient((_) async => http.Response(body, 200));
        await expectLater(
          native.searchYoutubeMetadata('music', client: client),
          throwsA(_error('blocked')),
        );
        expect(client.calls, 1);
        expect(client.closed, isTrue);
      });
    }

    test('does not follow consent redirects', () async {
      final client = _TrackingClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://consent.youtube.com/'},
        ),
      );
      await expectLater(
        native.searchYoutubeMetadata('music', client: client),
        throwsA(_error('consent')),
      );
      expect(client.calls, 1);
      expect(client.closed, isTrue);
    });

    test('malformed page fails safely and closes', () async {
      final client = _TrackingClient(
        (_) async => http.Response('<html>not search data</html>', 200),
      );
      await expectLater(
        native.searchYoutubeMetadata('music', client: client),
        throwsA(_error('metadata')),
      );
      expect(client.calls, 1);
      expect(client.closed, isTrue);
    });

    test('transport failure is safe and not retried', () async {
      final client = _TrackingClient(
        (_) async => throw http.ClientException('private detail'),
      );
      await expectLater(
        native.searchYoutubeMetadata('music', client: client),
        throwsA(_error('connection')),
      );
      expect(client.calls, 1);
      expect(client.closed, isTrue);
    });

    testWidgets('closes stalled native client at 20 seconds', (tester) async {
      final response = Completer<http.Response>();
      final client = _TrackingClient((_) => response.future);
      final assertion = expectLater(
        native.searchYoutubeMetadata('music', client: client),
        throwsA(_error('too long')),
      );
      await tester.pump(const Duration(seconds: 20));
      await assertion;
      expect(client.closed, isTrue);
      expect(client.calls, 1);
      response.complete(http.Response(_searchPage(), 200));
      await tester.pump();
    });
  });
}
