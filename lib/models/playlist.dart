import 'song.dart';

class Playlist {
  final int id;
  final String name;
  final List<Song> songs;
  final int gradientId;

  const Playlist({
    required this.id,
    required this.name,
    required this.songs,
    required this.gradientId,
  });

  Playlist copyWith({
    int? id,
    String? name,
    List<Song>? songs,
    int? gradientId,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      gradientId: gradientId ?? this.gradientId,
    );
  }
}
