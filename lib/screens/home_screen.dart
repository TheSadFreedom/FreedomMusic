import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/track_key.dart';
import '../models/artist_release.dart';
import '../models/catalog_search.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../navigation/library_navigation.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/breakpoints.dart';
import '../widgets/home_hero.dart';
import '../widgets/playlist_mosaic.dart';
import '../widgets/system_playlist_icon.dart';
import '../widgets/track_meta_links.dart';
import '../widgets/track_title_line.dart';
import '../widgets/track_overflow_menu.dart';
import 'playlists_screen.dart';
import 'release_detail_screen.dart';
import 'release_metadata_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  String _appliedQuery = '';
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _searchTimer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (_appliedQuery.isEmpty) return;
      setState(() => _appliedQuery = '');
      return;
    }
    _searchTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _appliedQuery = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final playing = context.select<PlayerService, bool>((p) => p.playing);
    final searching = _appliedQuery.trim().isNotEmpty;
    final results = searching
        ? library.searchCatalog(_appliedQuery)
        : CatalogSearch.empty;

    return HomeStage(
      playing: playing,
      child: Padding(
        padding: pagePadding(context),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _TopSearch(
                controller: _searchController,
                focusNode: _searchFocus,
                query: _query,
                onChanged: (v) {
                  setState(() => _query = v);
                  _scheduleSearch(v);
                },
                onClear: () {
                  _searchTimer?.cancel();
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _appliedQuery = '';
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: searching
                    ? KeyedSubtree(
                        key: const ValueKey('search'),
                        child: _SearchPanel(results: results),
                      )
                    : const KeyedSubtree(
                        key: ValueKey('hero'),
                        child: _LiveHero(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopSearch extends StatelessWidget {
  const _TopSearch({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          textAlign: TextAlign.start,
          style: GoogleFonts.figtree(
            color: AppTheme.paper,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: AppTheme.lime,
          decoration: InputDecoration(
            hintText: 'Треки, артисты, альбомы, плейлисты…',
            hintStyle: GoogleFonts.figtree(color: AppTheme.paperMuted),
            prefixIcon: const Icon(Icons.search, color: AppTheme.paperMuted),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close, color: AppTheme.paperMuted),
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }
}

/// Watches playback on its own so search results are not rebuilt every tick.
class _LiveHero extends StatelessWidget {
  const _LiveHero();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final playing = context.select<PlayerService, bool>(
      (p) => p.playing && p.current != null,
    );
    final current = context.select<PlayerService, Track?>((p) => p.current);
    return _CenteredHero(
      trackCount: library.tracks.length,
      empty: library.isEmpty,
      playing: playing,
      current: current,
      onPlay: library.isEmpty
          ? null
          : () {
              final player = context.read<PlayerService>();
              if (player.current != null) {
                player.togglePlayPause();
              } else {
                player.playRandomAll();
              }
            },
    );
  }
}

class _CenteredHero extends StatelessWidget {
  const _CenteredHero({
    required this.trackCount,
    required this.empty,
    required this.playing,
    required this.current,
    required this.onPlay,
  });

  final int trackCount;
  final bool empty;
  final bool playing;
  final Track? current;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final phone = isPhone(context);
    final vinylSize = phone
        ? (h * 0.28).clamp(160.0, 220.0)
        : (h * 0.34).clamp(200.0, 300.0);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'FREEDOM MUSIC',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(
                fontSize: phone ? 34 : 52,
                fontWeight: FontWeight.w800,
                height: 0.95,
                letterSpacing: phone ? 1.6 : 3.2,
                color: AppTheme.paper,
              ),
            ),
            const SizedBox(height: 14),
            if (empty)
              Text(
                'Положите треки в music и отсканируйте библиотеку.',
                textAlign: TextAlign.center,
                style: GoogleFonts.figtree(
                  color: AppTheme.paperMuted,
                  fontSize: phone ? 14 : 16,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.15,
                ),
              )
            else
              Text.rich(
                TextSpan(
                  style: GoogleFonts.figtree(
                    color: AppTheme.paperMuted,
                    fontSize: phone ? 14 : 16,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.15,
                  ),
                  children: [
                    const TextSpan(text: 'Случайный поток из '),
                    TextSpan(
                      text: '$trackCount',
                      style: const TextStyle(
                        color: AppTheme.lime,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: ' треков вашей библиотеки.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            SizedBox(height: phone ? 20 : 28),
            VinylPlayControl(
              size: vinylSize,
              playing: playing,
              enabled: onPlay != null,
              onPressed: onPlay,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 72,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: current == null
                    ? Text(
                        key: const ValueKey('idle'),
                        'Нажмите, чтобы начать',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.figtree(
                          color: AppTheme.paperMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : _NowPlaying(
                        track: current!,
                        onStop: () =>
                            context.read<PlayerService>().stopAndClear(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.track, required this.onStop});

  final Track track;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    Widget cover = Container(
      width: 52,
      height: 52,
      color: AppTheme.inkLift,
      child: const Icon(Icons.album, color: AppTheme.mossBright),
    );
    if (track.coverPath != null && File(track.coverPath!).existsSync()) {
      cover = Image.file(
        File(track.coverPath!),
        width: 52,
        height: 52,
        fit: BoxFit.cover,
      );
    }

    return TrackContextMenu(
      actions: standardTrackActions(context, track),
      child: Row(
        key: ValueKey(track.trackKey),
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: cover),
          const SizedBox(width: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'СЕЙЧАС',
                  style: GoogleFonts.figtree(
                    color: AppTheme.lime,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                TrackMetaLinks(
                  track: track,
                  titleStyle: GoogleFonts.syne(
                    color: AppTheme.paper,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  artistStyle: GoogleFonts.figtree(
                    color: AppTheme.paperMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppTheme.lime,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: Colors.black,
            child: InkWell(
              customBorder: const CircleBorder(),
              mouseCursor: SystemMouseCursors.click,
              onTap: onStop,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.stop_rounded, color: Colors.black, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchSection {
  const _SearchSection({
    required this.title,
    required this.count,
    required this.itemBuilder,
  });

  final String title;
  final int count;
  final Widget Function(BuildContext context, int index) itemBuilder;
}

class _HitStyle {
  const _HitStyle({
    required this.rowHeight,
    required this.mark,
    required this.title,
    required this.detail,
    required this.gap,
  });

  static const compact = _HitStyle(
    rowHeight: 30,
    mark: 22,
    title: 13,
    detail: 12,
    gap: 8,
  );

  static const roomy = _HitStyle(
    rowHeight: 58,
    mark: 42,
    title: 16,
    detail: 13,
    gap: 14,
  );

  final double rowHeight;
  final double mark;
  final double title;
  final double detail;
  final double gap;

  static _HitStyle of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HitStyleScope>();
    return scope?.style ?? compact;
  }
}

class _HitStyleScope extends InheritedWidget {
  const _HitStyleScope({required this.style, required super.child});

  final _HitStyle style;

  @override
  bool updateShouldNotify(_HitStyleScope oldWidget) => style != oldWidget.style;
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({required this.results});

  final CatalogSearch results;

  static const _rowHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'Ничего не найдено',
          style: GoogleFonts.figtree(color: AppTheme.paperMuted, fontSize: 16),
        ),
      );
    }

    final library = context.read<LibraryService>();
    final sections = <_SearchSection>[
      if (results.tracks.isNotEmpty)
        _SearchSection(
          title: 'Треки',
          count: results.tracks.length,
          itemBuilder: (context, index) {
            final track = results.tracks[index];
            final mark = _HitStyle.of(context).mark;
            return TrackContextMenu(
              actions: standardTrackActions(context, track),
              child: _CompactHit(
                title: track.displayTitle,
                note: track.displayNote,
                detail: track.displayArtist,
                leading: _CoverMark(path: track.coverPath, size: mark),
                onTap: () => context.read<PlayerService>().playTracks(
                  results.tracks,
                  startIndex: index,
                ),
              ),
            );
          },
        ),
      if (results.artists.isNotEmpty)
        _SearchSection(
          title: 'Артисты',
          count: results.artists.length,
          itemBuilder: (context, index) {
            final person = results.artists[index];
            final mark = _HitStyle.of(context).mark;
            return _CompactHit(
              title: person.name,
              detail: _countLabel(person.trackCount),
              leading: _PersonMark(
                photoPath: library.artistPhotoPath(person.name),
                icon: Icons.person_rounded,
                size: mark,
              ),
              onTap: () => openArtistPage(context, person.name),
            );
          },
        ),
      if (results.producers.isNotEmpty)
        _SearchSection(
          title: 'Продюсеры',
          count: results.producers.length,
          itemBuilder: (context, index) {
            final person = results.producers[index];
            final mark = _HitStyle.of(context).mark;
            return _CompactHit(
              title: person.name,
              detail: _countLabel(person.trackCount),
              leading: _PersonMark(
                photoPath: library.artistPhotoPath(person.name),
                icon: Icons.headphones_rounded,
                size: mark,
              ),
              onTap: () => openArtistPage(context, person.name, producer: true),
            );
          },
        ),
      if (results.albums.isNotEmpty)
        _SearchSection(
          title: 'Релизы',
          count: results.albums.length,
          itemBuilder: (context, index) {
            final album = results.albums[index];
            final year = album.release.year;
            final kind = releaseKindLabel(album.release.kind);
            final mark = _HitStyle.of(context).mark;
            return TrackContextMenu(
              actions: releaseMenuActions(context, album.release),
              child: _CompactHit(
                title: metaFieldText(album.release.title),
                detail: year == null
                    ? '$kind · ${album.artist}'
                    : '$kind · ${album.artist} · $year',
                leading: _CoverMark(
                  path: library.releaseCover(album.release),
                  size: mark,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReleaseDetailScreen(
                        release: album.release,
                        primaryArtist: album.artist,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      if (results.playlists.isNotEmpty)
        _SearchSection(
          title: 'Плейлисты',
          count: results.playlists.length,
          itemBuilder: (context, index) {
            final playlist = results.playlists[index];
            final mark = _HitStyle.of(context).mark;
            return _CompactHit(
              title: playlist.name,
              detail: _countLabel(playlist.trackCount),
              leading: _PlaylistMark(playlist: playlist, size: mark),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlaylistDetailScreen(playlistId: playlist.id),
                  ),
                );
              },
            );
          },
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0)
                const VerticalDivider(width: 1, color: Color(0x14F2EDE4)),
              Expanded(child: _SearchColumn(section: sections[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchColumn extends StatelessWidget {
  const _SearchColumn({required this.section});

  final _SearchSection section;

  static const _headerHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slots =
              ((constraints.maxHeight - _headerHeight) /
                      _SearchPanel._rowHeight)
                  .floor();
          final room = slots < 0 ? 0 : slots;
          final overflow = section.count > room && room > 0;
          final shown = overflow ? room - 1 : section.count.clamp(0, room);
          final hidden = section.count - shown;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _headerHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    section.count > shown
                        ? '${section.title}  ${section.count}'
                        : section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(
                      color: AppTheme.lime,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < shown; i++) section.itemBuilder(context, i),
              if (overflow)
                _CompactHit(
                  title: 'Ещё $hidden',
                  titleColor: AppTheme.lime,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _SearchMoreScreen(section: section),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchMoreScreen extends StatelessWidget {
  const _SearchMoreScreen({required this.section});

  final _SearchSection section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: _HitStyleScope(
        style: _HitStyle.roomy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 24, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    mouseCursor: SystemMouseCursors.click,
                    icon: const Icon(Icons.arrow_back, color: AppTheme.paper),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: GoogleFonts.syne(
                      color: AppTheme.paper,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 4, 28, 24),
                itemExtent: _HitStyle.roomy.rowHeight,
                itemCount: section.count,
                itemBuilder: section.itemBuilder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _countLabel(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return '$count трек';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$count трека';
  }
  return '$count треков';
}

class _CompactHit extends StatelessWidget {
  const _CompactHit({
    required this.title,
    required this.onTap,
    this.note,
    this.detail,
    this.leading,
    this.titleColor = AppTheme.paper,
  });

  final String title;
  final String? note;
  final String? detail;
  final Widget? leading;
  final Color titleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _HitStyle.of(context);
    return SizedBox(
      height: style.rowHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: onTap,
          child: Row(
            children: [
              if (leading != null) ...[leading!, SizedBox(width: style.gap)],
              Expanded(
                child: TrackTitleLine(
                  title: title,
                  note: note,
                  style: GoogleFonts.figtree(
                    color: titleColor,
                    fontWeight: FontWeight.w600,
                    fontSize: style.title,
                  ),
                ),
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                SizedBox(width: style.gap),
                Flexible(
                  child: Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: style.detail,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonMark extends StatelessWidget {
  const _PersonMark({
    required this.photoPath,
    required this.icon,
    this.size = 22,
  });

  final String? photoPath;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    Widget child = Icon(icon, color: AppTheme.ink, size: size * 0.55);
    if (path != null && File(path).existsSync()) {
      child = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    return ClipOval(
      child: ColoredBox(
        color: AppTheme.lime,
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }
}

class _CoverMark extends StatelessWidget {
  const _CoverMark({required this.path, this.size = 22});

  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget child = Icon(
      Icons.album,
      color: AppTheme.mossBright,
      size: size * 0.7,
    );
    final cover = path;
    if (cover != null && File(cover).existsSync()) {
      child = Image.file(
        File(cover),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: AppTheme.inkLift,
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }
}

class _PlaylistMark extends StatelessWidget {
  const _PlaylistMark({required this.playlist, this.size = 22});

  final Playlist playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (playlist.systemKind) {
      Playlist.kindNew => (const Color(0xFFFFDB4D), const Color(0xFF141414)),
      Playlist.kindIncomplete => (AppTheme.lime, const Color(0xFF141414)),
      Playlist.kindNoProducer => (AppTheme.mossBright, const Color(0xFF141414)),
      Playlist.kindMissingGenre => (
        const Color(0xFFFFDB4D),
        const Color(0xFF141414),
      ),
      Playlist.kindMissingLyrics => (
        AppTheme.mossBright,
        const Color(0xFF141414),
      ),
      Playlist.kindMetadataReady => (AppTheme.lime, const Color(0xFF141414)),
      Playlist.kindTrash => (const Color(0xFF3A3330), AppTheme.paper),
      _ => (AppTheme.inkLift, AppTheme.mossBright),
    };
    final cover = playlist.coverPath;
    Widget child = SystemPlaylistIcon(
      kind: playlist.systemKind,
      color: foreground,
      size: size * 0.62,
    );
    if (cover != null && cover.isNotEmpty && File(cover).existsSync()) {
      child = Image.file(
        File(cover),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    } else if (!playlist.isSystem) {
      child = PlaylistMosaicLoader(
        playlistId: playlist.id,
        fallback: child,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: background,
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }
}
