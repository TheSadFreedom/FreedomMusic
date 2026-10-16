import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/breakpoints.dart';
import '../widgets/home_hero.dart';
import '../widgets/track_meta_links.dart';
import '../widgets/track_tile.dart';

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
    final player = context.watch<PlayerService>();
    final searching = _query.trim().isNotEmpty;
    final results = searching ? library.search(_query) : const <Track>[];
    final playing = player.playing && player.current != null;

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
                            child: _SearchPanel(
                              results: results,
                              onPlay: (i) =>
                                  player.playTracks(results, startIndex: i),
                            ),
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('hero'),
                        child: _CenteredHero(
                          trackCount: library.tracks.length,
                          empty: library.isEmpty,
                          playing: playing,
                          current: player.current,
                          onPlay: library.isEmpty
                              ? null
                              : () {
                                  if (player.current != null) {
                                    player.togglePlayPause();
                                  } else {
                                    player.playRandomAll();
                                  }
                                },
                        ),
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
            hintText: 'Название, исполнитель, альбом, текст…',
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
  const _SearchPanel({
    required this.results,
    required this.onPlay,
  });

  final List<Track> results;
  final void Function(int index) onPlay;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${results.length} совпадений',
          textAlign: TextAlign.center,
          style: GoogleFonts.figtree(
            color: AppTheme.lime,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.28),
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final track = results[index];
                    return TrackTile(
                      track: track,
                      onTap: () => onPlay(index),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
