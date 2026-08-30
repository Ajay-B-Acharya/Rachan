class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String audioPath;
  final bool isFavorite;
  final int gradientId;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.audioPath,
    this.isFavorite = false,
    required this.gradientId,
  });

  Song copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? audioPath,
    bool? isFavorite,
    int? gradientId,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      audioPath: audioPath ?? this.audioPath,
      isFavorite: isFavorite ?? this.isFavorite,
      gradientId: gradientId ?? this.gradientId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
