import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/artist_release.dart';
import '../models/track.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/release_detail_screen.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';

Future<void> openAlbumForTrack(BuildContext context, Track track) async {
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

Future<void> openArtistFromTrack(BuildContext context, Track track) async {
  final artists = track.artists;
  if (artists.isEmpty) return;

  String? chosen;
  if (artists.length == 1) {
    chosen = artists.first;
  } else {
    chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.inkLift,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Выберите артиста',
                  style: GoogleFonts.syne(
                    color: AppTheme.paper,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              for (final name in artists)
                ListTile(
                  title: Text(
                    name,
                    style: GoogleFonts.figtree(color: AppTheme.paper),
                  ),
                  onTap: () => Navigator.pop(context, name),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
  if (chosen == null || !context.mounted) return;
  await openArtistPage(context, chosen);
}

Future<void> openArtistPage(BuildContext context, String artistName) async {
  final library = context.read<LibraryService>();
  final cardName = library.artistCardName(artistName);
  final byArtist = library.tracksByArtist();
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
      ),
    ),
  );
}
