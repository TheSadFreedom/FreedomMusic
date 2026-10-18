import 'package:flutter/material.dart';

import '../models/playlist.dart';
import 'kept_icons.dart';

/// Icon for a system playlist. Color and size come from [IconTheme].
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
        return const FiberNewGlyph();
      case Playlist.kindIncomplete:
        return const ArticleGlyph();
      case Playlist.kindNoProducer:
        return const HeadphonesGlyph();
      case Playlist.kindMissingGenre:
        return const SellGlyph();
      case Playlist.kindMissingLyrics:
        return const LyricsGlyph();
      case Playlist.kindMetadataReady:
        return const TaskAltGlyph();
      case Playlist.kindTrash:
        return const DeleteOutlineRoundedGlyph();
      default:
        return const QueueMusicGlyph();
    }
  }
}
