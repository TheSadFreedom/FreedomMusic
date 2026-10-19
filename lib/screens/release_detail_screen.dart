import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/track_key.dart';
import '../models/artist_release.dart';
import '../models/track.dart';
import '../navigation/library_navigation.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/duration_format.dart';
import '../utils/playlist_actions.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/fullscreen_cover.dart';
import '../widgets/listen_actions.dart';
import '../widgets/track_cover_play.dart';
import '../widgets/track_overflow_menu.dart';
import '../widgets/track_meta_links.dart';
import 'release_metadata_editor_screen.dart';

/// Album / single page in Yandex Music style.
class ReleaseDetailScreen extends StatefulWidget {
  const ReleaseDetailScreen({
    super.key,
    required this.release,
    required this.primaryArtist,
  });

  final ArtistRelease release;
  final String primaryArtist;

  @override
  State<ReleaseDetailScreen> createState() => _ReleaseDetailScreenState();
}

class _ReleaseDetailScreenState extends State<ReleaseDetailScreen> {
  Future<int>? _listensFuture;

  ArtistRelease _liveRelease(LibraryService library) {
    final tracks = <Track>[
      for (final track in widget.release.tracks)
        library.resolveTrack(track),
    ].where((track) => !track.isTrashed).toList();
    if (tracks.isEmpty) return widget.release;
    int? year;
    for (final track in tracks) {
      final value = track.year;
      if (value != null && value > 0 && (year == null || value > year)) {
        year = value;
      }
    }
    final draft = ArtistRelease(
      title: tracks.first.displayAlbum,
      tracks: tracks,
      kind: releaseKindForTracks(tracks),
      year: year,
      credit: widget.release.credit,
    );
    return ArtistRelease(
      title: draft.title,
      tracks: tracks,
      kind: draft.kind,
      year: year,
      coverPath: library.releaseCover(draft) ?? widget.release.coverPath,
      credit: draft.credit,
    );
  }

  String _kindLabel(ArtistRelease release) {
    if (release.kind == ReleaseKind.single && release.tracks.length > 1) {
      return 'Макси-Сингл';
    }
    return releaseKindLabel(release.kind);
  }

