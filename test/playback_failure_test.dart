import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/services/playback_failure.dart';
import 'package:just_audio/just_audio.dart';

const signedUrl =
    'https://rr1.googlevideo.com/videoplayback?expire=123&sig=secret403token';

void main() {
  test('Exo code 0 source errors preserve nested HTTP evidence', () {
    final errors = <Object>[
      PlayerException(0, 'Source error', {
        'index': 0,
        'originalError': {
          'message': 'Source error',
          'cause': {
            'type': 'HttpDataSource.InvalidResponseCodeException',
            'responseCode': 403,
            'url': signedUrl,
          },
        },
      }),
      PlayerException(0, 'Source error', {
        'originalError': {
          'cause': {
            'http': {'statusCode': '403', 'url': signedUrl},
          },
        },
      }),
      PlayerException(0, 'Source error', {
        'originalError': {
          'cause':
              'HttpDataSource.InvalidResponseCodeException: '
              'Response code: 403 $signedUrl',
        },
      }),
      PlayerException(0, 'Source error: Response code: 403 $signedUrl'),
      PlatformException(
        code: '0',
        message: 'Source error',
        details: {
          'originalError': {
            'cause': {'responseCode': 403},
          },
        },
      ),
      PlatformException(
        code: '0',
        message: 'Source error: Response code: 403 $signedUrl',
      ),
      Exception('Response code: 403 $signedUrl'),
      {
        'http': {'responseCode': 403},
      },
    ];
    for (final error in errors) {
      final failure = classifyPlaybackFailure(error);
      expect(failure, PlaybackFailure.forbidden);
      expect(
        failure.message(isYoutube: true),
        'YouTube refused this audio stream (403). Retrying may not help. '
        'Choose another track.',
      );
    }
  });

  test('bare player codes and URL tokens are not HTTP status evidence', () {
    final errors = <Object?>[
      null,
      PlayerException(0, 'Source error'),
      PlayerException(403, 'Source error'),
      PlatformException(code: '403', message: 'Source error'),
      PlayerException(0, 'Source error $signedUrl'),
      PlayerException(0, 'Source error', {
        'originalError': {
          'cause': {'url': signedUrl, 'token': '403', 'index': 403},
        },
      }),
      StateError(signedUrl),
      Exception('Source error: Response code: 4030'),
      Exception('Source error: Response code: 404'),
      Exception('https://audio.example/Response%20code:%20403?token=secret'),
      Exception('https://audio.example/?token=TimeoutException403'),
      {'responseCode': signedUrl, 'statusCode': '403token'},
    ];
    for (final error in errors) {
      expect(classifyPlaybackFailure(error), PlaybackFailure.generic);
    }
  });

  test('timeout errors have explicit retry guidance', () {
    final errors = <Object>[
      TimeoutException(signedUrl),
      PlayerException(0, 'Source error', {
        'originalError': {
          'cause': 'java.net.SocketTimeoutException: $signedUrl',
        },
      }),
      PlatformException(code: 'timeout', message: signedUrl),
      Exception('Connection timed out $signedUrl'),
    ];
    for (final error in errors) {
      final failure = classifyPlaybackFailure(error);
      expect(failure, PlaybackFailure.timeout);
      expect(
        failure.message(isYoutube: true),
        'YouTube audio timed out. Please try again.',
      );
    }
  });

  test('recognized network errors are distinct from generic source errors', () {
    for (final error in <Object>[
      PlatformException(code: 'network_error', message: signedUrl),
      PlayerException(0, 'Source error', {
        'originalError': {'cause': 'java.net.UnknownHostException: $signedUrl'},
      }),
      Exception('SocketException: Failed host lookup: $signedUrl'),
    ]) {
      expect(classifyPlaybackFailure(error), PlaybackFailure.network);
    }
  });

  test('explicit forbidden evidence takes precedence over timeout text', () {
    expect(
      classifyPlaybackFailure(
        PlayerException(0, 'Connection timed out', {
          'originalError': {'statusCode': 403},
        }),
      ),
      PlaybackFailure.forbidden,
    );
  });

  test('cyclic platform details do not recurse indefinitely', () {
    final details = <String, dynamic>{};
    details['cause'] = details;
    expect(
      classifyPlaybackFailure(PlayerException(0, 'Source error', details)),
      PlaybackFailure.generic,
    );
  });

  test('messages are fixed and local failures never claim YouTube', () {
    for (final failure in PlaybackFailure.values) {
      for (final isYoutube in [true, false]) {
        final message = failure.message(isYoutube: isYoutube);
        expect(message, isNot(contains('secret')));
        expect(message, isNot(contains('https://')));
        expect(message, isNot(contains('googlevideo')));
        if (!isYoutube) expect(message, isNot(contains('YouTube')));
      }
    }
    expect(
      PlaybackFailure.timeout.message(isYoutube: false),
      'Audio playback timed out. Please try again.',
    );
  });
}
