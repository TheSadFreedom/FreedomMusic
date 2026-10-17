import '../data/track_key.dart';
import 'track.dart';

enum ReleaseKind { album, single }

class ArtistRelease {
  const ArtistRelease({
    required this.title,
    required this.tracks,
    required this.kind,
    this.year,
    this.coverPath,
    this.credit,
  });

  final String title;
  final List<Track> tracks;
  final ReleaseKind kind;
  final int? year;
  final String? coverPath;

  /// Album owner shown under the title. Empty means the page artist.
  final String? credit;

  int get trackCount => tracks.length;
}

/// Album artists in first-seen order.
/// Uses the album-artist tag, otherwise the artists present on every track.
List<String> releaseAlbumArtists(ArtistRelease release) {
  final fromTag = _uniqueNames(
    release.tracks.expand((track) => splitArtists(track.albumArtist)),
  );
  if (fromTag.isNotEmpty) return fromTag;
  return _artistsOnEveryTrack(release.tracks);
}

List<String> _uniqueNames(Iterable<String> rawNames) {
  final names = <String>[];
  final seen = <String>{};
  for (final raw in rawNames) {
    final name = raw.trim();
    final key = name.toLowerCase();
    if (key.isEmpty || key == 'unknown' || !seen.add(key)) continue;
    names.add(name);
  }
  return names;
}

List<String> _artistsOnEveryTrack(List<Track> tracks) {
  if (tracks.isEmpty) return const [];
  final counts = <String, int>{};
  final order = <String>[];
  final seen = <String>{};
  for (final track in tracks) {
    final onTrack = <String>{};
    for (final artist in track.artists) {
      final key = artist.trim().toLowerCase();
      if (key.isEmpty || key == 'unknown' || !onTrack.add(key)) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      if (seen.add(key)) order.add(artist.trim());
    }
  }
  return [
    for (final name in order)
      if (counts[name.toLowerCase()] == tracks.length) name,
  ];
}

class ArtistReleaseGroups {
  const ArtistReleaseGroups({
    required this.albums,
    required this.singles,
    required this.appearances,
  });

  final List<ArtistRelease> albums;
  final List<ArtistRelease> singles;

