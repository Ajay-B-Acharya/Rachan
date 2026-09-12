import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/config/youtube_config.dart';
import 'package:harmoniq/models/youtube_video.dart';
import 'package:harmoniq/services/youtube_links.dart';
import 'package:harmoniq/services/youtube_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _id = 'dQw4w9WgXcQ';
const _secondId = 'abcdefghij_';

Map<String, dynamic> _item({
  String id = _id,
  bool search = true,
  bool embeddable = true,
}) => {
  'id': search ? {'kind': 'youtube#video', 'videoId': id} : id,
  'snippet': {
    'title': 'Music &amp; more &#39;live&#39;',
    'channelTitle': 'Music channel',
    'thumbnails': {
      'high': {'url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg'},
      'default': {'url': 'https://i.ytimg.com/vi/$id/default.jpg'},
    },
  },
  if (!search) 'contentDetails': {'duration': 'PT3M32S'},
  if (!search) 'status': {'embeddable': embeddable},
};

http.Response _response(List<Object?> items) =>
    http.Response(jsonEncode({'items': items}), 200);

Matcher _sourceError(String message) => isA<YoutubeSourceException>().having(
  (error) => error.message,
  'message',
  contains(message),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YoutubeVideo', () {
    test('parses search metadata without inventing duration or audio', () {
      final video = YoutubeVideo.fromSearchJson(_item());
      expect(video.id, _id);
      expect(video.title, "Music & more 'live'");
      expect(video.artist, 'Music channel');
      expect(video.thumbnailUrl, 'https://i.ytimg.com/vi/$_id/hqdefault.jpg');
      expect(video.duration, Duration.zero);
    });

    test('constructor defaults duration to zero', () {
      const video = YoutubeVideo(
        id: _id,
        title: 'Title',
        artist: 'Channel',
        thumbnailUrl: '',
      );
      expect(video.duration, Duration.zero);
    });

    test('parses videos.list IDs and ISO 8601 durations', () {
      final item = _item(search: false);
      expect(
        YoutubeVideo.fromSearchJson(item).duration,
        const Duration(minutes: 3, seconds: 32),
      );
      item['contentDetails'] = {'duration': 'P1DT2H3M4.5S'};
      expect(
        YoutubeVideo.fromSearchJson(item).duration,
        const Duration(days: 1, hours: 2, minutes: 3, milliseconds: 4500),
      );
      for (final duration in [null, 123, 'invalid', 'PT0S']) {
        item['contentDetails'] = {'duration': duration};
        expect(YoutubeVideo.fromSearchJson(item).duration, Duration.zero);
      }
    });

    test('handles missing metadata and skips unsafe thumbnail URLs', () {
      final video = YoutubeVideo.fromSearchJson({
        'id': _id,
        'snippet': {
          'title': '  ',
          'channelTitle': 123,
          'thumbnails': {
            'maxres': {'url': 'javascript:alert(1)'},
            'high': {'url': 'https://i.ytimg.com/valid.jpg'},
          },
        },
      });
      expect(video.title, 'Untitled video');
      expect(video.artist, 'Unknown channel');
      expect(video.thumbnailUrl, 'https://i.ytimg.com/valid.jpg');
      expect(YoutubeVideo.fromSearchJson({'id': _id}).thumbnailUrl, '');
    });

    test('decodes entities once and tolerates invalid code points', () {
      final video = YoutubeVideo.fromSearchJson({
        'id': _id,
        'snippet': {'title': '&amp;quot; &#x1F3B5; &#99999999; &#xD800;'},
      });
      expect(video.title, '&quot; \u{1F3B5} &#99999999; &#xD800;');
    });

    test('rejects missing, malformed and non-video IDs', () {
      for (final id in [
        null,
        123,
        'short',
        'bad/videoid',
        {'channelId': _id},
      ]) {
        expect(
          () => YoutubeVideo.fromSearchJson({'id': id}),
          throwsFormatException,
        );
      }
    });
  });

  group('YoutubeService', () {
    test('configuration comes from the build environment', () {
      expect(
        YoutubeConfig.apiKey,
        const String.fromEnvironment('YOUTUBE_API_KEY'),
      );
      expect(YoutubeService.instance, same(YoutubeService.instance));
    });

    test('missing key throws before any network request', () async {
      var calls = 0;
      final service = YoutubeService(
        apiKey: '   ',
        client: MockClient((_) async {
          calls++;
          return _response([]);
        }),
      );
      expect(service.isConfigured, isFalse);
      await expectLater(
        service.search('music'),
        throwsA(_sourceError('YOUTUBE_API_KEY')),
      );
      await expectLater(
        service.search(''),
        throwsA(_sourceError('YOUTUBE_API_KEY')),
      );
      await expectLater(
        service.trending(),
        throwsA(_sourceError('YOUTUBE_API_KEY')),
      );
      expect(calls, 0);
    });

    test('search uses official endpoint and required music filters', () async {
      final service = YoutubeService(
        apiKey: ' test-key ',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'www.googleapis.com');
          expect(request.url.path, '/youtube/v3/search');
          expect(request.url.queryParameters, {
            'key': 'test-key',
            'part': 'snippet',
            'q': 'jazz & blues',
            'type': 'video',
            'videoCategoryId': '10',
            'videoEmbeddable': 'true',
            'videoSyndicated': 'true',
            'maxResults': '12',
          });
          return _response([_item()]);
        }),
      );
      expect(service.isConfigured, isTrue);
      final videos = await service.search('  jazz  &\nblues  ');
      expect(videos.single.id, _id);
      expect(() => videos.clear(), throwsUnsupportedError);
    });

    test('empty and oversized searches avoid requests', () async {
      final service = YoutubeService(
        apiKey: 'test-key',
        client: MockClient((_) async => fail('Unexpected network call')),
      );
      expect(await service.search(' \n '), isEmpty);
      await expectLater(
        service.search('x' * 501),
        throwsA(_sourceError('500')),
      );
    });

    test(
      'trending is public mostPopular music and filters embed status',
      () async {
        final service = YoutubeService(
          apiKey: 'test-key',
          client: MockClient((request) async {
            expect(request.url.path, '/youtube/v3/videos');
            expect(request.url.queryParameters, {
              'key': 'test-key',
              'part': 'snippet,contentDetails,status',
              'chart': 'mostPopular',
              'videoCategoryId': '10',
              'maxResults': '12',
            });
            return _response([
              _item(search: false),
              _item(id: _secondId, search: false, embeddable: false),
              {'id': '12345678901', 'snippet': {}},
            ]);
          }),
        );
        final videos = await service.trending();
        expect(videos.map((video) => video.id), [_id]);
        expect(videos.single.duration, const Duration(seconds: 212));
      },
    );

    test('skips malformed items and duplicate IDs', () async {
      final service = YoutubeService(
        apiKey: 'test-key',
        client: MockClient(
          (_) async => _response([
            null,
            17,
            {},
            {
              'id': {'channelId': _id},
            },
            _item(),
            _item(),
            _item(id: _secondId),
          ]),
        ),
      );
      expect((await service.search('music')).map((v) => v.id), [
        _id,
        _secondId,
      ]);
    });

    test('caps returned results at twelve', () async {
      final service = YoutubeService(
        apiKey: 'test-key',
        client: MockClient(
          (_) async => _response([
            for (var i = 0; i < 20; i++)
              _item(id: i.toString().padLeft(11, '0')),
          ]),
        ),
      );
      expect(await service.search('music'), hasLength(12));
    });

    test(
      'deduplicates pending normalized searches and caches results',
      () async {
        var calls = 0;
        final response = Completer<http.Response>();
        final service = YoutubeService(
          apiKey: 'test-key',
          client: MockClient((_) {
            calls++;
            return response.future;
          }),
        );
        final first = service.search(' jazz   music ');
        final second = service.search('jazz music');
        response.complete(_response([_item()]));
        expect(await first, same(await second));
        expect(await service.search('jazz music'), same(await first));
        expect(calls, 1);
      },
    );

    test(
      'forceRefresh bypasses cached trending but deduplicates refreshes',
      () async {
        var calls = 0;
        final refresh = Completer<http.Response>();
        final service = YoutubeService(
          apiKey: 'test-key',
          client: MockClient((_) async {
            calls++;
            return calls == 1
                ? _response([_item(search: false)])
                : refresh.future;
          }),
        );
        await service.trending();
        await service.trending();
        expect(calls, 1);
        final first = service.trending(forceRefresh: true);
        final second = service.trending(forceRefresh: true);
        refresh.complete(_response([_item(id: _secondId, search: false)]));
        expect((await first).single.id, _secondId);
        expect(await first, same(await second));
        expect(calls, 2);
      },
    );

    test('cache evicts least recently used entries at its bound', () async {
      final calls = <String, int>{};
      final service = YoutubeService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          final query = request.url.queryParameters['q']!;
          calls[query] = (calls[query] ?? 0) + 1;
          return _response([]);
        }),
      );
      for (var i = 0; i < 20; i++) {
        await service.search('query$i');
      }
      await service.search('query0');
      await service.search('query20');
      await service.search('query0');
      await service.search('query1');
      expect(calls['query0'], 1);
      expect(calls['query1'], 2);
    });

    test('inflight requests are bounded and capacity recovers', () async {
      final response = Completer<http.Response>();
      final service = YoutubeService(
        apiKey: 'test-key',
        client: MockClient((_) => response.future),
      );
      final pending = [for (var i = 0; i < 8; i++) service.search('query$i')];
      await expectLater(
        service.search('overflow'),
        throwsA(_sourceError('Too many')),
      );
      response.complete(_response([]));
      await Future.wait(pending);
      expect(await service.search('overflow'), isEmpty);
    });

    test(
      'does not cache failures or retain failed inflight requests',
      () async {
        var calls = 0;
        final service = YoutubeService(
          apiKey: 'test-key',
          client: MockClient((_) async {
            calls++;
            return calls == 1
                ? http.Response('unavailable', 503)
                : _response([]);
          }),
        );
        await expectLater(
          service.search('music'),
          throwsA(isA<YoutubeSourceException>()),
        );
        expect(await service.search('music'), isEmpty);
        expect(calls, 2);
      },
    );

    for (final status in [403, 429]) {
      test('maps quota status $status to informative safe error', () async {
        final service = YoutubeService(
          apiKey: 'sensitive-key',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {
                  'message': 'sensitive-key',
                  'errors': [
                    {'reason': 'quotaExceeded'},
                  ],
                },
              }),
              status,
            ),
          ),
        );
        await expectLater(service.trending(), throwsA(_sourceError('quota')));
      });
    }

    for (final status in [400, 401, 403]) {
      test(
        'maps authorization status $status to configuration advice',
        () async {
          final service = YoutubeService(
            apiKey: 'sensitive-key',
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'error': {
                    'message': 'sensitive-key',
                    'details': [
                      {'reason': 'API_KEY_INVALID'},
                    ],
                  },
                }),
                status,
              ),
            ),
          );
          await expectLater(
            service.trending(),
            throwsA(_sourceError('authorization')),
          );
        },
      );
    }

    test(
      'sanitizes transport failures rather than exposing request keys',
      () async {
        final service = YoutubeService(
          apiKey: 'sensitive-key',
          client: MockClient(
            (request) async =>
                throw http.ClientException('sensitive-key', request.url),
          ),
        );
        await expectLater(
          service.search('music'),
          throwsA(
            isA<YoutubeSourceException>()
                .having((e) => e.message, 'message', contains('connection'))
                .having(
                  (e) => e.toString(),
                  'safe message',
                  isNot(contains('sensitive-key')),
                ),
          ),
        );
      },
    );

    for (final body in ['not json', '[]', '{}', '{"items":null}']) {
      test('handles malformed success body $body', () async {
        final service = YoutubeService(
          apiKey: 'test-key',
          client: MockClient((_) async => http.Response(body, 200)),
        );
        await expectLater(
          service.search('music'),
          throwsA(_sourceError('invalid response')),
        );
      });
    }

    testWidgets('times out a stalled request without real waiting', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      final service = YoutubeService(
        apiKey: 'test-key',
        client: MockClient((_) => response.future),
      );
      final assertion = expectLater(
        service.search('music'),
        throwsA(_sourceError('too long')),
      );
      await tester.pump(const Duration(seconds: 13));
      await assertion;
      response.complete(_response([]));
      await tester.pump();
      expect(await service.search('music'), isEmpty);
    });
  });

  group('YoutubeLinks', () {
    test('builds encoded Music URIs and a general YouTube watch fallback', () {
      expect(YoutubeLinks.home.toString(), 'https://music.youtube.com/');
      final search = YoutubeLinks.search('  jazz & blues/#?  ');
      expect(search.scheme, 'https');
      expect(search.host, 'music.youtube.com');
      expect(search.path, '/search');
      expect(search.queryParameters, {'q': 'jazz & blues/#?'});
      expect(
        search.toString(),
        'https://music.youtube.com/search?q=jazz+%26+blues%2F%23%3F',
      );
      expect(search.fragment, isEmpty);
      expect(
        YoutubeLinks.musicWatch(_id).toString(),
        'https://music.youtube.com/watch?v=$_id',
      );
      expect(
        YoutubeLinks.videoIdFromInput(YoutubeLinks.musicWatch(_id).toString()),
        _id,
      );
      expect(
        YoutubeLinks.watch(_id).toString(),
        'https://www.youtube.com/watch?v=$_id',
      );
      expect(() => YoutubeLinks.watch('bad'), throwsArgumentError);
      expect(() => YoutubeLinks.musicWatch('bad'), throwsArgumentError);
    });

    test('accepts strict IDs and supported trusted YouTube URL forms', () {
      for (final input in [
        _id,
        ' $_id ',
        'https://youtube.com/watch?v=$_id',
        'https://www.youtube.com/watch?v=$_id&t=20',
        'http://www.youtube.com/watch?v=$_id',
        'https://music.youtube.com/watch?v=$_id&list=123',
        'https://youtu.be/$_id?si=tracking',
        'youtu.be/$_id',
        'www.youtube.com/watch?v=$_id',
        'https://www.youtube.com/embed/$_id',
        'https://youtube.com/shorts/$_id',
        'https://youtube.com/live/$_id',
        'https://YOUTUBE.COM/watch?v=$_id',
      ]) {
        expect(YoutubeLinks.videoIdFromInput(input), _id, reason: input);
      }
    });

    test('rejects spoofed hosts, unsupported URLs, and invalid IDs', () {
      for (final input in [
        '',
        '123',
        '${_id}x',
        '!!!!!!!!!!!',
        'https://youtube.com.evil.example/watch?v=$_id',
        'https://evilyoutube.com/watch?v=$_id',
        'https://youtu.be.evil.example/$_id',
        'https://evil.example/?v=$_id',
        'https://youtube.com@evil.example/watch?v=$_id',
        'https://evil.example@youtube.com/watch?v=$_id',
        'https://youtube.com:8080/watch?v=$_id',
        'ftp://youtube.com/watch?v=$_id',
        'javascript:$_id',
        'https://youtube.com/redirect?v=$_id',
        'https://youtube.com/playlist?list=$_id',
        'https://youtube.com/watch?v=$_id&v=$_secondId',
        'https://youtu.be/$_id/extra',
        'https://youtu.be/bad',
        'https://youtube.com/watch?v=$_id%0A',
        'https://youtube.com/watch?v=bad%2Fvideoid',
        'https://youtube.com\\@evil.example/watch?v=$_id',
        'https://youtube.com/watch?v=bad id',
        'https://youtube.com/watch?v=%ZZ',
        'https://[invalid/watch?v=$_id',
      ]) {
        expect(YoutubeLinks.videoIdFromInput(input), isNull, reason: input);
      }
    });

  });
}
