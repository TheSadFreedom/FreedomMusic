import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pill_segmented.dart';
import '../widgets/screen_title.dart';
import 'artist_detail_screen.dart';

enum ArtistSort {
  chart,
  name,
  trackCount,
}

extension on ArtistSort {
  String get label => switch (this) {
        ArtistSort.chart => 'Чарт',
        ArtistSort.name => 'Название',
        ArtistSort.trackCount => 'Треки',
      };
}

class _ArtistRow {
  const _ArtistRow({
    required this.name,
    required this.tracks,
    required this.playCount,
    required this.rank,
  });

  final String name;
  final List<Track> tracks;
  final int playCount;
  final int rank;

  int get trackCount => tracks.length;

  String? coverFromTracks() {
    for (final t in tracks) {
      final p = t.coverPath;
      if (p != null && File(p).existsSync()) return p;
    }
    return null;
  }
}

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  ArtistSort _sort = ArtistSort.chart;
  Map<String, int> _playCounts = {};
  bool _loadingCounts = true;
  bool _refreshing = false;
  final _number = NumberFormat('#,###', 'ru');
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlayCounts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlayCounts() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final library = context.read<LibraryService>();
    final counts = await library.playCountsAllTime();
    if (!mounted) return;
    setState(() {
      _playCounts = counts;
      _loadingCounts = false;
      _refreshing = false;
    });
  }

  List<_ArtistRow> _sortedRows(
    Map<String, List<Track>> artists,
    LibraryService library,
  ) {
    final rows = artists.entries.map((e) {
      final plays = e.value.fold<int>(
        0,
        (sum, t) => sum + (_playCounts[t.trackKey] ?? 0),
      );
      return _ArtistRow(
        name: e.key,
        tracks: e.value,
        playCount: plays,
        rank: 0,
      );
    }).toList();

    // Chart rank is always by plays (all-time top).
    final byPlays = List<_ArtistRow>.from(rows)
      ..sort((a, b) {
        final byPlay = b.playCount.compareTo(a.playCount);
        if (byPlay != 0) return byPlay;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final rankByName = <String, int>{
      for (var i = 0; i < byPlays.length; i++) byPlays[i].name: i + 1,
    };

    var ranked = rows
        .map(
          (r) => _ArtistRow(
            name: r.name,
            tracks: r.tracks,
            playCount: r.playCount,
            rank: rankByName[r.name] ?? 0,
          ),
        )
        .toList();

    final q = _query.trim();
    if (q.isNotEmpty) {
      ranked = ranked
          .where((r) => library.artistCardMatchesQuery(r.name, q))
          .toList();
    }

    switch (_sort) {
      case ArtistSort.chart:
        ranked.sort((a, b) => a.rank.compareTo(b.rank));
      case ArtistSort.name:
        ranked.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case ArtistSort.trackCount:
        ranked.sort((a, b) {
          final byCount = b.trackCount.compareTo(a.trackCount);
          if (byCount != 0) return byCount;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
    return ranked;
  }

  int _crossAxisCount(double width) {
    if (width >= 1400) return 8;
    if (width >= 1100) return 7;
    if (width >= 900) return 6;
    if (width >= 700) return 5;
    if (width >= 520) return 4;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final artists = library.tracksByArtist();

    if (library.isEmpty) {
      return const Center(
        child: Text('Нет треков. Сканируйте папку music в Настройках.'),
      );
    }

    final rows = _sortedRows(artists, library);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenTitle(
          title: 'Артисты',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _refreshing ? null : _loadPlayCounts,
                visualDensity: VisualDensity.compact,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, color: AppTheme.paper),
              ),
              PillSegmented<ArtistSort>(
                segments: [
                  for (final s in ArtistSort.values)
                    PillSegment(value: s, label: s.label),
                ],
                selected: _sort,
                onChanged: (s) => setState(() => _sort = s),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            style: GoogleFonts.figtree(
              color: AppTheme.paper,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: AppTheme.lime,
            decoration: InputDecoration(
              hintText: 'Поиск артиста',
              hintStyle: GoogleFonts.figtree(color: AppTheme.paperMuted),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppTheme.paperMuted,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.paperMuted,
                      ),
                    ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 12,
              ),
            ),
          ),
        ),
        Expanded(
          child: _loadingCounts && _sort == ArtistSort.chart
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(
                      child: Text(
                        _query.trim().isEmpty
                            ? 'Нет артистов'
                            : 'Ничего не найдено',
                        style: GoogleFonts.figtree(
                          color: AppTheme.paperMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final count = _crossAxisCount(constraints.maxWidth);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: count,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 18,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            final photo = library.artistPhotoPath(row.name) ??
                                row.coverFromTracks();
                            return _ArtistGridTile(
                              row: row,
                              photoPath: photo,
                              tracksLabel: _number.format(row.trackCount),
                              playsLabel: _number.format(row.playCount),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ArtistDetailScreen(
                                      artist: row.name,
                                      tracks: row.tracks,
                                      playCount: row.playCount,
                                      chartRank: row.rank,
                                      trackPlayCounts: _playCounts,
                                    ),
                                  ),
                                );
                                await _loadPlayCounts();
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

class _ArtistGridTile extends StatelessWidget {
  const _ArtistGridTile({
    required this.row,
    required this.photoPath,
    required this.tracksLabel,
    required this.playsLabel,
    required this.onTap,
  });

  final _ArtistRow row;
  final String? photoPath;
  final String tracksLabel;
  final String playsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget avatar = Icon(
      Icons.person_rounded,
      color: AppTheme.paperMuted.withValues(alpha: 0.7),
      size: 40,
    );
    final path = photoPath;
    if (path != null) {
      avatar = Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => Icon(
          Icons.person_rounded,
          color: AppTheme.paperMuted.withValues(alpha: 0.7),
          size: 40,
        ),
      );
    }

    final metaStyle = GoogleFonts.figtree(
      color: AppTheme.paperMuted,
      fontWeight: FontWeight.w600,
      fontSize: 11,
      height: 1,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppTheme.inkLift,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(child: avatar),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    if (row.rank > 0)
                      TextSpan(
                        text: '${row.rank} ',
                        style: GoogleFonts.figtree(
                          color: AppTheme.paperMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    TextSpan(
                      text: row.name,
                      style: GoogleFonts.figtree(
                        color: AppTheme.paper,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tracksLabel, style: metaStyle),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.music_note_rounded,
                      size: 12,
                      color: AppTheme.paperMuted.withValues(alpha: 0.9),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text('–', style: metaStyle),
                    ),
                    Text(playsLabel, style: metaStyle),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.headphones_rounded,
                      size: 12,
                      color: AppTheme.paperMuted.withValues(alpha: 0.9),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
