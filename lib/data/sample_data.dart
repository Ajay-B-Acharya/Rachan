import '../models/song.dart';
import '../models/playlist.dart';

class SampleData {
  static const List<Song> songs = [
    Song(
      id: 0,
      title: "Midnight Drive",
      artist: "Rayan",
      album: "Retro Dreams",
      duration: Duration(minutes: 3, seconds: 42),
      audioPath: "simulated_midnight_drive.mp3",
      gradientId: 0,
    ),
    Song(
      id: 1,
      title: "Afterglow",
      artist: "Nova",
      album: "Ethereal Light",
      duration: Duration(minutes: 4, seconds: 15),
      audioPath: "simulated_afterglow.mp3",
      gradientId: 1,
    ),
    Song(
      id: 2,
      title: "Lost in Time",
      artist: "Aero",
      album: "Chronicles",
      duration: Duration(minutes: 3, seconds: 10),
      audioPath: "simulated_lost_in_time.mp3",
      gradientId: 2,
    ),
    Song(
      id: 3,
      title: "Neon Skies",
      artist: "Veyra",
      album: "Cyber City",
      duration: Duration(minutes: 2, seconds: 58),
      audioPath: "simulated_neon_skies.mp3",
      gradientId: 3,
    ),
    Song(
      id: 4,
      title: "Ocean Lights",
      artist: "Luna",
      album: "Deep Blue",
      duration: Duration(minutes: 5, seconds: 2),
      audioPath: "simulated_ocean_lights.mp3",
      gradientId: 4,
    ),
    Song(
      id: 5,
      title: "Slow Motion",
      artist: "Kairo",
      album: "Low-Fi Vibe",
      duration: Duration(minutes: 3, seconds: 35),
      audioPath: "simulated_slow_motion.mp3",
      gradientId: 5,
    ),
    Song(
      id: 6,
      title: "Dreamscape",
      artist: "Elara",
      album: "Fantasy",
      duration: Duration(minutes: 4, seconds: 40),
      audioPath: "simulated_dreamscape.mp3",
      gradientId: 6,
    ),
    Song(
      id: 7,
      title: "Night Runner",
      artist: "Zayn",
      album: "Outrun",
      duration: Duration(minutes: 3, seconds: 12),
      audioPath: "simulated_night_runner.mp3",
      gradientId: 7,
    ),
  ];

  static List<Playlist> getPlaylists(List<Song> songList) {
    return [
      Playlist(
        id: 0,
        name: "Late Night",
        songs: [songList[0], songList[3], songList[7]],
        gradientId: 0,
      ),
      Playlist(
        id: 1,
        name: "Chill Mode",
        songs: [songList[1], songList[4], songList[5]],
        gradientId: 1,
      ),
      Playlist(
        id: 2,
        name: "Workout",
        songs: [songList[3], songList[7], songList[2]],
        gradientId: 5,
      ),
      Playlist(
        id: 3,
        name: "Focus",
        songs: [songList[2], songList[5], songList[6]],
        gradientId: 7,
      ),
    ];
  }
}
