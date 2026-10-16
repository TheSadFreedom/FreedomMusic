import 'track.dart';

enum ReleaseKind { album, single }

class ArtistRelease {
  const ArtistRelease({
    required this.title,
    required this.tracks,
    required this.kind,
    this.year,
    this.coverPath,
  });

  final String title;
  final List<Track> tracks;
  final ReleaseKind kind;
  final int? year;
  final String? coverPath;

  int get trackCount => tracks.length;
}

List<ArtistRelease> buildReleases(List<Track> tracks) {
  final byAlbum = <String, List<Track>>{};
  for (final t in tracks) {
    final key = t.displayAlbum;
    byAlbum.putIfAbsent(key, () => []).add(t);
  }

  final releases = <ArtistRelease>[];
  for (final entry in byAlbum.entries) {
    final list = entry.value;
    final years = list.map((t) => t.year).whereType<int>().toList();
    final year = years.isEmpty
        ? null
        : years.reduce((a, b) => a > b ? a : b);
    String? cover;
    for (final t in list) {
      final p = t.coverPath;
      if (p != null && p.isNotEmpty) {
        cover = p;
        break;
      }
    }
    final isUnknown = entry.key.toLowerCase() == 'unknown';
    final kind = (list.length <= 1 || isUnknown)
        ? ReleaseKind.single
        : ReleaseKind.album;
    releases.add(
      ArtistRelease(
        title: entry.key,
        tracks: list,
        kind: kind,
        year: year,
        coverPath: cover,
      ),
    );
  }

  releases.sort(compareReleasesByYearDesc);
  return releases;
}

/// Newest year first; missing / non-positive years go last.
int compareReleasesByYearDesc(ArtistRelease a, ArtistRelease b) {
  final ay = (a.year != null && a.year! > 0) ? a.year! : -1;
  final by = (b.year != null && b.year! > 0) ? b.year! : -1;
  if (by != ay) return by.compareTo(ay);
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Album/single listens: 1 listen = 70% of the sum of all track durations.
/// Listening time stacks even when the same track is replayed.
int releaseListenCount(
  ArtistRelease release,
  Map<String, int> listenMsByKey,
) {
  var totalDurMs = 0;
  var listenedMs = 0;
  for (final t in release.tracks) {
    final d = t.durationMs ?? 0;
    if (d > 0) totalDurMs += d;
    listenedMs += listenMsByKey[t.trackKey] ?? 0;
  }
  if (totalDurMs <= 0) return 0;
  final unit = (totalDurMs * 0.7).round();
  if (unit <= 0) return 0;
  return listenedMs ~/ unit;
}

String formatListenCount(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n прослушивание';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$n прослушивания';
  }
  return '$n прослушиваний';
}
