import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/services/audio_service.dart';
import 'package:harmoniq/services/online_music_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_service_test.dart' show TestAudioPlayer, localSong, flush;

Map<String, dynamic> track([String id = 'gzgj5vl']) => {
  'id': id,
  'title': 'Full Song',
  'user': {'name': 'Artist'},
  'duration': 239,
  'is_streamable': true,
  'is_available': true,
  'is_delete': false,
  'is_unlisted': false,
  'is_stream_gated': false,
  'stream_conditions': null,
  'access': {'stream': true},
  'artwork': {'480x480': 'https://art.example/cover.jpg'},
  'created_at': '2026-01-02T03:04:05Z',
};

http.Response payload(Object? data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

Matcher fails(OnlineMusicFailure kind) =>
    throwsA(isA<OnlineMusicException>().having((e) => e.kind, 'kind', kind));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audius model', () {
    test(
      'parses seconds, safe artwork and opaque identity, not timestamps',
      () {
        final song = Song.fromAudius(track());
        expect(song.source, SongSource.online);
        expect(song.providerId, 'gzgj5vl');
        expect(song.id, 0);
        expect(song.identity, 'online:audius:gzgj5vl');
        expect(song.audioPath, '');
        expect(song.duration, const Duration(seconds: 239));
        expect(song.albumArtUrl, 'https://art.example/cover.jpg');
        expect(
          Song.fromAudius({...track(), 'duration': 1.25}).duration,
          const Duration(milliseconds: 1250),
        );
        final malformedTime = Song.fromAudius({
          ...track(),
          'created_at': 'not a timestamp',
          'updated_at': 123,
          'artwork': {'1000x1000': 'http://unsafe.example/image'},
        });
        expect(malformedTime.duration, song.duration);
        expect(malformedTime.albumArtUrl, isNull);
      },
    );

    test('strictly rejects restricted, preview-only and malformed entries', () {
      final rejected = <Map<String, dynamic>>[
        {'is_streamable': false},
        {'is_streamable': null},
        {'is_streamable': 'true'},
        {'is_available': false},
        {'is_delete': true},
        {'is_delete': null},
        {'is_unlisted': true},
        {'is_stream_gated': true},
        {'is_stream_gated': null},
        {
          'access': {'stream': false},
        },
        {'access': {}},
        {'access': true},
        {
          'stream_conditions': {
            'usdc_purchase': {'price': 1},
          },
        },
        {
          'stream_conditions': {'follow_user_id': 42},
        },
        {'stream_conditions': 'unknown'},
        {'preview_only': true},
        {'is_preview_only': true},
        {'is_preview': true},
        {
          'allowed_api_keys': ['private-key'],
        },
        {
          'access_authorities': ['restricted'],
        },
        {'duration': 0},
        {'duration': -1},
        {'duration': '239'},
        {'duration': double.nan},
        {'duration': double.infinity},
        {'duration': 86401},
        {'id': 12},
        {'id': ''},
        {'id': '../secret'},
        {'id': 'abc\n'},
        {'id': 'a' * 65},
      ];
      for (final change in rejected) {
        expect(
          () => Song.fromAudius({...track(), ...change}),
          throwsFormatException,
          reason: '$change',
        );
      }
      expect(
        Song.fromAudius({...track(), 'preview_cid': 'not-audio-url'}).audioPath,
        '',
      );
      expect(
        Song.fromAudius({...track(), 'access': null}).providerId,
        'gzgj5vl',
      );
    });

    test('persistence avoids redirects, integer collisions and unsafe IDs', () {
      final first = Song.fromAudius(track('Aa1'));
      final second = Song.fromAudius(track('BB2'));
      expect({first, second, localSong()}, hasLength(3));
      expect(first, first.copyWith(id: 876, title: 'Updated'));
      expect(first.hashCode, first.copyWith(id: 876).hashCode);
      final saved = first
          .copyWith(
            isFavorite: true,
            audioPath: 'https://cdn.example/audio?secret=expired',
          )
          .toJson();
      expect(jsonEncode(saved), isNot(contains('secret')));
      expect(saved['audioPath'], '');
      final restored = Song.fromJson(saved);
      expect(restored, first);
      expect(restored.isFavorite, isTrue);
      expect(restored.providerId, 'Aa1');
      expect(restored.id, 0);
      expect(
        Song.fromJson({...saved, 'providerId': '../bad'}).source,
        SongSource.legacy,
      );
      expect(Song.fromJson({...saved, 'providerId': 42}).providerId, isNull);
      for (final source in ['youtube', 'jamendo']) {
        expect(
          Song.fromJson({...saved, 'source': source}).source,
          SongSource.legacy,
        );
      }
      final a = Song.fromJson({
        ...saved,
        'source': 'youtube',
        'videoId': 'oldA',
      });
      final b = Song.fromJson({
        ...saved,
        'source': 'youtube',
        'videoId': 'oldB',
      });
      expect(a, isNot(b));
      expect(Song.fromJson(a.toJson()), a);
    });
  });

  group('Discovery and resolution', () {
    test(
      'official HTTPS, Accept JSON, trimmed encoded query and optional key',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return payload([track()]);
        });
        final service = OnlineMusicService(client: client, apiKey: '');
        expect(await service.search('   '), isEmpty);
        expect(requests, isEmpty);
        expect(await service.search('  jazz & café/+?  '), hasLength(1));
        final request = requests.single;
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'api.audius.co');
        expect(request.url.path, '/v1/tracks/search');
        expect(request.url.queryParameters['query'], 'jazz & café/+?');
        expect(request.url.queryParameters['app_name'], 'Harmoniq');
        expect(request.url.queryParameters.containsKey('api_key'), isFalse);
        expect(request.headers['Accept'], 'application/json');
        expect(request.followRedirects, isFalse);
        final keyed = OnlineMusicService(
          client: client,
          apiKey: ' test-public-key ',
        );
        await keyed.trending();
        expect(requests.last.url.queryParameters['api_key'], 'test-public-key');
        expect(
          requests.last.headers.keys.map((s) => s.toLowerCase()),
          isNot(contains('authorization')),
        );
      },
    );

    test(
      'filters gated tracks and deduplicates opaque IDs in API order',
      () async {
        final service = OnlineMusicService(
          client: MockClient(
            (_) async => payload([
              track('one'),
              {...track('gated'), 'is_stream_gated': true},
              track('two'),
              {...track('one'), 'title': 'Updated'},
              'malformed',
            ]),
          ),
        );
        final songs = await service.trending();
        expect(songs.map((s) => s.providerId), ['one', 'two']);
        expect(songs.first.title, 'Updated');
        expect(() => songs.clear(), throwsUnsupportedError);
      },
    );

    test(
      'deduplicates inflight, expires at five minutes and supports refresh',
      () async {
        var now = DateTime.utc(2026);
        var requests = 0;
        final gate = Completer<http.Response>();
        final service = OnlineMusicService(
          now: () => now,
          client: MockClient((_) {
            requests++;
            return requests == 1
                ? gate.future
                : Future.value(payload([track()]));
          }),
        );
        final first = service.trending();
        final simultaneous = service.trending(refresh: true);
        gate.complete(payload([track()]));
        await Future.wait([first, simultaneous]);
        expect(requests, 1);
        now = now.add(const Duration(minutes: 4, seconds: 59));
        await service.trending();
        expect(requests, 1);
        now = now.add(const Duration(seconds: 1));
        await service.trending();
        expect(requests, 2);
        await service.trending(refresh: true);
        expect(requests, 3);
      },
    );

    test(
      'bounds cache at 20 entries and promotes recently used results',
      () async {
        var requests = 0;
        final service = OnlineMusicService(
          client: MockClient((_) async {
            requests++;
            return payload([]);
          }),
        );
        for (var i = 0; i < 20; i++) {
          await service.search('query$i');
        }
        await service.search('query0');
        await service.search('query20');
        await service.search('query0');
        expect(requests, 21);
        await service.search('query1');
        expect(requests, 22);
      },
    );

    test(
      'revalidates object detail on each load, returns only official endpoint',
      () async {
        var requests = 0;
        final service = OnlineMusicService(
          client: MockClient((request) async {
            requests++;
            expect(request.url.path, '/v1/tracks/gzgj5vl');
            return payload(track());
          }),
        );
        final uri = await service.streamUri('gzgj5vl');
        expect(
          uri.toString(),
          'https://api.audius.co/v1/tracks/gzgj5vl/stream?app_name=Harmoniq',
        );
        await service.streamUri('gzgj5vl');
        expect(requests, 2);
        await expectLater(
          service.streamUri('../bad'),
          fails(OnlineMusicFailure.invalidTrack),
        );
        expect(requests, 2);
      },
    );

    test(
      'cached discovery cannot authorize newly gated or mismatched details',
      () async {
        var details = {...track(), 'is_stream_gated': true};
        final service = OnlineMusicService(
          client: MockClient(
            (request) async => payload(
              request.url.path.endsWith('trending') ? [track()] : details,
            ),
          ),
        );
        await service.trending();
        await expectLater(
          service.streamUri('gzgj5vl'),
          fails(OnlineMusicFailure.invalidTrack),
        );
        details = track('different');
        await expectLater(
          service.streamUri('gzgj5vl'),
          fails(OnlineMusicFailure.invalidTrack),
        );
      },
    );

    test(
      'empty results are not an error; failures are sanitized and retriable',
      () async {
        var response = http.Response(
          'secret https://private.example?api_key=private',
          503,
        );
        var requests = 0;
        final service = OnlineMusicService(
          client: MockClient((_) async {
            requests++;
            return response;
          }),
        );
        for (final entry in {
          401: OnlineMusicFailure.authentication,
          403: OnlineMusicFailure.authentication,
          404: OnlineMusicFailure.invalidTrack,
          410: OnlineMusicFailure.invalidTrack,
          429: OnlineMusicFailure.rateLimited,
          503: OnlineMusicFailure.unavailable,
          302: OnlineMusicFailure.unavailable,
        }.entries) {
          response = http.Response('secret', entry.key);
          await expectLater(service.trending(), fails(entry.value));
        }
        expect(requests, 7, reason: 'No automatic retries or cached failures');
        response = payload([]);
        expect(await service.trending(), isEmpty);
        expect(requests, 8);
        for (final kind in OnlineMusicFailure.values) {
          expect(
            OnlineMusicException(kind).toString(),
            isNot(contains('secret')),
          );
        }
      },
    );

    test(
      'malformed metadata, network errors and timeouts remain distinct',
      () async {
        for (final response in [
          http.Response('<html>private</html>', 200),
          payload(null),
          payload({}),
          http.Response('{}', 200),
        ]) {
          final service = OnlineMusicService(
            client: MockClient((_) async => response),
          );
          await expectLater(
            service.trending(),
            fails(OnlineMusicFailure.invalidResponse),
          );
        }
        final offline = OnlineMusicService(
          client: MockClient((_) async {
            throw http.ClientException('private URL');
          }),
        );
        await expectLater(
          offline.trending(),
          fails(OnlineMusicFailure.offline),
        );
        final timeout = OnlineMusicService(
          client: MockClient((_) async {
            throw TimeoutException('private URL');
          }),
        );
        await expectLater(
          timeout.trending(),
          fails(OnlineMusicFailure.timeout),
        );
      },
    );

    testWidgets('a hanging request times out after ten seconds', (
      tester,
    ) async {
      final gate = Completer<http.Response>();
      final service = OnlineMusicService(
        client: MockClient((_) => gate.future),
      );
      final expectation = expectLater(
        service.trending(),
        fails(OnlineMusicFailure.timeout),
      );
      await tester.pump(const Duration(seconds: 11));
      await expectation;
      gate.complete(payload([]));
      await tester.pump();
    });
  });

  group('Online playback', () {
    late TestAudioPlayer player;
    AudioService? audio;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      player = TestAudioPlayer();
    });
    tearDown(() async {
      audio?.dispose();
      audio = null;
      await flush();
    });

    test(
      'resolves by provider ID, supplies artwork and retries fresh',
      () async {
        final resolved = <String>[];
        audio = AudioService(
          audioPlayer: player,
          resolveOnlineAudio: (id) async {
            resolved.add(id);
            return Uri.https('api.audius.co', '/v1/tracks/$id/stream');
          },
        );
        await flush();
        final song = Song.fromAudius(track());
        await audio!.playSong(song, contextQueue: [song, localSong()]);
        expect(resolved, ['gzgj5vl']);
        expect(player.sources.single.uri.scheme, 'https');
        final media = player.sources.single.tag as MediaItem;
        expect(media.id, song.identity);
        expect(media.artUri.toString(), song.albumArtUrl);
        player.events.addError(
          PlayerException(0, 'FileNotFoundException private-url'),
        );
        expect(audio!.playbackError, contains('online audio stream'));
        expect(audio!.playbackError, isNot(contains('local audio')));
        await audio!.retryPlayback();
        expect(resolved, ['gzgj5vl', 'gzgj5vl']);
        expect(audio!.isPlaying, isTrue);
        await audio!.next();
        expect(audio!.currentSong!.source, SongSource.local);
      },
    );

    test(
      'late online resolution cannot replace a newer local selection',
      () async {
        final gate = Completer<Uri>();
        audio = AudioService(
          audioPlayer: player,
          resolveOnlineAudio: (_) => gate.future,
        );
        final pending = audio!.playSong(Song.fromAudius(track()));
        await audio!.playSong(localSong());
        gate.complete(Uri.https('audio.example', '/old.mp3'));
        await pending;
        expect(player.sources, hasLength(1));
        expect(audio!.currentSong, localSong());
        expect(audio!.playbackError, isNull);
      },
    );

    test(
      'stop cancels resolution and resolver errors support explicit retry',
      () async {
        final gate = Completer<Uri>();
        var calls = 0;
        audio = AudioService(
          audioPlayer: player,
          resolveOnlineAudio: (_) {
            calls++;
            if (calls == 1) return gate.future;
            if (calls == 2) {
              throw const OnlineMusicException(OnlineMusicFailure.offline);
            }
            return Future.value(Uri.https('audio.example', '/full.mp3'));
          },
        );
        final song = Song.fromAudius(track());
        final pending = audio!.playSong(song);
        await audio!.stopAndClear();
        gate.complete(Uri.https('audio.example', '/old.mp3'));
        await pending;
        expect(player.sources, isEmpty);
        expect(audio!.currentSong, isNull);
        await audio!.playSong(song);
        expect(audio!.playbackError, contains('internet connection'));
        expect(calls, 2);
        await audio!.retryPlayback();
        expect(calls, 3);
        expect(audio!.isPlaying, isTrue);
      },
    );

    test(
      'rejects non-HTTPS resolution, invalid IDs and arbitrary remote locals',
      () async {
        var calls = 0;
        audio = AudioService(
          audioPlayer: player,
          resolveOnlineAudio: (_) async {
            calls++;
            return Uri.parse('http://audio.example/unsafe.mp3');
          },
        );
        final song = Song.fromAudius(track());
        await audio!.playSong(song);
        expect(audio!.playbackError, contains('full streaming'));
        expect(player.sources, isEmpty);
        await audio!.playSong(song.copyWith(providerId: '../bad'));
        await audio!.playSong(
          localSong().copyWith(audioPath: 'https://audio.example/file'),
        );
        expect(calls, 1);
        expect(player.sources, isEmpty);
      },
    );

    test(
      'online favorites retain IDs across persistence and remain distinct',
      () async {
        audio = AudioService(
          audioPlayer: player,
          resolveOnlineAudio: (_) async =>
              Uri.https('audio.example', '/full.mp3'),
        );
        await flush();
        final songs = [
          Song.fromAudius(track('first')),
          Song.fromAudius(track('second')),
          localSong(),
        ];
        for (final song in songs) {
          audio!.toggleFavorite(song);
        }
        await flush();
        final prefs = await SharedPreferences.getInstance();
        final restored = prefs
            .getStringList('harmoniq_favorites_v1')!
            .map((s) => Song.fromJson(jsonDecode(s)))
            .toSet();
        expect(restored, hasLength(3));
        expect(restored, containsAll(songs));
        expect(
          restored
              .where((s) => s.source == SongSource.online)
              .every((s) => s.audioPath.isEmpty),
          isTrue,
        );
      },
    );
  });
}
