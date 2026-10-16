import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../navigation/library_navigation.dart';
import '../screens/metadata_editor_screen.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/breakpoints.dart';
import '../utils/duration_format.dart';
import '../utils/lyrics_format.dart';
import '../utils/trash_actions.dart';

const _kYellow = Color(0xFFFFDB4D);
const _kBar = Color(0xFF232323);
const _kIcon = Color(0xFFD4D0C8);
const _kIconDim = Color(0xFF7A766E);

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _showLyrics = false;
  bool _showQueue = false;
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
    setState(() {
      _showLyrics = false;
      _showQueue = false;
    });
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

  void _hideVolume() {
    _volumeHideTimer?.cancel();
    if (_volumePortal.isShowing) {
      _volumePortal.hide();
      setState(() {});
    }
  }

  void _closePanels() {
    _hideVolume();
    setState(() {
      _showLyrics = false;
      _showQueue = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final track = player.current;
    if (track == null) {
      _hideVolume();
      return const SizedBox.shrink();
    }

    final progress = player.duration == null ||
            player.duration!.inMilliseconds == 0
        ? 0.0
        : player.position.inMilliseconds / player.duration!.inMilliseconds;
    final lyricsText = formatLyrics(track.lyrics);
    final canShowLyrics = lyricsText.isNotEmpty;
    final phone = isPhone(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    void toggleLyrics() {
      _hideVolume();
      setState(() {
        _showQueue = false;
        _showLyrics = !_showLyrics;
      });
    }

    void toggleQueue() {
      _hideVolume();
      setState(() {
        _showLyrics = false;
        _showQueue = !_showQueue;
      });
    }

    final progressStrip = _ProgressStrip(
      progress: progress.clamp(0.0, 1.0),
      position: player.position,
      duration: player.duration,
      enabled: player.duration != null,
      onSeek: (v) {
        final total = player.duration!.inMilliseconds;
        player.seek(Duration(milliseconds: (total * v).round()));
      },
    );

    final panels = AnimatedCrossFade(
      firstChild: const SizedBox(width: double.infinity, height: 0),
      secondChild: _showLyrics
          ? _LyricsPanel(
              title: track.displayTitle,
              lyrics: lyricsText,
              onClose: () => setState(() => _showLyrics = false),
            )
          : _QueuePanel(
              queue: player.queue,
              currentKey: track.trackKey,
              onSelect: (i) => player.playQueueIndex(i),
              onReorder: player.reorderQueue,
              onClose: () => setState(() => _showQueue = false),
            ),
      crossFadeState: (_showLyrics || _showQueue)
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
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
                _TrackInfo(
                  track: track,
                  onMenu: () => _openTrackMenu(context, track),
                ),
                const SizedBox(height: 6),
                _CenterControls(player: player),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _IconBtn(
                      icon: Icons.lyrics_outlined,
                      active: _showLyrics,
                      enabled: canShowLyrics,
                      tooltip: canShowLyrics ? 'Текст' : 'Текста нет',
                      onPressed: canShowLyrics ? toggleLyrics : null,
                      size: 24,
                    ),
                    _IconBtn(
                      icon: Icons.queue_music_rounded,
                      active: _showQueue,
                      tooltip: 'Очередь',
                      onPressed: toggleQueue,
                      size: 24,
                    ),
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
                  child: _TrackInfo(
                    track: track,
                    onMenu: () => _openTrackMenu(context, track),
                  ),
                ),
                if (wide) ...[
                  Expanded(
                    flex: 4,
                    child: _CenterControls(player: player),
                  ),
                  Expanded(
                    flex: 3,
                    child: _RightControls(
                      canShowLyrics: canShowLyrics,
                      lyricsOpen: _showLyrics,
                      queueOpen: _showQueue,
                      onToggleLyrics: canShowLyrics ? toggleLyrics : null,
                      onToggleQueue: toggleQueue,
                      volumeControl: _volumeControl(player),
                    ),
                  ),
                ] else ...[
                  _CompactCenter(player: player),
                  const SizedBox(width: 4),
                  _IconBtn(
                    icon: Icons.lyrics_outlined,
                    active: _showLyrics,
                    enabled: canShowLyrics,
                    tooltip: canShowLyrics ? 'Текст' : 'Текста нет',
                    onPressed: canShowLyrics ? toggleLyrics : null,
                  ),
                  _IconBtn(
                    icon: Icons.queue_music_rounded,
                    active: _showQueue,
                    tooltip: 'Очередь',
                    onPressed: toggleQueue,
                  ),
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
            Padding(
              padding: EdgeInsets.fromLTRB(phone ? 8 : 10, 0, phone ? 8 : 10, 8),
              child: DecoratedBox(
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
          ],
        ),
      ),
    );
  }

  Future<void> _openTrackMenu(BuildContext context, Track track) async {
    _closePanels();
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.inkLift,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Метаданные'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Копировать название'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('В корзину'),
              onTap: () => Navigator.pop(ctx, 'trash'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || value == null) return;
    if (value == 'edit') {
      await openMetadataEditor(context, track);
    } else if (value == 'copy') {
      await Clipboard.setData(
        ClipboardData(text: '${track.displayArtist} - ${track.displayTitle}'),
      );
    } else if (value == 'trash') {
      await moveTrackToTrash(context, track);
    }
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
    const hitH = 14.0;

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
                // Time chips float above the bar — outside the clip.
                if (_hover) ...[
                  Positioned(
                    left: (thumbX - 22).clamp(6.0, math.max(6.0, width - 52)),
                    top: -26,
                    child: _TimeChip(posLabel),
                  ),
                  Positioned(
                    right: 8,
                    top: -26,
                    child: _TimeChip(durLabel),
                  ),
                ],
                // Clip to player top corners so the track doesn't spill out.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: hitH,
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
                          showThumb: _hover || p > 0,
                          thumbRadius: _hover ? 5.5 : 4.0,
                        ),
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
  _ProgressTrackPainter({
    required this.progress,
    required this.trackHeight,
    required this.showThumb,
    required this.thumbRadius,
  });

  final double progress;
  final double trackHeight;
  final bool showThumb;
  final double thumbRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = trackHeight / 2;
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
    if (showThumb) {
      canvas.drawCircle(
        Offset(size.width * progress, cy),
        thumbRadius,
        Paint()..color = _kYellow,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressTrackPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.showThumb != showThumb ||
      oldDelegate.thumbRadius != thumbRadius;
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
  const _TrackInfo({
    required this.track,
    required this.onMenu,
  });

  final Track track;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Cover(path: track.coverPath),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openAlbumForTrack(context, track),
                        child: Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.figtree(
                            color: AppTheme.paper,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    onTap: onMenu,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: _kIconDim,
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
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    Widget child = const ColoredBox(
      color: Color(0xFF2E2E2E),
      child: Icon(Icons.album, color: _kIconDim, size: 22),
    );
    if (path != null && File(path!).existsSync()) {
      child = Image.file(File(path!), fit: BoxFit.cover);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(width: 46, height: 46, child: child),
    );
  }
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
        _PlayButton(
          playing: player.playing,
          onPressed: player.togglePlayPause,
        ),
        const SizedBox(width: 4),
        _IconBtn(
          icon: Icons.skip_next_rounded,
          tooltip: 'Следующий',
          size: 28,
          onPressed: player.next,
        ),
        _IconBtn(
          icon: switch (player.repeat) {
            PlayRepeatMode.one => Icons.repeat_one_rounded,
            _ => Icons.repeat_rounded,
          },
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
    required this.canShowLyrics,
    required this.lyricsOpen,
    required this.queueOpen,
    required this.onToggleLyrics,
    required this.onToggleQueue,
    required this.volumeControl,
  });

  final bool canShowLyrics;
  final bool lyricsOpen;
  final bool queueOpen;
  final VoidCallback? onToggleLyrics;
  final VoidCallback onToggleQueue;
  final Widget volumeControl;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _IconBtn(
          icon: Icons.queue_music_rounded,
          active: queueOpen,
          tooltip: 'Очередь',
          onPressed: onToggleQueue,
        ),
        _IconBtn(
          icon: Icons.lyrics_outlined,
          active: lyricsOpen,
          enabled: canShowLyrics,
          tooltip: canShowLyrics ? 'Текст' : 'Текста нет',
          onPressed: onToggleLyrics,
        ),
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

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.enabled = true,
    this.size = 22,
  });

  final IconData icon;
  final String tooltip;
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
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(icon, size: size, color: color),
    );
  }
}

