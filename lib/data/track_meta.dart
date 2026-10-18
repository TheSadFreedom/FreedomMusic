import '../models/track.dart';
import 'track_key.dart';

/// Which system lists a track belongs to after a metadata check.
class TrackMetaGaps {
  const TrackMetaGaps({
    required this.core,
    required this.producer,
    required this.genre,
    required this.lyrics,
  });

  /// Cover, title, artist, album, album artist, year, number, total, or disc.
  final bool core;
  final bool producer;
  final bool genre;
  final bool lyrics;

  bool get ready => !core && !producer && !genre && !lyrics;
}

TrackMetaGaps trackMetaGaps(Track track) {
  final core = _coverMissing(track.coverPath) ||
      isBlankMeta(track.title) ||
      isBlankMeta(track.artist) ||
      _albumMissing(track.album) ||
      isBlankMeta(track.albumArtist) ||
      track.year == null ||
      track.year! < 1000 ||
      track.trackNumber == null ||
      track.trackNumber! < 1 ||
      track.trackTotal == null ||
      track.trackTotal! < 1 ||
      track.discNumber == null ||
      track.discNumber! < 1;
  return TrackMetaGaps(
    core: core,
    producer: producerNames(track.producer).isEmpty,
    genre: isBlankMeta(track.genre),
    lyrics: _lyricsMissing(track.lyrics),
  );
}

/// True when the lyrics tag has no visible text. Skips a full LRC rewrite.
bool _lyricsMissing(String? raw) {
  if (raw == null || raw.isEmpty) return true;
  for (var i = 0; i < raw.length; i++) {
    final unit = raw.codeUnitAt(i);
    if (unit == 0x5B) {
      final end = raw.indexOf(']', i + 1);
      if (end < 0) return true;
      i = end;
      continue;
    }
    if (unit > 32) return false;
  }
  return true;
}

bool _coverMissing(String? path) => path == null || path.trim().isEmpty;

bool _albumMissing(String album) {
  if (isBlankMeta(album)) return true;
  final name = album.trim().toLowerCase();
  return name == 'мне нравится' || name == 'мне нужен ui';
}
