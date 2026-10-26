import '../models/track.dart';
import '../utils/lyrics_format.dart';
import 'genius_service.dart';

/// Fetch lyrics from Genius when the file has none.
class LyricsService {
  LyricsService({GeniusService? genius}) : _genius = genius ?? GeniusService();

  final GeniusService _genius;

  /// With a note, the first query is «artist - title note».
  /// The second query is always «artist - title».
  Future<String?> fetchForTrack(Track track) async {
    final title = track.displayTitle.trim();
    final artist = track.displayArtist.trim();
    if (title.isEmpty ||
        title.toLowerCase() == 'unknown' ||
        artist.isEmpty ||
        artist.toLowerCase() == 'unknown') {
      return null;
    }

    final note = track.displayNote;
    if (note != null) {
      final withNote = await _genius.lyrics(
        artist: artist,
        title: title,
        note: note,
        phrase: true,
      );
      if (hasLyrics(withNote)) return withNote;
    }
    return _genius.lyrics(
      artist: artist,
      title: title,
      phrase: true,
    );
  }
}
