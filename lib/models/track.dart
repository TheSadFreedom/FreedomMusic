import 'package:path/path.dart' as p;

import '../data/track_key.dart';

final _searchCache = Expando<String>();

class Track {
  const Track({
    required this.trackKey,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    this.albumArtist,
    this.lyrics,
    this.year,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.durationMs,
    this.coverPath,
    this.trashedAt,
    this.addedAt,
    this.filePaths = const [],
  });

  final String trackKey;
  final String title;
  /// Full artist tag, e.g. "Artist A, Artist B".
  final String artist;
  final String album;
  final String genre;
  final String? albumArtist;
  final String? lyrics;
  final int? year;
  /// Track number on the album (TRCK).
  final int? trackNumber;
  /// Total tracks on the album / disc.
  final int? trackTotal;
  /// Disc / CD number (TPOS).
  final int? discNumber;
  final int? durationMs;
  final String? coverPath;
  /// Soft-delete timestamp; non-null means the track lives only in Корзина.
  final DateTime? trashedAt;
  /// When the track first appeared in the library (scan).
  final DateTime? addedAt;
  final List<String> filePaths;

  bool get isTrashed => trashedAt != null;

  /// True while [addedAt] is within the last 7 days and not trashed.
  bool get isNewTrack {
    final at = addedAt;
    if (at == null || isTrashed) return false;
    return DateTime.now().difference(at) < const Duration(days: 7);
  }

  String? get primaryPath =>
      filePaths.isEmpty ? null : filePaths.first;

  /// Individual artists (comma / feat.).
  List<String> get artists => splitArtists(artist);

  String get displayArtist => formatArtists(artist);

  String get displayTitle =>
      title.trim().isEmpty ? 'Unknown' : title;

  String get displayGenre =>
      genre.trim().isEmpty ? 'Unknown' : genre;

  String get displayAlbum =>
      album.trim().isEmpty ? 'Unknown' : album;

  /// All text used by home search (title, artists, album, lyrics, …).
  /// Cached: lyrics are long, and search must not rebuild this per keystroke.
  String get searchableText {
    final cached = _searchCache[this];
    if (cached != null) return cached;
    final names = <String>[
      title,
      artist,
      albumArtist ?? '',
      album,
      genre,
      lyrics ?? '',
      if (year != null) year.toString(),
      for (final path in filePaths) p.basenameWithoutExtension(path),
    ];
    final value = names.join(' ').toLowerCase();
    _searchCache[this] = value;
    return value;
  }

  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final hay = searchableText;
    return tokens.every(hay.contains);
  }

  Track copyWith({
    String? trackKey,
    String? title,
    String? artist,
    String? album,
    String? genre,
    Object? albumArtist = _unset,
    Object? lyrics = _unset,
    Object? year = _unset,
    Object? trackNumber = _unset,
    Object? trackTotal = _unset,
    Object? discNumber = _unset,
    int? durationMs,
    Object? coverPath = _unset,
    Object? trashedAt = _unset,
    Object? addedAt = _unset,
    List<String>? filePaths,
  }) {
    return Track(
      trackKey: trackKey ?? this.trackKey,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      albumArtist: identical(albumArtist, _unset)
          ? this.albumArtist
          : albumArtist as String?,
      lyrics: identical(lyrics, _unset) ? this.lyrics : lyrics as String?,
      year: identical(year, _unset) ? this.year : year as int?,
      trackNumber: identical(trackNumber, _unset)
          ? this.trackNumber
          : trackNumber as int?,
      trackTotal: identical(trackTotal, _unset)
          ? this.trackTotal
          : trackTotal as int?,
      discNumber: identical(discNumber, _unset)
          ? this.discNumber
          : discNumber as int?,
      durationMs: durationMs ?? this.durationMs,
      coverPath: identical(coverPath, _unset)
          ? this.coverPath
          : coverPath as String?,
      trashedAt: identical(trashedAt, _unset)
          ? this.trashedAt
          : trashedAt as DateTime?,
      addedAt: identical(addedAt, _unset)
          ? this.addedAt
          : addedAt as DateTime?,
      filePaths: filePaths ?? this.filePaths,
    );
  }
}

const Object _unset = Object();

class ChartEntry {
  const ChartEntry({
    required this.track,
    required this.playCount,
  });

  final Track track;
  final int playCount;
}
