import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/artist_release.dart';
import '../models/track.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/listen_actions.dart';
import '../widgets/screen_title.dart';
import '../widgets/track_overflow_menu.dart';
import 'artist_detail_screen.dart';
import 'release_detail_screen.dart';
import 'release_metadata_editor_screen.dart';

final _count = NumberFormat.decimalPattern();

List<_ArtistRow> _battleArtistRows(
  Map<String, List<Track>> grouped,
  Map<String, int> playCounts,
) {
  final rows = [
    for (final entry in grouped.entries)
      _ArtistRow(
        name: entry.key,
        tracks: entry.value,
        playCount: entry.value.fold<int>(
          0,
          (sum, track) => sum + (playCounts[track.trackKey] ?? 0),
        ),
        rank: 0,
      ),
  ]..sort((a, b) {
      final byPlay = b.playCount.compareTo(a.playCount);
      if (byPlay != 0) return byPlay;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  return [
    for (var i = 0; i < rows.length; i++)
      _ArtistRow(
        name: rows[i].name,
        tracks: rows[i].tracks,
        playCount: rows[i].playCount,
        rank: i + 1,
      ),
  ];
}

/// Battle-Rap artists and releases on one page.
class BattlesScreen extends StatefulWidget {
  const BattlesScreen({super.key});

  @override
  State<BattlesScreen> createState() => _BattlesScreenState();
}

class _BattlesScreenState extends State<BattlesScreen> {
  final _search = TextEditingController();
  String _query = '';
  Map<String, int> _playCounts = {};
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _loadPlayCounts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPlayCounts() async {
    final counts = await context.read<LibraryService>().playCountsAllTime();
    if (!mounted) return;
    setState(() {
      _playCounts = counts;
      _loadingCounts = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final tracks = library.battleTracks;
    if (library.isEmpty) {
      return const Center(
        child: Text('Нет треков. Сканируйте папку music в Настройках.'),
      );
    }

    final artists = _artistRows(library);
    final releases = _releases(library, tracks);
    final q = _query.trim().toLowerCase();
    final shownArtists = q.isEmpty
        ? artists
        : artists
            .where((row) => library.artistCardMatchesQuery(row.name, _query))
            .toList(growable: false);
    final shownReleases = q.isEmpty
        ? releases
        : releases
            .where((row) {
              final title = row.release.title.toLowerCase();
              final artist = row.artist.toLowerCase();
              return title.contains(q) || artist.contains(q);
            })
            .toList(growable: false);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenTitle(
            title: 'Баттлы',
            trailing: Text(
              formatTrackCount(tracks.length),
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 20, 8),
            child: Row(
              children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 12),
                ListenActions(
                  onListen: tracks.isEmpty
                      ? null
                      : () => context.read<PlayerService>().playTracks(tracks),
                  onShuffle: tracks.isEmpty
                      ? null
                      : () => context
                          .read<PlayerService>()
                          .playTracks(tracks, shuffle: true),
                ),
              ],
            ),
          ),
        ),
        if (tracks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text('Нет треков с жанром Battle-Rap.'),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: _SectionLabel(
              'Артисты',
              onTap: artists.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const _BattleArtistsScreen(),
                        ),
                      );
                    },
            ),
          ),
          if (_loadingCounts)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (shownArtists.isEmpty)
            const SliverToBoxAdapter(child: _EmptyLine('Ничего не найдено'))
          else
            SliverToBoxAdapter(
              child: _ArtistCarousel(
                rows: shownArtists,
                photoOf: (row) =>
                    library.artistPhotoPath(row.name) ??
                    coverFromTracks(row.tracks),
                onTap: (row) => _openArtist(context, row),
              ),
            ),
          const SliverToBoxAdapter(child: _SectionLabel('Релизы')),
          if (shownReleases.isEmpty)
            const SliverToBoxAdapter(child: _EmptyLine('Ничего не найдено'))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final count = _columns(constraints.crossAxisExtent, 180);
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 18,
                      childAspectRatio: 0.62,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final row = shownReleases[index];
                        return _ReleaseTile(
                          release: row.release,
                          artist: row.artist,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ReleaseDetailScreen(
                                  release: row.release,
                                  primaryArtist: row.artist,
                                ),
                              ),
                            );
                          },
                        );
                      },
                      childCount: shownReleases.length,
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  void _openArtist(BuildContext context, _ArtistRow row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistDetailScreen(
          artist: row.name,
          tracks: row.tracks,
          playCount: row.playCount,
          chartRank: row.rank,
          trackPlayCounts: _playCounts,
          battleOnly: true,
        ),
      ),
    );
  }

  Widget _searchField() {
    return SizedBox(
      height: ListenActions.buttonHeight,
      child: TextField(
        controller: _search,
        onChanged: (value) => setState(() => _query = value),
        style: GoogleFonts.figtree(
          color: AppTheme.paper,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: AppTheme.lime,
        decoration: InputDecoration(
          hintText: 'Поиск артиста или релиза',
          hintStyle: GoogleFonts.figtree(color: AppTheme.paperMuted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppTheme.paperMuted,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () {
                    _search.clear();
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
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  List<Track>? _releaseSource;
  List<_ReleaseRow>? _releaseCache;

  List<_ArtistRow> _artistRows(LibraryService library) {
    return _battleArtistRows(library.battleTracksByArtist(), _playCounts);
  }

  List<_ReleaseRow> _releases(LibraryService library, List<Track> tracks) {
    if (identical(tracks, _releaseSource) && _releaseCache != null) {
      return _releaseCache!;
    }
    final grouped = library.battleTracksByArtist();

    final seen = <String>{};
    final rows = <_ReleaseRow>[];
    for (final entry in grouped.entries) {
      final want = entry.key.toLowerCase();
      final groups = groupArtistReleases(
        artistTracks: entry.value,
        libraryTracks: tracks,
        isThisArtist: (name) =>
            library.artistCardName(name).toLowerCase() == want,
        cardName: library.artistCardName,
      );
      for (final release in [
        ...groups.albums,
        ...groups.eps,
        ...groups.singles,
      ]) {
        if (!seen.add(releaseCoverKey(release))) continue;
        final names = releaseAlbumArtists(release);
        rows.add(
          _ReleaseRow(
            release: release,
            artist: names.isEmpty ? entry.key : names.join(', '),
          ),
        );
      }
    }
    rows.sort((a, b) => compareReleasesByYearDesc(a.release, b.release));
    _releaseSource = tracks;
    _releaseCache = rows;
    return rows;
  }
}

int _columns(double width, double cell) {
  final count = (width / cell).floor();
  if (count < 2) return 2;
  if (count > 8) return 8;
  return count;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, {this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: InkWell(
        onTap: onTap,
        mouseCursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: Row(
          children: [
            Text(
              title,
              style: GoogleFonts.syne(
                color: AppTheme.paper,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, color: AppTheme.paperMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Text(
        text,
        style: GoogleFonts.figtree(
          color: AppTheme.paperMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
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
}

class _ReleaseRow {
  const _ReleaseRow({required this.release, required this.artist});

  final ArtistRelease release;
  final String artist;
}

class _ArtistCircle extends StatelessWidget {
  const _ArtistCircle({
    required this.row,
    required this.photoPath,
    required this.onTap,
  });

  static const diameter = 72.0;

  final _ArtistRow row;
  final String? photoPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.person_rounded,
      color: AppTheme.paperMuted.withValues(alpha: 0.7),
      size: 28,
    );
    Widget avatar = fallback;
    final path = photoPath;
    if (path != null) {
      avatar = fileCover(
        context,
        path,
        logicalSize: _ArtistCircle.diameter,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    final meta = GoogleFonts.figtree(
      color: AppTheme.paperMuted,
      fontWeight: FontWeight.w600,
      fontSize: 10,
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
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _ArtistCircle.diameter,
                height: _ArtistCircle.diameter,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppTheme.inkLift,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(child: avatar),
                ),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${row.rank} ',
                      style: GoogleFonts.figtree(
                        color: AppTheme.paperMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                    TextSpan(
                      text: row.name,
                      style: GoogleFonts.figtree(
                        color: AppTheme.paper,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_count.format(row.tracks.length), style: meta),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.music_note_rounded,
                      size: 12,
                      color: AppTheme.paperMuted.withValues(alpha: 0.9),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text('–', style: meta),
                    ),
                    Text(_count.format(row.playCount), style: meta),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.headphones_rounded,
                      size: 12,
                      color: AppTheme.paperMuted,
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

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({
    required this.release,
    required this.artist,
    required this.onTap,
  });

  final ArtistRelease release;
  final String artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget cover = const ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(Icons.album, color: AppTheme.mossBright, size: 40),
    );
    final path = context.read<LibraryService>().releaseCover(release);
    if (path != null && File(path).existsSync()) {
      cover = fileCover(context, path, logicalSize: 160);
    }
    final year = release.year;
    final caption = year == null || year <= 0
        ? releaseKindLabel(release.kind)
        : '${releaseKindLabel(release.kind)} · $year';

    return TrackContextMenu(
      actions: releaseMenuActions(context, release),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(aspectRatio: 1, child: cover),
            ),
            const SizedBox(height: 8),
            Text(
              release.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.figtree(
                color: AppTheme.paper,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 12,
              ),
            ),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistCarousel extends StatefulWidget {
  const _ArtistCarousel({
    required this.rows,
    required this.photoOf,
    required this.onTap,
  });

  final List<_ArtistRow> rows;
  final String? Function(_ArtistRow row) photoOf;
  final ValueChanged<_ArtistRow> onTap;

  @override
  State<_ArtistCarousel> createState() => _ArtistCarouselState();
}

class _ArtistCarouselState extends State<_ArtistCarousel> {
  final _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;

  static const _itemWidth = 108.0;
  static const _height = 118.0;
  static const _arrow = 36.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void didUpdateWidget(_ArtistCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncArrows);
    _controller.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final back = pos.pixels > 4;
    final forward = pos.maxScrollExtent > 4 && pos.pixels < pos.maxScrollExtent - 4;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _page(bool forward) {
    if (!_controller.hasClients) return;
    final delta = forward ? _itemWidth * 3 : -_itemWidth * 3;
    final target = (_controller.offset + delta).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final arrowTop = (_ArtistCircle.diameter - _arrow) / 2;
    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.rows.length,
            itemBuilder: (context, index) {
              final row = widget.rows[index];
              return SizedBox(
                width: _itemWidth,
                child: _ArtistCircle(
                  row: row,
                  photoPath: widget.photoOf(row),
                  onTap: () => widget.onTap(row),
                ),
              );
            },
          ),
          if (_canBack)
            Positioned(
              left: 4,
              top: arrowTop,
              child: _CarouselArrow(forward: false, onPressed: () => _page(false)),
            ),
          if (_canForward)
            Positioned(
              right: 4,
              top: arrowTop,
              child: _CarouselArrow(forward: true, onPressed: () => _page(true)),
            ),
        ],
      ),
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({required this.forward, required this.onPressed});

  final bool forward;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.82),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        mouseCursor: SystemMouseCursors.click,
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: forward
              ? const Icon(
                  Icons.chevron_right_rounded,
                  size: 26,
                  color: Color(0xFF1A1A1A),
                )
              : const Icon(
                  Icons.chevron_left_rounded,
                  size: 26,
                  color: Color(0xFF1A1A1A),
                ),
        ),
      ),
    );
  }
}

class _BattleArtistsScreen extends StatefulWidget {
  const _BattleArtistsScreen();

  @override
  State<_BattleArtistsScreen> createState() => _BattleArtistsScreenState();
}

class _BattleArtistsScreenState extends State<_BattleArtistsScreen> {
  Map<String, int> _playCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await context.read<LibraryService>().playCountsAllTime();
    if (!mounted) return;
    setState(() => _playCounts = counts);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final rows = _battleArtistRows(
      library.battleTracksByArtist(),
      _playCounts,
    );
    return Scaffold(
      backgroundColor: AppTheme.ink,
      appBar: AppBar(
        backgroundColor: AppTheme.ink,
        title: Text(
          'Артисты',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          mainAxisSpacing: 16,
          crossAxisSpacing: 8,
          childAspectRatio: 0.78,
        ),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return _ArtistCircle(
            row: row,
            photoPath:
                library.artistPhotoPath(row.name) ?? coverFromTracks(row.tracks),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArtistDetailScreen(
                    artist: row.name,
                    tracks: row.tracks,
                    playCount: row.playCount,
                    chartRank: row.rank,
                    trackPlayCounts: _playCounts,
                    battleOnly: true,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
