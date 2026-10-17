import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/track_key.dart';
import '../models/artist_release.dart';
import '../models/track.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/image_pick.dart';
import '../utils/playlist_actions.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/listen_actions.dart';
import '../widgets/track_cover_play.dart';
import '../widgets/track_meta_links.dart';
import 'release_detail_screen.dart';

/// Yandex Music–inspired artist page.
class ArtistDetailScreen extends StatefulWidget {
  const ArtistDetailScreen({
    super.key,
    required this.artist,
    required this.tracks,
    required this.playCount,
    required this.chartRank,
    required this.trackPlayCounts,
    this.byProducer = false,
  });

  final String artist;
  final List<Track> tracks;
  final int playCount;
  final int chartRank;
  final Map<String, int> trackPlayCounts;
  final bool byProducer;

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  Map<String, int> _listenMs = const {};
  bool _listenMsLoaded = false;

  List<Track> _liveTracks(LibraryService library) {
    final want = widget.artist.toLowerCase();
    final live = library.tracks
        .where(
          (t) => widget.byProducer
              ? producerNames(t.producer).any(
                  (name) =>
                      library.artistCardName(name).toLowerCase() == want,
                )
              : t.artists.any(
                  (name) =>
                      library.artistCardName(name).toLowerCase() == want,
                ),
        )
        .toList(growable: false);
    return live.isEmpty ? widget.tracks : live;
  }

  ArtistReleaseGroups _producerGroups(List<Track> tracks) {
    final releases = buildReleases(tracks);
    return ArtistReleaseGroups(
      albums: releases.where((r) => r.kind == ReleaseKind.album).toList(),
      singles: releases.where((r) => r.kind == ReleaseKind.single).toList(),
      appearances: const [],
    );
  }