  List<String> _releaseArtists(ArtistRelease release) {
    final names = releaseAlbumArtists(release);
    if (names.isNotEmpty) return names;
    final fallback = widget.primaryArtist.trim();
    if (fallback.isEmpty || fallback.toLowerCase() == 'unknown') {
      return const [];
    }
    return [fallback];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listensFuture ??= context.read<LibraryService>().playCountsAllTime().then(
          (map) => releaseListenCount(widget.release, map),
        );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    final library = context.watch<LibraryService>();
    final release = _liveRelease(library);
    final artists = _releaseArtists(release);
    final artistsLine = artists.join(', ');
    final tracks = List<Track>.from(release.tracks)
      ..sort((a, b) {
        final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
        if (disc != 0) return disc;
        final ta = a.trackNumber ?? 9999;
        final tb = b.trackNumber ?? 9999;
        if (ta != tb) return ta.compareTo(tb);
        return a.displayTitle
            .toLowerCase()
            .compareTo(b.displayTitle.toLowerCase());
      });
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final coverSize = wide ? 200.0 : 160.0;

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: FutureBuilder<int>(
        future: _listensFuture,
        builder: (context, snap) {
          final listens = snap.data ?? 0;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppTheme.ink.withValues(alpha: 0.92),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  metaFieldText(release.title),
                  style: GoogleFonts.syne(fontWeight: FontWeight.w700),
                ),
              ),
              SliverToBoxAdapter(
                child: TrackContextMenu(
                  actions: releaseMenuActions(context, release),
                  child: Stack(
                  children: [
                    const Positioned.fill(
                      child: AmbientBackdrop(
                        accent: Color(0xFF4A3A5C),
                        secondary: Color(0xFF2A3A4C),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Cover(
                                  path: release.coverPath,
                                  size: coverSize,
                                ),
                                const SizedBox(width: 28),
                                Expanded(
                                  child: _Meta(
                                    kindLabel: _kindLabel(release),
                                    title: metaFieldText(release.title),
                                    artistsLine: artistsLine,
                                    year: release.year,
                                    listenCount: listens,
                                    onArtists: () =>
                                        openArtists(context, artists),
                                    onListen: () => player.playTracks(tracks),
                                    onShuffle: () => player.playTracks(
                                      tracks,
                                      shuffle: true,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _Cover(
                                  path: release.coverPath,
                                  size: coverSize,
                                ),
                                const SizedBox(height: 20),
                                _Meta(
                                  kindLabel: _kindLabel(release),
                                  title: metaFieldText(release.title),
                                  artistsLine: artistsLine,
                                  year: release.year,
                                  listenCount: listens,
                                  centered: true,
                                  onArtists: () =>
                                      openArtists(context, artists),
                                  onListen: () => player.playTracks(tracks),
                                  onShuffle: () => player.playTracks(
                                    tracks,
                                    shuffle: true,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate(
                  _releaseRows(tracks, player),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  child: Text(
                    releaseCaption(release, listens),
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path, required this.size});

  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasFile = path != null && File(path!).existsSync();
    Widget image = ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(Icons.album, size: size * 0.35, color: AppTheme.mossBright),
    );
    if (hasFile) {
      image = Image.file(File(path!), fit: BoxFit.cover);
    }

    return MouseRegion(
      cursor: hasFile ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: hasFile ? () => showFullscreenCover(context, path) : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: image,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.kindLabel,
    required this.title,
    required this.artistsLine,
    required this.year,
    required this.listenCount,
    required this.onArtists,
    required this.onListen,
    required this.onShuffle,
    this.centered = false,
  });

  final String kindLabel;
  final String title;
  final String artistsLine;
  final int? year;
  final int listenCount;
  final VoidCallback onArtists;
  final VoidCallback onListen;
  final VoidCallback onShuffle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align = centered ? TextAlign.center : TextAlign.left;
    final cross =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(
          kindLabel,
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          textAlign: align,
          style: GoogleFonts.syne(
            color: AppTheme.paper,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 10),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onArtists,
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.figtree(fontSize: 15, height: 1.35),
                children: [
                  TextSpan(
                    text: artistsLine,
                    style: const TextStyle(
                      color: AppTheme.paper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((year ?? 0) > 0)
                    TextSpan(
                      text: '  ·  $year',
                      style: const TextStyle(color: AppTheme.paperMuted),
                    ),
                  if (listenCount > 0)
                    TextSpan(
                      text: '  ·  ${formatListenCount(listenCount)}',
                      style: const TextStyle(color: AppTheme.paperMuted),
                    ),
                ],
              ),
              textAlign: align,
            ),
          ),
        ),
        const SizedBox(height: 22),
        ListenActions(
          onListen: onListen,
          onShuffle: onShuffle,
          center: centered,
        ),
      ],
    );
  }
}

List<Widget> _releaseRows(List<Track> tracks, PlayerService player) {
  final discs = <int>{
    for (final track in tracks) track.discNumber ?? 1,
  };
  final multiDisc = discs.length > 1;
  final rows = <Widget>[];
  var shownDisc = 0;
  for (var i = 0; i < tracks.length; i++) {
    final track = tracks[i];
    final disc = track.discNumber ?? 1;
    if (multiDisc && disc != shownDisc) {
      shownDisc = disc;
      rows.add(_DiscHeader(number: disc, first: rows.isEmpty));
    }
    rows.add(
      _TrackRow(
        track: track,
        onTap: () => player.playTracks(tracks, startIndex: i),
      ),
    );
  }
  return rows;
}

class _DiscHeader extends StatelessWidget {
  const _DiscHeader({required this.number, required this.first});

  final int number;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, first ? 4 : 18, 24, 6),
      child: Text(
        'Диск $number',
        style: GoogleFonts.figtree(
          color: AppTheme.paper,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _trackNumberLabel(int? number) {
  if (number == null || number < 1) return '—';
  return '$number';
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.onTap,
  });

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TrackContextMenu(
      actions: standardTrackActions(context, track),
      child: InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                _trackNumberLabel(track.trackNumber),
                style: GoogleFonts.figtree(
                  color: AppTheme.paperMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TrackCoverPlay(
              path: track.coverPath,
              onPlay: onTap,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TrackMetaLinks(
                track: track,
                titleStyle: GoogleFonts.figtree(
                  color: AppTheme.paper,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                artistStyle: GoogleFonts.figtree(
                  color: AppTheme.paperMuted,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              formatTrackDuration(track.durationMs),
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 13,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => addTrackToPlaylist(context, track),
              icon: const Icon(
                Icons.queue_music_rounded,
                color: AppTheme.paperMuted,
                size: 22,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
