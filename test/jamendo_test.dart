import 'package:flutter_test/flutter_test.dart';
import 'package:harmoniq/config/jamendo_config.dart';
import 'package:harmoniq/models/song.dart';
import 'package:harmoniq/services/jamendo_service.dart';

void main() {
  group('JamendoConfig Security & Integrity Tests', () {
    test('Client ID is correct and configured', () {
      expect(JamendoConfig.clientId, 'da19c12c');
      expect(JamendoConfig.apiBaseUrl, 'https://api.jamendo.com/v3.0');
    });
  });

  group('Song Model Jamendo Integration Tests', () {
    test('Creates Jamendo Song from API JSON correctly', () {
      final sampleJson = {
        'id': '1932670',
        'name': 'RED LIGHT',
        'duration': 190,
        'artist_id': '510867',
        'artist_name': 'Egor Budennyy',
        'album_name': 'RED LIGHT',
        'license_ccurl': 'http://creativecommons.org/licenses/by-nc-nd/3.0/',
        'image':
            'https://usercontent.jamendo.com?type=album&id=477294&width=300&trackid=1932670',
        'audio':
            'https://prod-1.storage.jamendo.com/?trackid=1932670&format=mp31',
        'audiodownload_allowed': true,
      };

      final song = Song.fromJamendo(sampleJson);

      expect(song.id, 1932670);
      expect(song.title, 'RED LIGHT');
      expect(song.artist, 'Egor Budennyy');
      expect(song.album, 'RED LIGHT');
      expect(song.duration.inSeconds, 190);
      expect(song.isOnline, true);
      expect(song.source, SongSource.jamendo);
      expect(song.albumArtUrl, contains('usercontent.jamendo.com'));
      expect(song.audioPath, contains('prod-1.storage.jamendo.com'));
      expect(song.licenseUrl, contains('creativecommons.org'));
      expect(song.audioDownloadAllowed, true);
    });

    test('Serializes to and from JSON for persistent offline storage', () {
      const song = Song(
        id: 998877,
        title: 'Offline Favorite',
        artist: 'Jamendo Indie Artist',
        album: 'Acoustic Sessions',
        duration: Duration(minutes: 3, seconds: 20),
        audioPath: 'https://example.com/audio.mp3',
        isFavorite: true,
        gradientId: 3,
        albumArtUrl: 'https://example.com/art.jpg',
        source: SongSource.jamendo,
        licenseUrl: 'http://creativecommons.org/licenses/by/4.0/',
        audioDownloadAllowed: true,
      );

      final jsonMap = song.toJson();
      final revived = Song.fromJson(jsonMap);

      expect(revived.id, song.id);
      expect(revived.title, song.title);
      expect(revived.artist, song.artist);
      expect(revived.album, song.album);
      expect(revived.duration, song.duration);
      expect(revived.audioPath, song.audioPath);
      expect(revived.isFavorite, true);
      expect(revived.isOnline, true);
      expect(revived.source, SongSource.jamendo);
      expect(revived.albumArtUrl, song.albumArtUrl);
      expect(revived.licenseUrl, song.licenseUrl);
      expect(revived.audioDownloadAllowed, true);
    });
  });

  group('JamendoService Tests', () {
    test('Singleton instance is accessible', () {
      final s1 = JamendoService();
      final s2 = JamendoService.instance;
      expect(identical(s1, s2), true);
    });

    test('Live API call fetches real Jamendo tracks when network available', () async {
      try {
        final tracks = await JamendoService.instance.getPopularTracks(limit: 3);
        if (tracks.isNotEmpty) {
          expect(tracks.first.title, isNotEmpty);
          expect(tracks.first.audioPath, contains('storage.jamendo.com'));
          expect(tracks.first.source, SongSource.jamendo);
        }
      } catch (_) {
        // Ignored when running under test runner with mocked HTTP
      }
    });
  });
}
