import 'youtube_audio_stub.dart'
    if (dart.library.io) 'youtube_audio_native.dart'
    as platform;

/// Resolves an ephemeral audio-only URL. Never store the result in a Song.
Future<Uri> resolveYoutubeAudio(String videoId) =>
    platform.resolveYoutubeAudio(videoId);