  List<Track> _popularOf(List<Track> tracks) {
    return List<Track>.from(tracks)
      ..sort((a, b) {
        final ca = widget.trackPlayCounts[a.trackKey] ?? 0;
        final cb = widget.trackPlayCounts[b.trackKey] ?? 0;
        if (cb != ca) return cb.compareTo(ca);
        return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listenMsLoaded) return;
    _listenMsLoaded = true;
    context.read<LibraryService>().listenMsAllTime().then((map) {
      if (!mounted) return;
      setState(() => _listenMs = map);
    });
  }

  String? _resolvePhoto(LibraryService library, List<Track> popular) {
    final custom = library.artistPhotoPath(widget.artist);
    if (custom != null) return custom;
    for (final t in popular) {
      final p = t.coverPath;
      if (p != null && File(p).existsSync()) return p;
    }
    return null;
  }

  Future<void> _mergeArtist(BuildContext context) async {
    final library = context.read<LibraryService>();
    final others = library
        .tracksByArtist()
        .keys
        .where((n) => n.toLowerCase() != widget.artist.toLowerCase())
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (others.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Нет других артистов для объединения',
            style: GoogleFonts.figtree(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.inkLift,
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.inkLift,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _MergeArtistSheet(
        currentArtist: widget.artist,
        candidates: others,
      ),
    );
    if (selected == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.inkLift,
        title: Text(
          'Объединить артистов?',
          style: GoogleFonts.syne(
            color: AppTheme.paper,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '«$selected» попадёт на карточку «${widget.artist}». '
          'В треках останется исходное имя. '
          'Поиск найдёт и старое, и новое название.',
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: GoogleFonts.figtree(color: AppTheme.paperMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Объединить',
              style: GoogleFonts.figtree(
                color: const Color(0xFFFFDB4D),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await library.mergeArtists(into: widget.artist, from: selected);
    if (!context.mounted) return;

    final byArtist = library.tracksByArtist();
    var tracks = <Track>[];
    for (final e in byArtist.entries) {
      if (e.key.toLowerCase() == widget.artist.toLowerCase()) {
        tracks = e.value;
        break;
      }
    }
    final counts = await library.playCountsAllTime();
    if (!context.mounted) return;

    final plays = tracks.fold<int>(
      0,
      (sum, t) => sum + (counts[t.trackKey] ?? 0),
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ArtistDetailScreen(
          artist: widget.artist,
          tracks: tracks,
          playCount: plays,
          chartRank: widget.chartRank,
          trackPlayCounts: counts,
        ),
      ),
    );
  }

  Future<void> _editPhoto(BuildContext context) async {
    final library = context.read<LibraryService>();
    final hasCustom = library.artistPhotoPath(widget.artist) != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.inkLift,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Выбрать фото'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (hasCustom)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Сбросить фото'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'pick') {
      final bytes = await pickImageBytes();
      if (bytes == null || !context.mounted) return;
      await library.setArtistPhoto(widget.artist, bytes);
    } else if (action == 'clear') {
      await library.clearArtistPhoto(widget.artist);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    final library = context.watch<LibraryService>();
    final tracks = _liveTracks(library);
    final popular = _popularOf(tracks);
    final groups = widget.byProducer
        ? _producerGroups(tracks)
        : groupArtistReleases(
            artistTracks: tracks,
            libraryTracks: library.tracks,
            isThisArtist: (name) =>
                library.artistCardName(name).toLowerCase() ==
                widget.artist.toLowerCase(),
            cardName: library.artistCardName,
          );
    final albums = groups.albums;
    final singles = groups.singles;
    final appearances = groups.appearances;
    final photoPath = _resolvePhoto(library, popular);

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.ink.withValues(alpha: 0.92),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              widget.artist,
              style: GoogleFonts.syne(fontWeight: FontWeight.w700),
            ),
          ),
          SliverToBoxAdapter(child: _Header(
            artist: widget.artist,
            photoPath: photoPath,
            chartRank: widget.chartRank,
            trackCount: tracks.length,
            onListen: () => player.playTracks(popular, shuffle: false),
            onShuffle: () => player.playTracks(tracks, shuffle: true),
            onEditPhoto: () => _editPhoto(context),
            onMerge: widget.byProducer ? null : () => _mergeArtist(context),
            roleLabel: widget.byProducer ? 'Продюсер' : 'Артист',
          )),
          if (popular.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionTitle(
                title: 'Популярные треки',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ArtistAllTracksScreen(
                        artist: widget.artist,
                        tracks: popular,
                        trackPlayCounts: widget.trackPlayCounts,
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = popular[index];
                  final plays = widget.trackPlayCounts[track.trackKey] ?? 0;
                  return _PopularTrackRow(
                    index: index + 1,
                    track: track,
                    plays: plays,
                    onTap: () =>
                        player.playTracks(popular, startIndex: index),
                  );
                },
                childCount: popular.length.clamp(0, 10),
              ),
            ),
          ],
          if (albums.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: _SectionTitle(
                title: 'Альбомы',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ArtistAllReleasesScreen(
                        artist: widget.artist,
                        sectionTitle: 'Альбомы',
                        releases: albums,
                        listenMsByKey: _listenMs,
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: _ReleaseCarousel(
                releases: albums,
                artist: widget.artist,
                listenMsByKey: _listenMs,
              ),
            ),
          ],
          if (singles.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: _SectionTitle(
                title: 'Синглы',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ArtistAllReleasesScreen(
                        artist: widget.artist,
                        sectionTitle: 'Синглы',
                        releases: singles,
                        listenMsByKey: _listenMs,
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: _ReleaseCarousel(
                releases: singles,
                artist: widget.artist,
                listenMsByKey: _listenMs,
              ),
            ),
          ],
          if (appearances.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(
              child: _SectionTitle(
                title: 'Участие в релизах',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ArtistAllReleasesScreen(
                        artist: widget.artist,
                        sectionTitle: 'Участие в релизах',
                        releases: appearances,
                        listenMsByKey: _listenMs,
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: _ReleaseCarousel(
                releases: appearances,
                artist: widget.artist,
                listenMsByKey: _listenMs,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.artist,
    required this.photoPath,
    required this.chartRank,
    required this.trackCount,
    required this.onListen,
    required this.onShuffle,
    required this.onEditPhoto,
    this.onMerge,
    this.roleLabel = 'Артист',
  });

  final String artist;
  final String? photoPath;
  final int chartRank;
  final int trackCount;
  final VoidCallback onListen;
  final VoidCallback onShuffle;
  final VoidCallback onEditPhoto;
  final VoidCallback? onMerge;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;

    final photo = _ArtistPhoto(
      path: photoPath,
      size: wide ? 180 : 140,
      onEdit: onEditPhoto,
    );

    final info = Column(
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          roleLabel,
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          artist,
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: GoogleFonts.syne(
            color: AppTheme.paper,
            fontSize: wide ? 44 : 32,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
            _MetaChip(
              icon: Icons.emoji_events_outlined,
              text: chartRank > 0 ? '$chartRank место в топе' : 'Нет в топе',
            ),
            _MetaChip(
              icon: Icons.music_note_outlined,
              text: '$trackCount треков',
            ),
          ],
        ),
        const SizedBox(height: 20),
        ListenActions(
          onListen: onListen,
          onShuffle: onShuffle,
          center: !wide,
          extra: [
            if (onMerge != null)
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: ListenActions.yellow,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.zero,
                ),
                onPressed: onMerge,
                icon: const Icon(Icons.merge_type_rounded, size: 22),
              ),
          ],
        ),
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          const Positioned.fill(
            child: AmbientBackdrop(
              accent: Color(0xFF3D6B8B),
              secondary: Color(0xFF2A4A5C),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      photo,
                      const SizedBox(width: 28),
                      Expanded(child: info),
                    ],
                  )
                : Column(
                    children: [
                      photo,
                      const SizedBox(height: 20),
                      info,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ArtistPhoto extends StatefulWidget {
  const _ArtistPhoto({
    required this.path,
    required this.size,
    required this.onEdit,
  });

  final String? path;
  final double size;
  final VoidCallback onEdit;

  @override
  State<_ArtistPhoto> createState() => _ArtistPhotoState();
}

class _ArtistPhotoState extends State<_ArtistPhoto> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget image = ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(
        Icons.person,
        size: widget.size * 0.45,
        color: AppTheme.mossBright,
      ),
    );
    if (widget.path != null && File(widget.path!).existsSync()) {
      image = Image.file(File(widget.path!), fit: BoxFit.cover);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onEdit,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (_hover) ...[
                  ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                  const Center(
                    child: Icon(
                      Icons.edit_outlined,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.paperMuted),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Text(
              title,
              style: GoogleFonts.syne(
                color: AppTheme.paper,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppTheme.paperMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _PopularTrackRow extends StatelessWidget {
  const _PopularTrackRow({
    required this.index,
    required this.track,
    required this.plays,
    required this.onTap,
  });

  final int index;
  final Track track;
  final int plays;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$index',
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
              plays > 0 ? NumberFormat.compact(locale: 'ru').format(plays) : '—',
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
    );
  }
}

class _ReleaseCarousel extends StatefulWidget {
  const _ReleaseCarousel({
    required this.releases,
    required this.artist,
    required this.listenMsByKey,
  });

  final List<ArtistRelease> releases;
  final String artist;
  final Map<String, int> listenMsByKey;

  @override
  State<_ReleaseCarousel> createState() => _ReleaseCarouselState();
}

class _ReleaseCarouselState extends State<_ReleaseCarousel> {
  final _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
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
    final forward = pos.pixels < pos.maxScrollExtent - 4;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _page(bool forward) {
    if (!_controller.hasClients) return;
    final delta = forward ? 320.0 : -320.0;
    final target = (_controller.offset + delta)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  static const _coverSize = 148.0;
  static const _arrowSize = 40.0;

  @override
  Widget build(BuildContext context) {
    // Center arrows on the cover, not the full card (cover + captions).
    final arrowTop = (_coverSize - _arrowSize) / 2;

    return SizedBox(
      height: 252,
      child: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _syncArrows();
              return false;
            },
            child: ListView.separated(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: widget.releases.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final release = widget.releases[index];
                final credit = _releaseArtistLine(release, widget.artist);
                return _ReleaseCard(
                  release: release,
                  artist: credit,
                  listenCount: releaseListenCount(release, widget.listenMsByKey),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReleaseDetailScreen(
                          release: release,
                          primaryArtist: credit,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_canBack)
            Positioned(
              left: 4,
              top: arrowTop,
              child: _CarouselArrow(
                forward: false,
                onPressed: () => _page(false),
              ),
            ),
          if (_canForward)
            Positioned(
              right: 4,
              top: arrowTop,
              child: _CarouselArrow(
                forward: true,
                onPressed: () => _page(true),
              ),
            ),
        ],
      ),
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({
    required this.forward,
    required this.onPressed,
  });

  final bool forward;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // const Icon keeps glyphs through release icon tree-shaking.
    final icon = forward
        ? const Icon(Icons.chevron_right_rounded, size: 28, color: Color(0xFF1A1A1A))
        : const Icon(Icons.chevron_left_rounded, size: 28, color: Color(0xFF1A1A1A));

    return Material(
      color: Colors.white.withValues(alpha: 0.82),
      shape: const CircleBorder(),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        hoverColor: Colors.white.withValues(alpha: 0.2),
        splashColor: Colors.white.withValues(alpha: 0.35),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(child: icon),
        ),
      ),
    );
  }
}

String _releaseArtistLine(ArtistRelease release, String pageArtist) {
  final names = releaseAlbumArtists(release);
  if (names.isNotEmpty) return names.join(', ');
  final credit = release.credit?.trim();
  if (credit != null && credit.isNotEmpty) return credit;
  return pageArtist;
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.artist,
    required this.onTap,
    this.listenCount = 0,
    this.width = 148,
  });

  final ArtistRelease release;
  final String artist;
  final VoidCallback onTap;
  final int listenCount;
  /// Null expands to the parent (grid cell).
  final double? width;

  @override
  Widget build(BuildContext context) {
    Widget cover = ColoredBox(
      color: AppTheme.inkLift,
      child: const Icon(Icons.album, color: AppTheme.mossBright, size: 40),
    );
    if (release.coverPath != null && File(release.coverPath!).existsSync()) {
      cover = Image.file(File(release.coverPath!), fit: BoxFit.cover);
    }

    final kind =
        release.kind == ReleaseKind.single ? 'Сингл' : 'Альбом';

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(aspectRatio: 1, child: cover),
              ),
            ),
            const SizedBox(height: 10),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 12,
              ),
            ),
            Text(
              [
                if (release.year != null && release.year! > 0) '${release.year}',
                kind,
                if (listenCount > 0) formatListenCount(listenCount),
              ].join(' · '),
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

/// Full album / single grid for an artist.
class _ArtistAllReleasesScreen extends StatelessWidget {
  const _ArtistAllReleasesScreen({
    required this.artist,
    required this.sectionTitle,
    required this.releases,
    required this.listenMsByKey,
  });

  final String artist;
  final String sectionTitle;
  final List<ArtistRelease> releases;
  final Map<String, int> listenMsByKey;

  void _open(BuildContext context, ArtistRelease release, String credit) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReleaseDetailScreen(
          release: release,
          primaryArtist: credit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      appBar: AppBar(
        backgroundColor: AppTheme.ink,
        title: Text(
          '$sectionTitle $artist',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 18,
          crossAxisSpacing: 14,
          childAspectRatio: 0.62,
        ),
        itemCount: releases.length,
        itemBuilder: (context, index) {
          final release = releases[index];
          final credit = _releaseArtistLine(release, artist);
          return _ReleaseCard(
            release: release,
            artist: credit,
            width: null,
            listenCount: releaseListenCount(release, listenMsByKey),
            onTap: () => _open(context, release, credit),
          );
        },
      ),
    );
  }
}

class _MergeArtistSheet extends StatefulWidget {
  const _MergeArtistSheet({
    required this.currentArtist,
    required this.candidates,
  });

  final String currentArtist;
  final List<String> candidates;

  @override
  State<_MergeArtistSheet> createState() => _MergeArtistSheetState();
}

class _MergeArtistSheetState extends State<_MergeArtistSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((n) => n.toLowerCase().contains(q))
            .toList();
    final height = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Объединить с «${widget.currentArtist}»',
                style: GoogleFonts.syne(
                  color: AppTheme.paper,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Выберите артиста, которого нужно добавить на эту карточку. '
                'Имена в треках не меняются.',
                style: GoogleFonts.figtree(
                  color: AppTheme.paperMuted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.figtree(color: AppTheme.paper),
                decoration: InputDecoration(
                  hintText: 'Поиск артиста',
                  hintStyle: GoogleFonts.figtree(color: AppTheme.paperMuted),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppTheme.paperMuted.withValues(alpha: 0.9),
                  ),
                  filled: true,
                  fillColor: AppTheme.ink.withValues(alpha: 0.45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Ничего не найдено',
                        style: GoogleFonts.figtree(color: AppTheme.paperMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final name = filtered[index];
                        return ListTile(
                          title: Text(
                            name,
                            style: GoogleFonts.figtree(
                              color: AppTheme.paper,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full track list for an artist (from «Популярные треки»).
class _ArtistAllTracksScreen extends StatelessWidget {
  const _ArtistAllTracksScreen({
    required this.artist,
    required this.tracks,
    required this.trackPlayCounts,
  });

  final String artist;
  final List<Track> tracks;
  final Map<String, int> trackPlayCounts;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();

    return Scaffold(
      backgroundColor: AppTheme.ink,
      appBar: AppBar(
        backgroundColor: AppTheme.ink,
        title: Text(
          'Все треки',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Слушать',
            onPressed: tracks.isEmpty
                ? null
                : () => player.playTracks(tracks, shuffle: false),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 48),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          final plays = trackPlayCounts[track.trackKey] ?? 0;
          return _PopularTrackRow(
            index: index + 1,
            track: track,
            plays: plays,
            onTap: () => player.playTracks(tracks, startIndex: index),
          );
        },
      ),
    );
  }
}
