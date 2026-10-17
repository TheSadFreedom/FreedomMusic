import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/catalog_search.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../navigation/library_navigation.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/breakpoints.dart';
import '../widgets/home_hero.dart';
import '../widgets/track_meta_links.dart';
import '../widgets/track_tile.dart';
import 'playlists_screen.dart';
import 'release_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final playing = context.select<PlayerService, bool>((p) => p.playing);
    final searching = _query.trim().isNotEmpty;
    final results = searching ? library.searchCatalog(_query) : CatalogSearch.empty;

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
                onChanged: (v) => setState(() => _query = v),
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
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
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: _SearchPanel(results: results),
                          ),
                        ),
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
    final current = context.select<PlayerService, Track?>(
      (p) => p.current,
    );
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
  const _NowPlaying({
    required this.track,
    required this.onStop,
  });

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

    return Row(
      key: ValueKey(track.trackKey),
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: cover,
        ),
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
              child: Icon(
                Icons.stop_rounded,
                color: Colors.black,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({required this.results});

  final CatalogSearch results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'Ничего не найдено',
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            fontSize: 16,
          ),
        ),
      );
    }

    final library = context.read<LibraryService>();
    var first = true;
    Widget header(String title) {
      final top = first ? 12.0 : 20.0;
      first = false;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, top, 16, 4),
        child: Text(
          title,
          style: GoogleFonts.syne(
            color: AppTheme.lime,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CustomScrollView(
          slivers: [
            if (results.tracks.isNotEmpty) ...[
              SliverToBoxAdapter(child: header('Треки')),
              SliverFixedExtentList(
                itemExtent: 64,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = results.tracks[index];
                    return TrackTile(
                      track: track,
                      onTap: () => context.read<PlayerService>().playTracks(
                            results.tracks,
                            startIndex: index,
                          ),
                    );
                  },
                  childCount: results.tracks.length,
                ),
              ),
            ],
            if (results.artists.isNotEmpty) ...[
              SliverToBoxAdapter(child: header('Артисты')),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final person = results.artists[index];
                    return _SearchHit(
                      title: person.name,
                      subtitle: _countLabel(person.trackCount),
                      leading: _PersonMark(
                        photoPath: library.artistPhotoPath(person.name),
                        icon: Icons.person_rounded,
                      ),
                      onTap: () => openArtistPage(context, person.name),
                    );
                  },
                  childCount: results.artists.length,
                ),
              ),
            ],
            if (results.producers.isNotEmpty) ...[
              SliverToBoxAdapter(child: header('Продюсеры')),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final person = results.producers[index];
                    return _SearchHit(
                      title: person.name,
                      subtitle: _countLabel(person.trackCount),
                      leading: _PersonMark(
                        photoPath: library.artistPhotoPath(person.name),
                        icon: Icons.headphones_rounded,
                      ),
                      onTap: () => openArtistPage(
                        context,
                        person.name,
                        producer: true,
                      ),
                    );
                  },
                  childCount: results.producers.length,
                ),
              ),
            ],
            if (results.albums.isNotEmpty) ...[
              SliverToBoxAdapter(child: header('Альбомы')),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final album = results.albums[index];
                    final year = album.release.year;
                    return _SearchHit(
                      title: album.release.title,
                      subtitle: year == null
                          ? album.artist
                          : '${album.artist} · $year',
                      leading: _CoverMark(path: album.release.coverPath),
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
                    );
                  },
                  childCount: results.albums.length,
                ),
              ),
            ],
            if (results.playlists.isNotEmpty) ...[
              SliverToBoxAdapter(child: header('Плейлисты')),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final playlist = results.playlists[index];
                    return _SearchHit(
                      title: playlist.name,
                      subtitle: _countLabel(playlist.trackCount),
                      leading: _PlaylistMark(playlist: playlist),
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
                  childCount: results.playlists.length,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
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

class _SearchHit extends StatelessWidget {
  const _SearchHit({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.figtree(
                        color: AppTheme.paper,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.figtree(
                        color: AppTheme.paperMuted,
                        fontSize: 13,
                      ),
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

class _PersonMark extends StatelessWidget {
  const _PersonMark({required this.photoPath, required this.icon});

  final String? photoPath;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    Widget child = Icon(icon, color: AppTheme.ink, size: 22);
    if (path != null && File(path).existsSync()) {
      child = Image.file(File(path), width: 40, height: 40, fit: BoxFit.cover);
    }
    return ClipOval(
      child: ColoredBox(
        color: AppTheme.lime,
        child: SizedBox(width: 40, height: 40, child: child),
      ),
    );
  }
}

class _CoverMark extends StatelessWidget {
  const _CoverMark({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    Widget child = const Icon(Icons.album, color: AppTheme.mossBright, size: 22);
    final cover = path;
    if (cover != null && File(cover).existsSync()) {
      child = Image.file(File(cover), width: 40, height: 40, fit: BoxFit.cover);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: AppTheme.inkLift,
        child: SizedBox(width: 40, height: 40, child: child),
      ),
    );
  }
}

class _PlaylistMark extends StatelessWidget {
  const _PlaylistMark({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground, IconData icon) = switch (playlist.systemKind) {
      Playlist.kindNew => (
          const Color(0xFFFFDB4D),
          const Color(0xFF141414),
          Icons.fiber_new_rounded,
        ),
      Playlist.kindIncomplete => (
          AppTheme.lime,
          const Color(0xFF141414),
          Icons.article_outlined,
        ),
      Playlist.kindTrash => (
          const Color(0xFF3A3330),
          AppTheme.paper,
          Icons.delete_outline_rounded,
        ),
      _ => (AppTheme.inkLift, AppTheme.mossBright, Icons.queue_music),
    };
    final cover = playlist.coverPath;
    Widget child = Icon(icon, color: foreground, size: 22);
    if (cover != null && cover.isNotEmpty && File(cover).existsSync()) {
      child = Image.file(File(cover), width: 40, height: 40, fit: BoxFit.cover);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: background,
        child: SizedBox(width: 40, height: 40, child: child),
      ),
    );
  }
}