class _YandexVolumeCapsule extends StatelessWidget {
  const _YandexVolumeCapsule({
    required this.volume,
    required this.onChanged,
  });

  final double volume;
  final ValueChanged<double> onChanged;

  void _setFromLocalY(double localY, double height) {
    final t = 1.0 - (localY / height);
    onChanged(t.clamp(0.0, 1.0));
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
                  final step = signal.scrollDelta.dy > 0 ? -0.05 : 0.05;
                  onChanged((volume + step).clamp(0.0, 1.0));
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _setFromLocalY(d.localPosition.dy, constraints.maxHeight),
                  onVerticalDragUpdate: (d) =>
                      _setFromLocalY(d.localPosition.dy, constraints.maxHeight),
                  child: CustomPaint(
                    painter:
                        _VolumeCapsulePainter(volume: volume.clamp(0.0, 1.0)),
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
    const pad = 16.0;
    const thumbR = 7.0;
    final trackTop = pad;
    final trackBottom = size.height - pad;
    final trackH = (trackBottom - trackTop).clamp(0.0, size.height);

    final railPaint = Paint()
      ..color = const Color(0xFF555555)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, trackTop),
      Offset(cx, trackBottom),
      railPaint,
    );

    final fillTop = trackBottom - trackH * volume;
    if (volume > 0.001) {
      final fillPaint = Paint()
        ..color = _kYellow
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(cx, fillTop),
        Offset(cx, trackBottom),
        fillPaint,
      );
    }

    final thumbY = fillTop.clamp(trackTop, trackBottom);
    canvas.drawCircle(
      Offset(cx, thumbY),
      thumbR,
      Paint()..color = _kYellow,
    );
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

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({
    required this.title,
    required this.lyrics,
    required this.onClose,
  });

  final String title;
  final String lyrics;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.paper.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Текст · $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.syne(
                    color: _kYellow,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18, color: _kIconDim),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                lyrics,
                style: GoogleFonts.figtree(
                  color: AppTheme.paper,
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
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
                  style: GoogleFonts.figtree(
                    color: _kIconDim,
                    fontSize: 11,
                  ),
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
                              child: Text(
                                '${t.displayArtist} - ${t.displayTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
