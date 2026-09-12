import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Only categories and fixed messages leave the classifier, never error text.
enum PlaybackFailure {
  generic,
  timeout,
  unavailable,
  onlineUnavailable;

  String message() => switch (this) {
    generic => 'Unable to play this audio. Please try again.',
    timeout => 'Audio playback timed out. Please try again.',
    unavailable =>
      'This local audio file is missing or cannot be accessed. '
          'Check the file and storage permission.',
    onlineUnavailable => 'The online audio stream is unavailable. Check your connection or try another song.',
  };
}

final _url = RegExp(r'\b[a-z][a-z0-9+.-]*://[^\s]+', caseSensitive: false);
final _timeout = RegExp(
  r'\b(timed out|timeout|TimeoutException)\b',
  caseSensitive: false,
);
final _unavailable = RegExp(
  r'\b(FileNotFoundException|SecurityException|ENOENT|EACCES|'
  r'permission_denied|permission denied|access denied|'
  r'no such file|file not found)\b',
  caseSensitive: false,
);

PlaybackFailure classifyPlaybackFailure(Object? error, {bool online = false}) {
  var failure = PlaybackFailure.generic;

  void record(PlaybackFailure candidate) {
    if (candidate.index > failure.index) failure = candidate;
  }

  void inspect(Object? value, int depth) {
    // Bound traversal even for cyclic platform details.
    if (value == null || depth > 16) return;
    if (value is TimeoutException) {
      record(PlaybackFailure.timeout);
    } else if (value is PlayerException) {
      inspect(value.message, depth + 1);
      inspect(value.details, depth + 1);
    } else if (value is PlatformException) {
      inspect(value.code, depth + 1);
      inspect(value.message, depth + 1);
      inspect(value.details, depth + 1);
    } else if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key;
        final nested = entry.value;
        if (nested is Map ||
            nested is List ||
            key == 'originalError' ||
            key == 'cause' ||
            key == 'error' ||
            key == 'details' ||
            key == 'message' ||
            key == 'code' ||
            key == 'type') {
          inspect(nested, depth + 1);
        }
      }
    } else if (value is List) {
      for (final nested in value) {
        inspect(nested, depth + 1);
      }
    } else {
      final text = value.toString().replaceAll(_url, '');
      if (_timeout.hasMatch(text)) record(PlaybackFailure.timeout);
      if (_unavailable.hasMatch(text)) record(PlaybackFailure.unavailable);
    }
  }

  inspect(error, 0);
  return online && failure != PlaybackFailure.timeout
      ? PlaybackFailure.onlineUnavailable
      : failure;
}
