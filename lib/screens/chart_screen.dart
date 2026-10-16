import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/track_key.dart';
import '../models/artist_release.dart';
import '../models/track.dart';
import '../navigation/library_navigation.dart';
import '../screens/metadata_editor_screen.dart';
import '../screens/release_detail_screen.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/duration_format.dart';
import '../utils/playlist_actions.dart';
import '../utils/trash_actions.dart';
import '../widgets/pill_segmented.dart';
import '../widgets/track_cover_play.dart';
import '../widgets/track_meta_links.dart';
import '../widgets/track_overflow_menu.dart';

enum _ChartKind { tracks, albums }

enum _RankDelta { up, down, same, newEntry }

class _ChartRow {
  const _ChartRow({
    required this.rank,
    required this.entry,
    required this.delta,
  });

  final int rank;
  final ChartEntry entry;
  final _RankDelta delta;
}

class _AlbumChartRow {
  const _AlbumChartRow({
    required this.rank,
    required this.release,
    required this.artist,
    required this.listens,
    required this.delta,
  });

  final int rank;
  final ArtistRelease release;
  final String artist;
  final int listens;
  final _RankDelta delta;
}

class _ChartData {
  const _ChartData({required this.tracks, required this.albums});

  final List<_ChartRow> tracks;
  final List<_AlbumChartRow> albums;
}

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  Future<_ChartData>? _future;
  bool _refreshing = false;
  _ChartKind _kind = _ChartKind.tracks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<_ChartData> _load() async {
    final library = context.read<LibraryService>();
    final settings = context.read<SettingsService>();
    final entries = await library.chart(ChartPeriod.allTime);
    final listenMs = await library.listenMsAllTime();
    final trackRows = _rankTracks(entries, settings.chartSnapshot(ChartPeriod.allTime.name));
    final albumRows = _rankAlbums(
      library.tracks,
      listenMs,
      settings.chartSnapshot('albums'),
    );
    await settings.saveChartSnapshot(ChartPeriod.allTime.name, {
      for (final row in trackRows) row.entry.track.trackKey: row.rank,
    });
    await settings.saveChartSnapshot('albums', {
      for (final row in albumRows) _albumKey(row.release, row.artist): row.rank,
    });
    return _ChartData(tracks: trackRows, albums: albumRows);
  }

  List<_ChartRow> _rankTracks(List<ChartEntry> entries, Map<String, int> prev) {
    final rows = <_ChartRow>[];
    for (var i = 0; i < entries.length; i++) {
      final rank = i + 1;
      rows.add(_ChartRow(
        rank: rank,
        entry: entries[i],
        delta: _delta(prev, entries[i].track.trackKey, rank),
      ));
    }
    return rows;
  }

  List<_AlbumChartRow> _rankAlbums(
    List<Track> tracks,
    Map<String, int> listenMs,
    Map<String, int> prev,
  ) {
    final groups = <String, List<Track>>{};
    final artistLabel = <String, String>{};
    final albumLabel = <String, String>{};
    for (final track in tracks) {
      final album = track.displayAlbum.trim();
      if (album.isEmpty || album.toLowerCase() == 'unknown') continue;
      final artist = (track.albumArtist != null &&
              track.albumArtist!.trim().isNotEmpty)
          ? track.albumArtist!.trim()
          : track.displayArtist;
      final key = '${artist.toLowerCase()}\u0001${album.toLowerCase()}';
      groups.putIfAbsent(key, () => []).add(track);
      artistLabel.putIfAbsent(key, () => artist);
      albumLabel.putIfAbsent(key, () => album);
    }

    final ranked = <_AlbumChartRow>[];
    for (final entry in groups.entries) {
      final list = entry.value;
      if (list.length <= 1) continue;
      list.sort((a, b) {
        final ta = a.trackNumber ?? 9999;
        final tb = b.trackNumber ?? 9999;
        if (ta != tb) return ta.compareTo(tb);
        return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
      });
      final years = list.map((t) => t.year).whereType<int>().toList();
      String? cover;
      for (final track in list) {
        final path = track.coverPath;
        if (path != null && path.isNotEmpty) {
          cover = path;
          break;
        }
      }
      final release = ArtistRelease(
        title: albumLabel[entry.key]!,
        tracks: list,
        kind: ReleaseKind.album,
        year: years.isEmpty ? null : years.reduce((a, b) => a > b ? a : b),
        coverPath: cover,
      );
      ranked.add(_AlbumChartRow(
        rank: 0,
        release: release,
        artist: artistLabel[entry.key]!,
        listens: releaseListenCount(release, listenMs),
        delta: _RankDelta.same,
      ));
    }
    ranked.sort((a, b) {
      final byListens = b.listens.compareTo(a.listens);
      if (byListens != 0) return byListens;
      final byTitle = a.release.title.toLowerCase().compareTo(
            b.release.title.toLowerCase(),
          );
      if (byTitle != 0) return byTitle;
      return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    });
    return [
      for (var i = 0; i < ranked.length; i++)
        _AlbumChartRow(
          rank: i + 1,
          release: ranked[i].release,
          artist: ranked[i].artist,
          listens: ranked[i].listens,
          delta: _delta(
            prev,
            _albumKey(ranked[i].release, ranked[i].artist),
            i + 1,
          ),
        ),
    ];
  }

  _RankDelta _delta(Map<String, int> prev, String key, int rank) {
    final old = prev[key];
    if (old == null) {
      return prev.isEmpty ? _RankDelta.same : _RankDelta.newEntry;
    }
    if (old == rank) return _RankDelta.same;
    return old > rank ? _RankDelta.up : _RankDelta.down;
  }

  String _albumKey(ArtistRelease release, String artist) =>
      '${artist.toLowerCase()}\u0001${release.title.toLowerCase()}';

  void _reload() {
    setState(() {
      _refreshing = true;
      _future = _load().whenComplete(() {
        if (mounted) setState(() => _refreshing = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final player = context.read<PlayerService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Чарт',
                  style: GoogleFonts.syne(
                    color: AppTheme.paper,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              PillSegmented<_ChartKind>(
                segments: const [
                  PillSegment(value: _ChartKind.tracks, label: 'Треки'),
                  PillSegment(value: _ChartKind.albums, label: 'Альбомы'),
                ],
                selected: _kind,
                onChanged: (kind) => setState(() => _kind = kind),
              ),
              IconButton(
                onPressed: _refreshing ? null : _reload,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, color: AppTheme.paper),
              ),
            ],
          ),
        ),
        Expanded(
          child: library.isEmpty
              ? const Center(
                  child: Text(
                    'Нет треков. Сканируйте папку music в Настройках.',
                  ),
                )
              : FutureBuilder<_ChartData>(
                  key: ValueKey('chart-${library.tracks.length}'),
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final data = snapshot.data;
                    if (data == null) {
                      return const SizedBox.shrink();
                    }
                    if (_kind == _ChartKind.albums) {
                      return _AlbumChartList(rows: data.albums);
                    }
                    final rows = data.tracks;
                    final tracks = rows.map((r) => r.entry.track).toList();
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      // Fixed height lets a fling jump by index instead of
                      // laying out every row in between on one frame.
                      itemExtent: 64,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return _ChartTrackRow(
                          row: row,
                          onPlay: () =>
                              player.playTracks(tracks, startIndex: index),
                          onEdit: () async {
                            final ok = await openMetadataEditor(
                              context,
                              row.entry.track,
                            );
                            if (ok && mounted) _reload();
                          },
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AlbumChartList extends StatelessWidget {
  const _AlbumChartList({required this.rows});

  final List<_AlbumChartRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'Нет альбомов',
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final player = context.read<PlayerService>();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemExtent: 64,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return _AlbumChartTile(
          row: row,
          onPlay: () => player.playTracks(row.release.tracks),
        );
      },
    );
  }
}

class _AlbumChartTile extends StatelessWidget {
  const _AlbumChartTile({required this.row, required this.onPlay});

  final _AlbumChartRow row;
  final VoidCallback onPlay;

  static final _rankStyle = GoogleFonts.figtree(
    color: AppTheme.paperMuted,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );
  static final _titleStyle = GoogleFonts.figtree(
    color: AppTheme.paper,
    fontWeight: FontWeight.w600,
    fontSize: 15,
  );
  static final _artistStyle = GoogleFonts.figtree(
    color: AppTheme.paperMuted,
    fontSize: 13,
  );
  static final _playsStyle = GoogleFonts.figtree(
    color: AppTheme.paperMuted.withValues(alpha: 0.55),
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final artistName = splitArtists(row.artist).first;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Colors.white.withValues(alpha: 0.04),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${row.rank}', style: _rankStyle),
                    const SizedBox(height: 1),
                    _DeltaIcon(delta: row.delta),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              TrackCoverPlay(
                path: row.release.coverPath,
                onPlay: onPlay,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReleaseDetailScreen(
                                release: row.release,
                                primaryArtist: artistName,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          row.release.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _titleStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openArtistPage(context, artistName),
                        child: Text(
                          row.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _artistStyle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (row.listens > 0) ...[
                const SizedBox(width: 8),
                Text('${row.listens}', style: _playsStyle),
              ],
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartTrackRow extends StatelessWidget {
  const _ChartTrackRow({
    required this.row,
    required this.onPlay,
    required this.onEdit,
  });

  final _ChartRow row;
  final VoidCallback onPlay;
  final VoidCallback onEdit;

  static final _rankStyle = GoogleFonts.figtree(
    color: AppTheme.paperMuted,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );
  static final _titleStyle = GoogleFonts.figtree(
    color: AppTheme.paper,
    fontWeight: FontWeight.w600,
    fontSize: 15,
  );
  static final _artistStyle = GoogleFonts.figtree(
    color: AppTheme.paperMuted,
    fontSize: 13,
  );
  static final _playsStyle = GoogleFonts.figtree(
    color: AppTheme.paperMuted.withValues(alpha: 0.55),
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );
  static final _durationStyle = GoogleFonts.figtree(
    color: AppTheme.paperMuted,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final track = row.entry.track;
    final plays = row.entry.playCount;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Colors.white.withValues(alpha: 0.04),
        onTap: onPlay,
        onLongPress: onEdit,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${row.rank}',
                        style: _rankStyle,
                      ),
                      const SizedBox(height: 1),
                      _DeltaIcon(delta: row.delta),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                TrackCoverPlay(
                  path: track.coverPath,
                  onPlay: onPlay,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TrackMetaLinks(
                    track: track,
                    titleStyle: _titleStyle,
                    artistStyle: _artistStyle,
                  ),
                ),
                if (plays > 0) ...[
                  const SizedBox(width: 8),
                  Text('$plays', style: _playsStyle),
                ],
                TrackOverflowMenu(
                  actions: [
                    TrackMenuAction(
                      icon: Icons.edit_outlined,
                      label: 'Метаданные',
                      onSelected: onEdit,
                    ),
                    TrackMenuAction(
                      icon: Icons.queue_music_rounded,
                      label: 'В плейлист',
                      onSelected: () => addTrackToPlaylist(context, track),
                    ),
                    TrackMenuAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'В корзину',
                      destructive: true,
                      onSelected: () => moveTrackToTrash(context, track),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    formatTrackDuration(track.durationMs),
                    textAlign: TextAlign.right,
                    style: _durationStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

class _DeltaIcon extends StatelessWidget {
  const _DeltaIcon({required this.delta});

  final _RankDelta delta;

  @override
  Widget build(BuildContext context) {
    return switch (delta) {
      _RankDelta.up => const _TrendTriangle(up: true),
      _RankDelta.down => const _TrendTriangle(up: false),
      _RankDelta.newEntry => Text(
          'new',
          style: GoogleFonts.figtree(
            color: const Color(0xFFFFDB4D),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      _RankDelta.same => Container(
          width: 8,
          height: 1.5,
          margin: const EdgeInsets.symmetric(vertical: 5),
          color: AppTheme.paperMuted.withValues(alpha: 0.65),
        ),
    };
  }
}

class _TrendTriangle extends StatelessWidget {
  const _TrendTriangle({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(10, 7),
      painter: _TrianglePainter(
        color: up ? const Color(0xFF3DDC84) : const Color(0xFFFF5C5C),
        pointUp: up,
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color, required this.pointUp});

  final Color color;
  final bool pointUp;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) =>
      old.color != color || old.pointUp != pointUp;
}

