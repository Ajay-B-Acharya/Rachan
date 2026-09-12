import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Only categories and fixed messages leave the classifier, never error text.
enum PlaybackFailure {
  generic,
  network,
  timeout,
  forbidden;

  String message({required bool isYoutube}) => switch (this) {
    forbidden =>
      isYoutube
          ? 'YouTube refused this audio stream (403). Retrying may not help. Choose another track.'
          : 'Unable to access this audio (403). Choose another track.',
    timeout =>
      isYoutube
          ? 'YouTube audio timed out. Please try again.'
          : 'Audio playback timed out. Please try again.',
    network =>
      isYoutube
          ? 'Unable to connect to YouTube audio. Check your connection and try again.'
          : 'Unable to connect to this audio. Check your connection and try again.',
    generic =>
      isYoutube
          ? 'YouTube audio is unavailable. Please try again.'
          : 'Unable to play this audio. Please try again.',
  };
}

final _url = RegExp(r'\b[a-z][a-z0-9+.-]*://[^\s]+', caseSensitive: false);
final _forbidden = RegExp(r'\bResponse code:\s*403\b', caseSensitive: false);
final _timeout = RegExp(
  r'\b(timed out|timeout|TimeoutException|SocketTimeoutException)\b',
  caseSensitive: false,
);
final _network = RegExp(
  r'\b(SocketException|UnknownHostException|network_error|network error|'
  r'failed host lookup|network is unreachable|connection refused|connection reset)\b',
  caseSensitive: false,
);

/// Exo's player code (often 0 for a source error) is not an HTTP status.
/// Inspect explicit status fields and known phrases, excluding URLs entirely.
PlaybackFailure classifyPlaybackFailure(Object? error) {
  var failure = PlaybackFailure.generic;

  void record(PlaybackFailure candidate) {
    if (candidate.index > failure.index) failure = candidate;
  }

  void inspect(Object? value, int depth) {
    // Platform details can be nested; bound traversal even for cyclic maps.
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
        if ((key == 'responseCode' || key == 'statusCode') &&
            (nested == 403 || nested == '403')) {
          record(PlaybackFailure.forbidden);
        } else if (nested is Map ||
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
      if (_forbidden.hasMatch(text)) record(PlaybackFailure.forbidden);
      if (_timeout.hasMatch(text)) record(PlaybackFailure.timeout);
      if (_network.hasMatch(text)) record(PlaybackFailure.network);
    }
  }

  inspect(error, 0);
  return failure;
}
