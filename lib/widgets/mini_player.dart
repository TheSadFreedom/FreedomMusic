import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/equalizer_state.dart';
import '../models/track.dart';
import '../navigation/library_navigation.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/breakpoints.dart';
import '../utils/duration_format.dart';
import '../utils/lyrics_format.dart';
import 'equalizer_panel.dart';
import 'kept_icons.dart';
import 'lyrics_view.dart';
import 'track_overflow_menu.dart';
import 'track_title_line.dart';
import '../utils/trash_actions.dart';

const _kYellow = Color(0xFFFFDB4D);
const _kBar = Color(0xFF232323);
const _kIcon = Color(0xFFD4D0C8);
const _kIconDim = Color(0xFF7A766E);

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, this.barKey});

  /// Ключ бара для высоты дока (без панели эквалайзера).
  final GlobalKey? barKey;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _showLyrics = false;
  bool _showQueue = false;
  bool _showEqualizer = false;
  final _volumePortal = OverlayPortalController();
  final _volumeLink = LayerLink();
  Timer? _volumeHideTimer;

  @override
  void dispose() {
    _volumeHideTimer?.cancel();
    if (_volumePortal.isShowing) _volumePortal.hide();
    super.dispose();
  }

  void _showVolumeHover() {
    _volumeHideTimer?.cancel();
    if (_showQueue || _showEqualizer) {
      setState(() {
        _showQueue = false;
        _showEqualizer = false;
      });
    }
    if (!_volumePortal.isShowing) {
      _volumePortal.show();
      setState(() {});
    }
  }

  void _scheduleHideVolume() {
    _volumeHideTimer?.cancel();
    _volumeHideTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _hideVolume();
    });
  }

  void _cancelHideVolume() {
    _volumeHideTimer?.cancel();
  }

  void _publishLyrics({
    required bool visible,
    String title = '',
    String? note,
    String? raw,
    bool fetching = false,
    bool notFound = false,
  }) {
    final presentation = context.read<LyricsPresentation>();
    presentation.closeHandler = () {
      if (!mounted) return;
      setState(() => _showLyrics = false);
    };
    if (presentation.visible == visible &&
        presentation.title == title &&
        presentation.note == note &&
        presentation.raw == raw &&
        presentation.fetching == fetching &&
        presentation.notFound == notFound) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      presentation.update(
        visible: visible,
        title: title,
        note: note,
        raw: raw,
        fetching: fetching,
        notFound: notFound,
      );
    });
  }

  void _hideVolume() {
    _volumeHideTimer?.cancel();
    if (_volumePortal.isShowing) {
      _volumePortal.hide();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlayerService, Track?>((p) => p.current);
    context.select<PlayerService, bool>((p) => p.playing);
    context.select<PlayerService, bool>((p) => p.shuffle);
    context.select<PlayerService, PlayRepeatMode>((p) => p.repeat);
    context.select<PlayerService, double>((p) => p.volume);
    context.select<PlayerService, int>((p) => p.queueEpoch);
    context.select<PlayerService, EqualizerState>((p) => p.equalizer);
    final player = context.read<PlayerService>();
    final library = context.watch<LibraryService>();
    if (track == null) {
      _hideVolume();
      if (_showLyrics) _showLyrics = false;
      if (_showEqualizer) _showEqualizer = false;
      _publishLyrics(visible: false);
      return const SizedBox.shrink();
    }

    final lyricsSource = library.resolveTrack(track);
    final lyricsText = formatLyrics(lyricsSource.lyrics);
    final lyricsFetching = library.isFetchingLyrics(track.trackKey);
    final lyricsFailed = library.lyricsLookupFailed(track.trackKey);
    final phone = isPhone(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    _publishLyrics(
      visible: _showLyrics,
      title: track.displayTitle,
      note: track.displayNote,
      raw: lyricsSource.lyrics,
      fetching: lyricsFetching,
      notFound: lyricsFailed && lyricsText.isEmpty,
    );

    void toggleLyrics() {
      _hideVolume();
      final opening = !_showLyrics;
      setState(() {
        _showQueue = false;
        _showEqualizer = false;
        _showLyrics = opening;
      });
      // The stage lives in the player overlay, outside this build. Publish
      // now, while the click is still handling, so the text is not left closed.
      final willFetch = opening && lyricsText.isEmpty;
      context.read<LyricsPresentation>().update(
        visible: opening,
        title: track.displayTitle,
        note: track.displayNote,
        raw: lyricsSource.lyrics,
        fetching: willFetch || lyricsFetching,
        notFound: !willFetch && lyricsFailed && lyricsText.isEmpty,
      );
      if (opening && lyricsText.isEmpty) {
        library.ensureRemoteLyrics(lyricsSource).then((updated) {
          if (updated != null) player.syncTrack(updated);
        });
      }
    }

    void toggleQueue() {
      _hideVolume();
      setState(() {
        _showLyrics = false;
        _showEqualizer = false;
        _showQueue = !_showQueue;
      });
    }

    void toggleEqualizer() {
      _hideVolume();
      setState(() {
        _showLyrics = false;
        _showQueue = false;
        _showEqualizer = !_showEqualizer;
      });
    }

    const progressStrip = _LiveProgressStrip();

    final panels = AnimatedCrossFade(
      firstChild: const SizedBox(width: double.infinity, height: 0),
      secondChild: _showQueue
          ? _QueuePanel(
              queue: player.queue,
              currentKey: track.trackKey,
              onSelect: (i) => player.playQueueIndex(i),
              onReorder: player.reorderQueue,
              onClose: () => setState(() => _showQueue = false),
            )
          : const SizedBox(width: double.infinity, height: 0),
      crossFadeState:
          _showQueue ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 220),
    );

    final Widget controlsBody;
    if (phone) {
      controlsBody = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          progressStrip,
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              10,
              8,
              _showLyrics || _showQueue ? 8 : 10,
            ),
            child: Column(
              children: [
                _TrackInfo(track: track),
                const SizedBox(height: 6),
                _CenterControls(player: player),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _IconBtn(
                      icon: Icons.lyrics_outlined,
                      mark: const LyricsGlyph(),
                      active: _showLyrics,
                      tooltip: lyricsText.isNotEmpty
                          ? 'Текст'
                          : lyricsFetching
                          ? 'Ищем текст…'
                          : 'Текст',
                      onPressed: toggleLyrics,
                      size: 24,
                    ),
                    _IconBtn(
                      icon: Icons.equalizer_rounded,
                      mark: const EqualizerGlyph(),
                      active: _showEqualizer,
                      tooltip: 'Эквалайзер',
                      onPressed: toggleEqualizer,
                      size: 24,
                    ),
                    _IconBtn(
                      icon: Icons.queue_music_rounded,
                      active: _showQueue,
                      tooltip: 'Очередь',
                      onPressed: toggleQueue,
                      size: 24,
                    ),
                    const _TrashBtn(size: 24),
                    _volumeControl(player, iconSize: 24),
                  ],
                ),
              ],
            ),
          ),
          panels,
        ],
      );
    } else {
      controlsBody = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          progressStrip,
          Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              8,
              10,
              _showLyrics || _showQueue ? 8 : 12,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: wide ? 3 : 2,
                  child: _TrackInfo(track: track),
                ),
                if (wide) ...[
                  Expanded(flex: 4, child: _CenterControls(player: player)),
                  Expanded(
                    flex: 3,
                    child: _RightControls(
                      lyricsOpen: _showLyrics,
                      queueOpen: _showQueue,
                      equalizerOpen: _showEqualizer,
                      onToggleLyrics: toggleLyrics,
                      onToggleQueue: toggleQueue,
                      onToggleEqualizer: toggleEqualizer,
                      volumeControl: _volumeControl(player),
                      lyricsTooltip: lyricsText.isNotEmpty
                          ? 'Текст'
                          : lyricsFetching
                          ? 'Ищем текст…'
                          : 'Текст',
                    ),
                  ),
                ] else ...[
                  _CompactCenter(player: player),
                  const SizedBox(width: 4),
                  _IconBtn(
                    icon: Icons.lyrics_outlined,
                    mark: const LyricsGlyph(),
                    active: _showLyrics,
                    tooltip: lyricsText.isNotEmpty
                        ? 'Текст'
                        : lyricsFetching
                        ? 'Ищем текст…'
                        : 'Текст',
                    onPressed: toggleLyrics,
                  ),
                  _IconBtn(
                    icon: Icons.equalizer_rounded,
                    mark: const EqualizerGlyph(),
                    active: _showEqualizer,
                    tooltip: 'Эквалайзер',
                    onPressed: toggleEqualizer,
                  ),
                  _IconBtn(
                    icon: Icons.queue_music_rounded,
                    active: _showQueue,
                    tooltip: 'Очередь',
                    onPressed: toggleQueue,
                  ),
                  const _TrashBtn(),
                  _volumeControl(player),
                ],
              ],
            ),
          ),
          panels,
        ],
      );
    }

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showEqualizer)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  phone ? 12 : 16,
                  0,
                  phone ? 12 : 16,
                  10,
                ),
                child: const Align(
                  alignment: Alignment.centerRight,
                  child: EqualizerPanel(),
                ),
              ),
            // Высоту дока меряем только по бару — EQ поверх контента.
            SizeChangedLayoutNotifier(
              child: Padding(
                key: widget.barKey,
                padding: EdgeInsets.fromLTRB(
                  phone ? 8 : 10,
                  0,
                  phone ? 8 : 10,
                  8,
                ),
                // Clip.none so the progress thumb can sit on the top edge
                // without being cut by the rounded bar.
                child: Container(
                  clipBehavior: Clip.none,
                  decoration: BoxDecoration(
                    color: _kBar,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: controlsBody,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _volumeIcon(double v) {
    if (v <= 0.001) return Icons.volume_off_rounded;
    if (v < 0.35) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  /// Hover shows the capsule; click mutes. Wheel adjusts level.
  /// Overlay must not cover the button — otherwise mute clicks are stolen.
  Widget _volumeControl(PlayerService player, {double iconSize = 22}) {
    final volumeOpen = _volumePortal.isShowing;
    return OverlayPortal(
      controller: _volumePortal,
      overlayChildBuilder: (context) {
        // Stack gives loose constraints (no stretch) and keeps follower
        // anchored to the volume button.
        return Stack(
          children: [
            CompositedTransformFollower(
              link: _volumeLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -10),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => _cancelHideVolume(),
                onExit: (_) => _scheduleHideVolume(),
                child: _YandexVolumeCapsule(
                  volume: player.volume,
                  onChanged: player.setVolume,
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _volumeLink,
        child: MouseRegion(
          onEnter: (_) => _showVolumeHover(),
          onExit: (_) => _scheduleHideVolume(),
          child: Listener(
            onPointerSignal: (signal) {
              if (signal is! PointerScrollEvent) return;
              final step = signal.scrollDelta.dy > 0 ? -0.05 : 0.05;
              player.setVolume((player.volume + step).clamp(0.0, 1.0));
            },
            child: _IconBtn(
              icon: _volumeIcon(player.volume),
              active: volumeOpen,
              tooltip: '',
              onPressed: player.toggleMute,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveProgressStrip extends StatelessWidget {
  const _LiveProgressStrip();

  @override
  Widget build(BuildContext context) {
    final position = context.select<PlayerService, Duration>((p) => p.position);
    final duration = context.select<PlayerService, Duration?>((p) => p.duration);
    final player = context.read<PlayerService>();
    final total = duration?.inMilliseconds ?? 0;
    final progress = total == 0 ? 0.0 : position.inMilliseconds / total;
    return _ProgressStrip(
      progress: progress.clamp(0.0, 1.0),
      position: position,
      duration: duration,
      enabled: duration != null && total > 0,
      onSeek: (v) {
        final ms = player.duration?.inMilliseconds ?? 0;
        if (ms <= 0) return;
        player.seek(Duration(milliseconds: (ms * v).round()));
      },
    );
  }
}

class _ProgressStrip extends StatefulWidget {
  const _ProgressStrip({
    required this.progress,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onSeek,
  });

  final double progress;
  final Duration position;
  final Duration? duration;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  State<_ProgressStrip> createState() => _ProgressStripState();
}

class _ProgressStripState extends State<_ProgressStrip> {
  bool _hover = false;

  void _seekAt(Offset local, double width) {
    if (!widget.enabled || width <= 0) return;
    widget.onSeek((local.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration?.inMilliseconds ?? 0;
    final posLabel = formatTrackDuration(widget.position.inMilliseconds);
    final durLabel = formatTrackDuration(totalMs > 0 ? totalMs : null);
    final p = widget.progress.clamp(0.0, 1.0);
    final trackH = _hover ? 3.0 : 2.0;
    final thumbR = _hover ? 5.5 : 4.0;
    // Hit area below the top border; track itself is painted on y=0 (edge).
    const hitH = 12.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: SizedBox(
        height: hitH,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final thumbX = width * p;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (_hover) ...[
                  Positioned(
                    left: (thumbX - 22).clamp(6.0, math.max(6.0, width - 52)),
                    top: -28,
                    child: _TimeChip(posLabel),
                  ),
                  Positioned(right: 8, top: -28, child: _TimeChip(durLabel)),
                ],
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: widget.enabled
                          ? (d) => _seekAt(d.localPosition, width)
                          : null,
                      onHorizontalDragUpdate: widget.enabled
                          ? (d) => _seekAt(d.localPosition, width)
                          : null,
                      child: CustomPaint(
                        size: Size(width, hitH),
                        painter: _ProgressTrackPainter(
                          progress: p,
                          trackHeight: trackH,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_hover || p > 0)
                  Positioned(
                    left: (width * p).clamp(thumbR, width - thumbR) - thumbR,
                    top: trackH / 2 - thumbR,
                    child: IgnorePointer(
                      child: Container(
                        width: thumbR * 2,
                        height: thumbR * 2,
                        decoration: const BoxDecoration(
                          color: _kYellow,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressTrackPainter extends CustomPainter {
  _ProgressTrackPainter({required this.progress, required this.trackHeight});

  final double progress;
  final double trackHeight;

  @override
  void paint(Canvas canvas, Size size) {
    // Line sits on the player's top edge. The parent ClipRRect (radius 16)
    // follows the bar's rounded corners so the ends don't float past them.
    final track = RRect.fromLTRBR(
      0,
      0,
      size.width,
      trackHeight,
      Radius.circular(trackHeight / 2),
    );
    canvas.drawRRect(
      track,
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          0,
          size.width * progress,
          trackHeight,
          Radius.circular(trackHeight / 2),
        ),
        Paint()..color = _kYellow,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressTrackPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackHeight != trackHeight;
}

class _TimeChip extends StatelessWidget {
  const _TimeChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          text,
          style: GoogleFonts.figtree(
            color: AppTheme.paper,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return TrackContextMenu(
      actions: standardTrackActions(context, track, copyTitle: true),
      child: Row(
        children: [
          _Cover(path: track.coverPath),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRect(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: TrackTitleLine(
                        title: track.displayTitle,
                        note: track.displayNote,
                        onTap: () => openAlbumForTrack(context, track),
                        style: GoogleFonts.figtree(
                          color: AppTheme.paper,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openArtistFromTrack(context, track),
                    child: Text(
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.figtree(
                        color: _kIconDim,
                        fontSize: 12,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final filePath = path;
    final hasFile = filePath != null && File(filePath).existsSync();
    Widget child = const ColoredBox(
      color: Color(0xFF2E2E2E),
      child: Icon(Icons.album, color: _kIconDim, size: 22),
    );
    if (hasFile) {
      child = Image.file(File(filePath), fit: BoxFit.cover);
    }
    final art = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(width: 46, height: 46, child: child),
    );
    if (!hasFile) return art;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openCover(context, filePath),
        child: art,
      ),
    );
  }
}

Future<void> _openCover(BuildContext context, String path) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final side = math.min(size.width, size.height) * 0.78;
      return GestureDetector(
        onTap: () => Navigator.pop(ctx),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: SizedBox(
              width: side,
              height: side,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _IconBtn(
          icon: Icons.shuffle_rounded,
          active: player.shuffle,
          tooltip: 'Случайный порядок',
          onPressed: player.toggleShuffle,
        ),
        _IconBtn(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Предыдущий',
          size: 28,
          onPressed: player.previous,
        ),
        const SizedBox(width: 4),
        _PlayButton(playing: player.playing, onPressed: player.togglePlayPause),
        const SizedBox(width: 4),
        _IconBtn(
          icon: Icons.skip_next_rounded,
          tooltip: 'Следующий',
          size: 28,
          onPressed: player.next,
        ),
        _IconBtn(
          icon: Icons.repeat,
          mark: _RepeatMark(one: player.repeat == PlayRepeatMode.one),
          active: player.repeat != PlayRepeatMode.off,
          tooltip: switch (player.repeat) {
            PlayRepeatMode.off => 'Повтор выкл.',
            PlayRepeatMode.all => 'Повтор очереди',
            PlayRepeatMode.one => 'Повтор трека',
          },
          onPressed: player.cycleRepeat,
        ),
      ],
    );
  }
}

class _CompactCenter extends StatelessWidget {
  const _CompactCenter({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Предыдущий',
          onPressed: player.previous,
        ),
        _PlayButton(
          playing: player.playing,
          onPressed: player.togglePlayPause,
          size: 42,
        ),
        _IconBtn(
          icon: Icons.skip_next_rounded,
          tooltip: 'Следующий',
          onPressed: player.next,
        ),
      ],
    );
  }
}

class _RightControls extends StatelessWidget {
  const _RightControls({
    required this.lyricsOpen,
    required this.queueOpen,
    required this.equalizerOpen,
    required this.onToggleLyrics,
    required this.onToggleQueue,
    required this.onToggleEqualizer,
    required this.volumeControl,
    required this.lyricsTooltip,
  });

  final bool lyricsOpen;
  final bool queueOpen;
  final bool equalizerOpen;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleQueue;
  final VoidCallback onToggleEqualizer;
  final Widget volumeControl;
  final String lyricsTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _IconBtn(
          icon: Icons.equalizer_rounded,
          mark: const EqualizerGlyph(),
          active: equalizerOpen,
          tooltip: 'Эквалайзер',
          onPressed: onToggleEqualizer,
        ),
        _IconBtn(
          icon: Icons.queue_music_rounded,
          active: queueOpen,
          tooltip: 'Очередь',
          onPressed: onToggleQueue,
        ),
        _IconBtn(
          icon: Icons.lyrics_outlined,
          mark: const LyricsGlyph(),
          active: lyricsOpen,
          tooltip: lyricsTooltip,
          onPressed: onToggleLyrics,
        ),
        _TrashBtn(),
        volumeControl,
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.onPressed,
    this.size = 48,
  });

  final bool playing;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: _kYellow,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          mouseCursor: SystemMouseCursors.click,
          onTap: onPressed,
          child: Transform.translate(
            offset: Offset(playing ? 0 : size * 0.02, 0),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.black,
              size: size * 0.55,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrashBtn extends StatelessWidget {
  const _TrashBtn({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    final track = context.watch<PlayerService>().current;
    return _IconBtn(
      icon: Icons.delete_outline_rounded,
      tooltip: '',
      size: size,
      onPressed: track == null ? null : () => moveTrackToTrash(context, track),
      enabled: track != null,
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.mark,
    this.onPressed,
    this.active = false,
    this.enabled = true,
    this.size = 22,
  });

  final IconData icon;
  final String tooltip;
  final Widget? mark;
  final VoidCallback? onPressed;
  final bool active;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? _kIconDim.withValues(alpha: 0.35)
        : active
        ? _kYellow
        : _kIcon;
    return IconButton(
      tooltip: tooltip.isEmpty ? null : tooltip,
      onPressed: enabled ? onPressed : null,
      mouseCursor: enabled && onPressed != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: mark == null
          ? Icon(icon, size: size, color: color)
          : IconTheme(
              data: IconThemeData(color: color, size: size),
              child: mark!,
            ),
    );
  }
}

/// Drawn repeat glyph. The Material `repeat` codepoint is stripped from the
/// Windows icon font, so the button otherwise shows an empty circle.
class _RepeatMark extends StatelessWidget {
  const _RepeatMark({required this.one});

  final bool one;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 22;
    final color = theme.color ?? _kIcon;
    return CustomPaint(
      size: Size.square(size),
      painter: _RepeatMarkPainter(color: color, one: one),
    );
  }
}

class _RepeatMarkPainter extends CustomPainter {
  const _RepeatMarkPainter({required this.color, required this.one});

  final Color color;
  final bool one;

  static final Path _repeat = Path()
    ..moveTo(7, 7)
    ..lineTo(17, 7)
    ..lineTo(17, 10)
    ..lineTo(21, 6)
    ..lineTo(17, 2)
    ..lineTo(17, 5)
    ..lineTo(5, 5)
    ..lineTo(5, 11)
    ..lineTo(7, 11)
    ..close()
    ..moveTo(17, 17)
    ..lineTo(7, 17)
    ..lineTo(7, 14)
    ..lineTo(3, 18)
    ..lineTo(7, 22)
    ..lineTo(7, 19)
    ..lineTo(19, 19)
    ..lineTo(19, 13)
    ..lineTo(17, 13)
    ..close();

  static final Path _repeatOne = Path()
    ..addPath(_repeat, Offset.zero)
    ..moveTo(13, 15)
    ..lineTo(13, 9)
    ..lineTo(12, 9)
    ..lineTo(10, 10)
    ..lineTo(10, 11)
    ..lineTo(11.5, 11)
    ..lineTo(11.5, 15)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.save();
    canvas.translate(size.width * 0.04, size.height * 0.04);
    canvas.scale(size.width / 24 * 0.92, size.height / 24 * 0.92);
    canvas.drawPath(one ? _repeatOne : _repeat, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RepeatMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.one != one;
}

class _YandexVolumeCapsule extends StatelessWidget {
  const _YandexVolumeCapsule({required this.volume, required this.onChanged});

  final double volume;
  final ValueChanged<double> onChanged;

  static const _step = 0.05;

  void _setFromLocalY(double localY, double height) {
    const pad = 22.0;
    final usable = (height - pad * 2).clamp(1.0, height);
    final t = 1.0 - ((localY - pad) / usable);
    // Snap to 10% steps so the bar feels chunky.
    final snapped = (t.clamp(0.0, 1.0) / _step).round() * _step;
    onChanged(snapped.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    const width = 48.0;
    const height = 152.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          height: height,
          clipBehavior: Clip.none,
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(width / 2),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Listener(
                onPointerSignal: (signal) {
                  if (signal is! PointerScrollEvent) return;
                  final step = signal.scrollDelta.dy > 0 ? -_step : _step;
                  onChanged((volume + step).clamp(0.0, 1.0));
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _setFromLocalY(d.localPosition.dy, constraints.maxHeight),
                  onVerticalDragUpdate: (d) =>
                      _setFromLocalY(d.localPosition.dy, constraints.maxHeight),
                  child: CustomPaint(
                    painter: _VolumeCapsulePainter(
                      volume: volume.clamp(0.0, 1.0),
                    ),
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _VolumeCapsulePainter extends CustomPainter {
  _VolumeCapsulePainter({required this.volume});

  final double volume;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const pad = 22.0;
    const thumbR = 7.0;
    final trackTop = pad;
    final trackBottom = size.height - pad;
    final trackH = (trackBottom - trackTop).clamp(0.0, size.height);

    final railPaint = Paint()
      ..color = const Color(0xFF555555)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, trackTop), Offset(cx, trackBottom), railPaint);

    final fillTop = trackBottom - trackH * volume;
    if (volume > 0.001) {
      final fillPaint = Paint()
        ..color = _kYellow
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(cx, fillTop), Offset(cx, trackBottom), fillPaint);
    }

    final thumbY = fillTop.clamp(trackTop, trackBottom);
    canvas.drawCircle(Offset(cx, thumbY), thumbR, Paint()..color = _kYellow);
    canvas.drawCircle(
      Offset(cx, thumbY),
      thumbR,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _VolumeCapsulePainter oldDelegate) =>
      oldDelegate.volume != volume;
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.queue,
    required this.currentKey,
    required this.onSelect,
    required this.onReorder,
    required this.onClose,
  });

  final List<Track> queue;
  final String currentKey;
  final ValueChanged<int> onSelect;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final queueH = MediaQuery.sizeOf(context).height * 0.5;
    return Container(
      width: double.infinity,
      height: queueH,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.paper.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Очередь · ${queue.length}',
                    style: GoogleFonts.syne(
                      color: _kYellow,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  'перетащите',
                  style: GoogleFonts.figtree(color: _kIconDim, fontSize: 11),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18, color: _kIconDim),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: queue.length,
              onReorderItem: onReorder,
              itemBuilder: (context, index) {
                final t = queue[index];
                final current = t.trackKey == currentKey;
                return ReorderableDragStartListener(
                  key: ValueKey(t.trackKey),
                  index: index,
                  child: TrackContextMenu(
                    actions: standardTrackActions(context, t, copyTitle: true),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () => onSelect(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                child: Text(
                                  '${index + 1}',
                                  style: GoogleFonts.figtree(
                                    color: current ? _kYellow : _kIconDim,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: TrackTitleLine(
                                  title: t.displayArtist.isEmpty
                                      ? t.displayTitle
                                      : '${t.displayArtist} - ${t.displayTitle}',
                                  note: t.displayNote,
                                  style: GoogleFonts.figtree(
                                    color: current ? _kYellow : AppTheme.paper,
                                    fontWeight: current
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  size: 18,
                                  color: _kIconDim.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
