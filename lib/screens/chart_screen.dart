import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../models/track.dart';
import '../screens/metadata_editor_screen.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/duration_format.dart';
import '../utils/trash_actions.dart';
import '../widgets/track_cover_play.dart';
import '../widgets/track_meta_links.dart';

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

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  Future<List<_ChartRow>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<_ChartRow>> _load() async {
    final library = context.read<LibraryService>();
    final settings = context.read<SettingsService>();
    final entries = await library.chart(ChartPeriod.allTime);
    final prev = settings.chartSnapshot(ChartPeriod.allTime.name);

    final rows = <_ChartRow>[];
    final nextSnap = <String, int>{};
    for (var i = 0; i < entries.length; i++) {
      final rank = i + 1;
      final key = entries[i].track.trackKey;
      nextSnap[key] = rank;
      final old = prev[key];
      final delta = old == null
          ? (prev.isEmpty ? _RankDelta.same : _RankDelta.newEntry)
          : old == rank
              ? _RankDelta.same
              : old > rank
                  ? _RankDelta.up
                  : _RankDelta.down;
      rows.add(_ChartRow(rank: rank, entry: entries[i], delta: delta));
    }

    // Persist current order as baseline for the next visit.
    await settings.saveChartSnapshot(ChartPeriod.allTime.name, nextSnap);
    return rows;
  }

  void _reload() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final player = context.read<PlayerService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Чарт',
            style: GoogleFonts.syne(
              color: AppTheme.paper,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: library.isEmpty
              ? const Center(
                  child: Text(
                    'Нет треков. Сканируйте папку music в Настройках.',
                  ),
                )
              : FutureBuilder<List<_ChartRow>>(
                  key: ValueKey('allTime-${library.tracks.length}'),
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = snapshot.data ?? const <_ChartRow>[];
                    final tracks = rows.map((r) => r.entry.track).toList();
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
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

class _ChartTrackRow extends StatefulWidget {
  const _ChartTrackRow({
    required this.row,
    required this.onPlay,
    required this.onEdit,
  });

  final _ChartRow row;
  final VoidCallback onPlay;
  final VoidCallback onEdit;

  @override
  State<_ChartTrackRow> createState() => _ChartTrackRowState();
}

class _ChartTrackRowState extends State<_ChartTrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.row.entry.track;
    final plays = widget.row.entry.playCount;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: widget.onPlay,
          onLongPress: widget.onEdit,
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
                        '${widget.row.rank}',
                        style: GoogleFonts.figtree(
                          color: AppTheme.paperMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 1),
                      _DeltaIcon(delta: widget.row.delta),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                TrackCoverPlay(
                  path: track.coverPath,
                  onPlay: widget.onPlay,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TrackMetaLinks(
                    track: track,
                    titleStyle: GoogleFonts.figtree(
                      color: AppTheme.paper,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    artistStyle: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (plays > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$plays',
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                PopupMenuButton<String>(
                  tooltip: 'Действия',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      widget.onEdit();
                    } else if (value == 'trash') {
                      await moveTrackToTrash(context, track);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Метаданные'),
                    ),
                    PopupMenuItem(
                      value: 'trash',
                      child: Text('В корзину'),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    formatTrackDuration(track.durationMs),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
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

