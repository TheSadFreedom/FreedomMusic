import 'package:flutter/material.dart';

import '../models/playlist.dart';

/// Icon for a system playlist. Each glyph is a const [Icon] so the release
/// font keeps it.
class SystemPlaylistIcon extends StatelessWidget {
  const SystemPlaylistIcon({
    super.key,
    required this.kind,
    required this.color,
    required this.size,
  });

  final String? kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      data: IconThemeData(color: color, size: size),
      child: _glyph(kind),
    );
  }

  static Widget _glyph(String? kind) {
    switch (kind) {
      case Playlist.kindNew:
        return const Icon(Icons.fiber_new_rounded);
      case Playlist.kindIncomplete:
        return const Icon(Icons.article_outlined);
      case Playlist.kindNoProducer:
        return const Icon(Icons.headphones_rounded);
      case Playlist.kindMissingGenre:
        return const Icon(Icons.sell_outlined);
      case Playlist.kindMissingLyrics:
        return const Icon(Icons.lyrics_outlined);
      case Playlist.kindMetadataReady:
        return const Icon(Icons.task_alt_rounded);
      case Playlist.kindTrash:
        return const Icon(Icons.delete_outline_rounded);
      default:
        return const Icon(Icons.queue_music);
    }
  }
}
