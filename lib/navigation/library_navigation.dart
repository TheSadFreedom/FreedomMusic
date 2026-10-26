import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/artist_release.dart';
import '../models/track.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/release_detail_screen.dart';
import '../services/library_service.dart';
import '../widgets/app_bottom_sheet.dart';
import 'app_navigator.dart';

Future<void> openAlbumForTrack(BuildContext context, Track track) async {
  context = navigatorContext(context);
  final library = context.read<LibraryService>();
  final album = track.displayAlbum;
  final albumTracks = library.tracks
      .where((t) => t.displayAlbum.toLowerCase() == album.toLowerCase())
      .toList();
  if (albumTracks.isEmpty) return;

  final releases = buildReleases(albumTracks);
  final release = releases.firstWhere(
    (r) => r.title.toLowerCase() == album.toLowerCase(),
    orElse: () => releases.first,
  );
  final primary = track.artists.isNotEmpty
      ? track.artists.first
      : track.displayArtist;

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReleaseDetailScreen(
        release: release,
        primaryArtist: primary,
      ),
    ),
  );
}

Future<void> openArtistFromTrack(BuildContext context, Track track) {
  return openArtists(context, track.artists);
}

/// Opens the only artist immediately. Several names ask which card to open.
Future<void> openArtists(BuildContext context, List<String> artists) async {
  context = navigatorContext(context);
  final names = <String>[];
  final seen = <String>{};
  for (final raw in artists) {
    final name = raw.trim();
    if (name.isEmpty || name.toLowerCase() == 'unknown') continue;
    if (seen.add(name.toLowerCase())) names.add(name);
  }
  if (names.isEmpty) return;

  String? chosen;
  if (names.length == 1) {
    chosen = names.first;
  } else {
    final library = context.read<LibraryService>();
    final byArtist = library.tracksByArtist();
    chosen = await showAppBottomSheet<String>(
      context: context,
      title: 'Выберите артиста',
      buildChildren: (sheetCtx) => [
        for (final name in names)
          SheetRow(
            title: name,
            subtitle: _artistTracksSubtitle(library, byArtist, name),
            leading: SheetArtistAvatar(
              photoPath: library.artistPhotoPath(library.artistCardName(name)),
            ),
            onTap: () => Navigator.pop(sheetCtx, name),
          ),
      ],
    );
  }
  if (chosen == null || !context.mounted) return;
  await openArtistPage(context, chosen);
}

String? _artistTracksSubtitle(
  LibraryService library,
  Map<String, List<Track>> byArtist,
  String name,
) {
  final card = library.artistCardName(name);
  List<Track>? tracks = byArtist[card];
  if (tracks == null) {
    for (final e in byArtist.entries) {
      if (e.key.toLowerCase() == card.toLowerCase()) {
        tracks = e.value;
        break;
      }
    }
  }
  if (tracks == null || tracks.isEmpty) return null;
  final n = tracks.length;
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n трек в библиотеке';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$n трека в библиотеке';
  }
  return '$n треков в библиотеке';
}

Future<void> openArtistPage(
  BuildContext context,
  String artistName, {
  bool producer = false,
}) async {
  context = navigatorContext(context);
  final library = context.read<LibraryService>();
  final cardName = producer
      ? library.producerCardName(artistName)
      : library.artistCardName(artistName);
  final byArtist =
      producer ? library.tracksByProducer() : library.tracksByArtist();
  final tracks = byArtist[cardName] ??
      byArtist.entries
          .where((e) => e.key.toLowerCase() == cardName.toLowerCase())
          .map((e) => e.value)
          .firstOrNull;
  if (tracks == null || tracks.isEmpty) return;

  final playCounts = await library.playCountsAllTime();
  if (!context.mounted) return;

  // Rank among all artists by total plays.
  final totals = <String, int>{};
  for (final entry in byArtist.entries) {
    totals[entry.key] = entry.value.fold<int>(
      0,
      (sum, t) => sum + (playCounts[t.trackKey] ?? 0),
    );
  }
  final ranked = totals.entries.toList()
    ..sort((a, b) {
      final byPlay = b.value.compareTo(a.value);
      if (byPlay != 0) return byPlay;
      return a.key.toLowerCase().compareTo(b.key.toLowerCase());
    });
  final rankIndex = ranked.indexWhere(
    (e) => e.key.toLowerCase() == cardName.toLowerCase(),
  );
  final chartRank = rankIndex >= 0 ? rankIndex + 1 : 0;
  final playCount = totals.entries
      .firstWhere(
        (e) => e.key.toLowerCase() == cardName.toLowerCase(),
        orElse: () => MapEntry(cardName, 0),
      )
      .value;

  final displayName = byArtist.keys.firstWhere(
    (k) => k.toLowerCase() == cardName.toLowerCase(),
    orElse: () => cardName,
  );

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ArtistDetailScreen(
        artist: displayName,
        tracks: tracks,
        playCount: playCount,
        chartRank: chartRank,
        trackPlayCounts: playCounts,
        byProducer: producer,
      ),
    ),
  );
}
