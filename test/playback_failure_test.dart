import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/services/playback_failure.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  test('timeouts have fixed local guidance', () {
    expect(
      classifyPlaybackFailure(TimeoutException('private details')),
      PlaybackFailure.timeout,
    );
    expect(
      PlaybackFailure.timeout.message(),
      'Audio playback timed out. Please try again.',
    );
  });

  test('missing files are unavailable', () {
    expect(
      classifyPlaybackFailure(
        PlayerException(0, 'FileNotFoundException: private path'),
      ),
      PlaybackFailure.unavailable,
    );
  });

  test('generic failures do not expose paths', () {
    final error = PlatformException(
      code: '0',
      message: 'Source error',
      details: '/private/music/file.mp3',
    );
    expect(classifyPlaybackFailure(error), PlaybackFailure.generic);
    for (final failure in PlaybackFailure.values) {
      expect(failure.message(), isNot(contains('/private')));
    }
  });
}
