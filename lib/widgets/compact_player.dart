import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../models/track.dart';
import '../services/desktop_shell.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';

const _kYellow = Color(0xFFFFDB4D);
const _kIcon = Color(0xFFD4D0C8);
const _kIconDim = Color(0xFF8A857C);

/// Always-on-top floating bar: track + transport + volume + unpin.
class CompactPlayer extends StatefulWidget {
  const CompactPlayer({super.key});

  @override
  State<CompactPlayer> createState() => _CompactPlayerState();
}

class _CompactPlayerState extends State<CompactPlayer> {
  /// When set, the bar shows an inline trash confirmation (dialogs clip here).
  Track? _trashConfirm;

  Future<void> _commitTrash(Track track) async {
    final library = context.read<LibraryService>();
    final player = context.read<PlayerService>();
    await library.moveToTrash(track.trackKey);
    await player.removeTrackFromQueue(track.trackKey);
    if (mounted) setState(() => _trashConfirm = null);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final shell = context.watch<DesktopShell>();
    final track = player.current;

    // Drop confirm if the track changed or disappeared.
    if (_trashConfirm != null &&
        (track == null || track.trackKey != _trashConfirm!.trackKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _trashConfirm = null);
      });
    }

    final progress = player.duration == null ||
            player.duration!.inMilliseconds == 0
        ? 0.0
        : player.position.inMilliseconds / player.duration!.inMilliseconds;

    final confirming = _trashConfirm != null &&
        track != null &&
        track.trackKey == _trashConfirm!.trackKey;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF161E1A),
              Color(0xFF0C1210),
              Color(0xFF121A16),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                  child: confirming
                      ? _CompactTrashConfirm(
                          track: track!,
                          onCancel: () =>
                              setState(() => _trashConfirm = null),
                          onConfirm: () => _commitTrash(track),
                          onExpand: shell.exitCompactMode,
                        )
                      : _CompactPlaybackRow(
                          track: track,
                          player: player,
                          shell: shell,
                          onTrash: track == null
                              ? null
                              : () =>
                                  setState(() => _trashConfirm = track),
                        ),
                ),
              ),
            ),
            _CompactProgress(
              progress: progress.clamp(0.0, 1.0),
              enabled: player.duration != null && track != null && !confirming,
              onSeek: (v) {
                final total = player.duration!.inMilliseconds;
                player.seek(Duration(milliseconds: (total * v).round()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactPlaybackRow extends StatelessWidget {
  const _CompactPlaybackRow({
    required this.track,
    required this.player,
    required this.shell,
    required this.onTrash,
  });

  final Track? track;
  final PlayerService player;
  final DesktopShell shell;
  final VoidCallback? onTrash;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Cover(path: track?.coverPath),
        const SizedBox(width: 12),
        Expanded(
          child: track == null
              ? Text(
                  'Нет трека',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.figtree(
                    color: _kIconDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      track!.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.syne(
                        color: AppTheme.paper,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.1,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track!.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.figtree(
                        color: AppTheme.mossBright.withValues(alpha: 0.85),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(width: 8),
        _TransportCluster(
          playing: player.playing,
          onPrev: player.previous,
          onPlay: player.togglePlayPause,
          onNext: player.next,
        ),
        const SizedBox(width: 4),
        if (onTrash != null)
          _ChipBtn(
            icon: Icons.delete_outline_rounded,
            muted: true,
            onPressed: onTrash!,
          ),
        _VolumeBtn(player: player),
        _ChipBtn(
          icon: Icons.open_in_full_rounded,
          onPressed: shell.exitCompactMode,
        ),
      ],
    );
  }
}

/// Fits the 540×100 compact window — no Dialog (it clips and stacks over the bar).
class _CompactTrashConfirm extends StatelessWidget {
  const _CompactTrashConfirm({
    required this.track,
    required this.onCancel,
    required this.onConfirm,
    required this.onExpand,
  });

  final Track track;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Cover(path: track.coverPath),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'В корзину?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.syne(
                  color: AppTheme.paper,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  height: 1.1,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                track.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.figtree(
                  color: AppTheme.paperMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _ConfirmPill(
          label: 'Отмена',
          background: Colors.white.withValues(alpha: 0.08),
          foreground: AppTheme.paper,
          onPressed: onCancel,
        ),
        const SizedBox(width: 6),
        _ConfirmPill(
          label: 'В корзину',
          background: _kYellow,
          foreground: Colors.black,
          onPressed: onConfirm,
        ),
        const SizedBox(width: 4),
        _ChipBtn(
          icon: Icons.open_in_full_rounded,
          onPressed: onExpand,
        ),
      ],
    );
  }
}

class _ConfirmPill extends StatelessWidget {
  const _ConfirmPill({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: GoogleFonts.figtree(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportCluster extends StatelessWidget {
  const _TransportCluster({
    required this.playing,
    required this.onPrev,
    required this.onPlay,
    required this.onNext,
  });

  final bool playing;
  final VoidCallback onPrev;
  final VoidCallback onPlay;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChipBtn(
              icon: Icons.skip_previous_rounded,
              onPressed: onPrev,
            ),
            _PlayBtn(playing: playing, onPressed: onPlay),
            _ChipBtn(
              icon: Icons.skip_next_rounded,
              onPressed: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactProgress extends StatefulWidget {
  const _CompactProgress({
    required this.progress,
    required this.enabled,
    required this.onSeek,
  });

  final double progress;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  State<_CompactProgress> createState() => _CompactProgressState();
}

class _CompactProgressState extends State<_CompactProgress> {
  bool _hover = false;

  void _seekAt(Offset local, double width) {
    if (!widget.enabled || width <= 0) return;
    widget.onSeek((local.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress.clamp(0.0, 1.0);
    final trackH = _hover ? 3.0 : 2.0;
    final thumbR = _hover ? 5.5 : 4.0;
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
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16),
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
                        painter: _BarPainter(
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
                    // Circle sits on the bottom edge and stays inside the
                    // window. Centering it on the line would cut it in half.
                    top: hitH - thumbR * 2,
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

class _BarPainter extends CustomPainter {
  _BarPainter({required this.progress, required this.trackHeight});

  final double progress;
  final double trackHeight;

  @override
  void paint(Canvas canvas, Size size) {
    // Line sits on the window's bottom edge. ClipRRect (radius 16) follows
    // the same corner as the main player's top edge.
    final top = size.height - trackHeight;
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        top,
        size.width,
        size.height,
        Radius.circular(trackHeight / 2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          top,
          size.width * progress,
          size.height,
          Radius.circular(trackHeight / 2),
        ),
        Paint()..color = _kYellow,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackHeight != trackHeight;
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    Widget child = ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(
        Icons.graphic_eq_rounded,
        color: AppTheme.mossBright.withValues(alpha: 0.7),
        size: 20,
      ),
    );
    if (path != null && File(path!).existsSync()) {
      child = Image.file(
        File(path!),
        fit: BoxFit.cover,
        cacheWidth: 112,
        cacheHeight: 112,
        filterQuality: FilterQuality.medium,
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  const _PlayBtn({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // No Tooltip — compact window clips overlays outside its bounds.
    return Material(
      color: _kYellow,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        mouseCursor: SystemMouseCursors.click,
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Transform.translate(
            offset: Offset(playing ? 0 : 1.2, 0),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 22,
              color: AppTheme.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeBtn extends StatelessWidget {
  const _VolumeBtn({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final v = player.volume;
    final icon = v <= 0.001
        ? Icons.volume_off_rounded
        : v < 0.35
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return Listener(
      onPointerSignal: (signal) {
        if (signal is! PointerScrollEvent) return;
        final step = signal.scrollDelta.dy > 0 ? -0.05 : 0.05;
        player.setVolume((player.volume + step).clamp(0.0, 1.0));
      },
      child: _ChipBtn(
        icon: icon,
        onPressed: player.toggleMute,
      ),
    );
  }
}

class _ChipBtn extends StatelessWidget {
  const _ChipBtn({
    required this.icon,
    required this.onPressed,
    this.muted = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? _kIconDim : _kIcon;
    // Tooltips are clipped by the tiny always-on-top window — skip them.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        mouseCursor: SystemMouseCursors.click,
        onTap: onPressed,
        hoverColor: Colors.white.withValues(alpha: 0.08),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