  /// Releases where the artist appears, but is not the album artist.
  final List<ArtistRelease> appearances;
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

/// Own albums belong to the album artist.
/// Someone else on a track gets that whole release under
/// [ArtistReleaseGroups.appearances].
ArtistReleaseGroups groupArtistReleases({
  required List<Track> artistTracks,
  required Iterable<Track> libraryTracks,
  required bool Function(String name) isThisArtist,
  required String Function(String name) cardName,
}) {
  final byKey = <String, Track>{};
  for (final track in artistTracks) {
    byKey[track.trackKey] = track;
  }
  for (final track in libraryTracks) {
    byKey[track.trackKey] = track;
  }

  final byAlbum = <String, List<Track>>{};
  for (final track in byKey.values) {
    if (track.displayAlbum.toLowerCase() == 'unknown') continue;
    byAlbum.putIfAbsent(track.displayAlbum.toLowerCase(), () => []).add(track);
  }

  final used = <String>{};
  final own = <ArtistRelease>[];
  final appearances = <ArtistRelease>[];

  for (final group in byAlbum.values) {
    for (final cluster in _albumClusters(group, cardName)) {
      final owners = _clusterOwners(cluster, cardName);
      final mine = cluster.where((track) {
        return track.artists.any(isThisArtist);
      }).toList();
      if (mine.isEmpty && !owners.any(isThisArtist)) continue;

      final isOwner = owners.any(isThisArtist);
      if (isOwner) {
        own.add(_releaseFromTracks(cluster, credit: null));
        for (final track in mine) {
          used.add(track.trackKey);
        }
      } else if (mine.isNotEmpty && owners.isNotEmpty) {
        appearances.add(
          _releaseFromTracks(
            cluster,
            credit: _ownerCredit(cluster, owners, cardName),
          ),
        );
        for (final track in mine) {
          used.add(track.trackKey);
        }
      }
    }
  }

  final loose = artistTracks
      .where((track) => !used.contains(track.trackKey))
      .toList(growable: false);
  own.addAll(buildReleases(loose));
  own.sort(compareReleasesByYearDesc);
  appearances.sort(compareReleasesByYearDesc);
  return ArtistReleaseGroups(
    albums: own.where((release) => release.kind == ReleaseKind.album).toList(),
    singles: own.where((release) => release.kind == ReleaseKind.single).toList(),
    appearances: appearances,
  );
}

/// One list when every tagged track agrees on at least one album artist.
/// Otherwise each distinct album-artist tag is its own release.
List<List<Track>> _albumClusters(
  List<Track> tracks,
  String Function(String name) cardName,
) {
  final tagged = tracks.where((track) => _owners(track).isNotEmpty).toList();
  if (tagged.isEmpty) return [tracks];

  var shared = _ownerKeys(tagged.first, cardName);
  for (final track in tagged.skip(1)) {
    shared = shared.intersection(_ownerKeys(track, cardName));
    if (shared.isEmpty) break;
  }
  if (shared.isNotEmpty) return [tracks];

  final groups = <String, List<Track>>{};
  final untagged = <Track>[];
  for (final track in tracks) {
    if (_owners(track).isEmpty) {
      untagged.add(track);
      continue;
    }
    final key = (_ownerKeys(track, cardName).toList()..sort()).join('\u0002');
    groups.putIfAbsent(key, () => []).add(track);
  }
  if (groups.length == 1) {
    groups.values.first.addAll(untagged);
  }
  return groups.values.toList(growable: false);
}

/// Everyone named in the album-artist tag owns the release.
/// Without that tag, the artists on every track own it.
List<String> _clusterOwners(
  List<Track> tracks,
  String Function(String name) cardName,
) {
  final tagged = tracks.where((track) => _owners(track).isNotEmpty).toList();
  if (tagged.isNotEmpty) {
    final labels = <String, String>{};
    final order = <String>[];
    for (final track in tagged) {
      for (final name in _owners(track)) {
        final label = cardName(name).trim();
        final key = label.toLowerCase();
        if (key.isEmpty || key == 'unknown' || labels.containsKey(key)) {
          continue;
        }
        labels[key] = label;
        order.add(key);
      }
    }
    return [for (final key in order) labels[key]!];
  }

  if (tracks.isEmpty) return const [];
  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final track in tracks) {
    final seen = <String>{};
    for (final name in track.artists) {
      final key = cardName(name).trim().toLowerCase();
      if (key.isEmpty || key == 'unknown' || !seen.add(key)) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      labels.putIfAbsent(key, () => cardName(name).trim());
    }
  }
  return [
    for (final entry in counts.entries)
      if (entry.value == tracks.length) labels[entry.key]!,
  ];
}

Set<String> _ownerKeys(Track track, String Function(String name) cardName) {
  return _owners(track).map((name) => cardName(name).trim().toLowerCase()).toSet();
}

String _ownerCredit(
  List<Track> tracks,
  List<String> owners,
  String Function(String name) cardName,
) {
  if (owners.isNotEmpty) return owners.join(', ');
  return _ownerLabel(tracks.first, cardName);
}

List<String> _owners(Track track) {
  return splitArtists(track.albumArtist)
      .where((name) => name.trim().isNotEmpty && name.toLowerCase() != 'unknown')
      .toList(growable: false);
}

String _ownerLabel(Track track, String Function(String name) cardName) {
  final names = <String>[];
  final seen = <String>{};
  for (final name in _owners(track)) {
    final card = cardName(name);
    if (seen.add(card.toLowerCase())) names.add(card);
  }
  return names.join(', ');
}

ArtistRelease _releaseFromTracks(List<Track> tracks, {required String? credit}) {
  final ordered = List<Track>.from(tracks)
    ..sort((a, b) {
      final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
      if (disc != 0) return disc;
      final number = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
      if (number != 0) return number;
      return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
    });
  final years = ordered.map((t) => t.year).whereType<int>().toList();
  final year = years.isEmpty ? null : years.reduce((a, b) => a > b ? a : b);
  String? cover;
  for (final track in ordered) {
    final path = track.coverPath;
    if (path != null && path.isNotEmpty) {
      cover = path;
      break;
    }
  }
  final kind = ordered.length <= 1 ? ReleaseKind.single : ReleaseKind.album;
  return ArtistRelease(
    title: ordered.first.displayAlbum,
    tracks: ordered,
    kind: kind,
    year: year,
    coverPath: cover,
    credit: (credit == null || credit.isEmpty) ? null : credit,
  );
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
