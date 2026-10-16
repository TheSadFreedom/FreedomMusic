import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Full-bleed listening-room stage: mesh wash + soft waveform.
class HomeStage extends StatefulWidget {
  const HomeStage({
    super.key,
    required this.playing,
    required this.child,
  });

  final bool playing;
  final Widget child;

  @override
  State<HomeStage> createState() => _HomeStageState();
}

class _HomeStageState extends State<HomeStage> with TickerProviderStateMixin {
  late final AnimationController _wave;
  late final AnimationController _breathe;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _wave.dispose();
    _breathe.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_wave, _breathe, _enter]),
      builder: (context, _) {
        final enter = Curves.easeOutCubic.transform(_enter.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _MeshPainter(
                breathe: _breathe.value,
                playing: widget.playing,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WavePainter(
                    t: _wave.value,
                    playing: widget.playing,
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.1),
                  radius: 1.1,
                  colors: [
                    Color(0x000C1210),
                    Color(0x990C1210),
                    Color(0xE60C1210),
                  ],
                  stops: [0.35, 0.75, 1.0],
                ),
              ),
            ),
            Opacity(
              opacity: enter,
              child: Transform.translate(
                offset: Offset(0, (1 - enter) * 28),
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Spinning vinyl with a fixed play button locked to the disc center.
class VinylPlayControl extends StatefulWidget {
  const VinylPlayControl({
    super.key,
    required this.playing,
    required this.enabled,
    required this.onPressed,
    this.size = 280,
  });

  final bool playing;
  final bool enabled;
  final VoidCallback? onPressed;
  final double size;

  @override
  State<VinylPlayControl> createState() => _VinylPlayControlState();
}

class _VinylPlayControlState extends State<VinylPlayControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    // ~33⅓ RPM feel, readable in the UI.
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant VinylPlayControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playSize = widget.size * 0.34;
    final scale = _hover && widget.enabled ? 1.03 : 1.0;

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Disc spins; center play control stays fixed.
              RotationTransition(
                turns: _spin,
                child: CustomPaint(
                  size: Size.square(widget.size),
                  painter: const _VinylPainter(hole: false),
                ),
              ),
              GestureDetector(
                onTap: widget.enabled ? widget.onPressed : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: playSize,
                  height: playSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !widget.enabled
                        ? AppTheme.paperMuted.withValues(alpha: 0.35)
                        : widget.playing
                            ? AppTheme.lime
                            : AppTheme.mossBright,
                    boxShadow: widget.enabled
                        ? [
                            BoxShadow(
                              color: (widget.playing
                                      ? AppTheme.lime
                                      : AppTheme.mossBright)
                                  .withValues(alpha: 0.4),
                              blurRadius: widget.playing ? 36 : 22,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  // play_arrow is slightly left-heavy in the glyph box;
                  // nudge a hair right so it looks centered in the circle.
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(
                        widget.playing ? 0 : playSize * 0.02,
                        widget.playing ? 0 : -playSize * 0.01,
                      ),
                      child: Icon(
                        widget.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: playSize * 0.48,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter({this.hole = true});

  final bool hole;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFF1A2420)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF141A18));

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF2A3530);
    for (var i = 8; i < 42; i++) {
      canvas.drawCircle(c, r * (i / 48), groove);
    }

    // Asymmetric bright groove sector — makes rotation obvious.
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.14);
    for (var i = 10; i < 40; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * (i / 48)),
        -0.35,
        0.55,
        false,
        highlight,
      );
    }

    // Label ring — play button sits on top of the center.
    canvas.drawCircle(
      c,
      r * 0.36,
      Paint()..color = AppTheme.moss.withValues(alpha: 0.55),
    );
    canvas.drawCircle(c, r * 0.30, Paint()..color = const Color(0xFF0E1613));

    // Offset label mark so the disc doesn't look static while spinning.
    final mark = Offset(c.dx + r * 0.18, c.dy - r * 0.08);
    canvas.drawCircle(
      mark,
      r * 0.035,
      Paint()..color = AppTheme.lime.withValues(alpha: 0.85),
    );

    if (hole) {
      canvas.drawCircle(c, r * 0.05, Paint()..color = AppTheme.lime);
    }

    final sheen = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.05, 0.14, 0.28, 0.62, 0.78],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, sheen);
  }

  @override
  bool shouldRepaint(covariant _VinylPainter oldDelegate) =>
      oldDelegate.hole != hole;
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({required this.breathe, required this.playing});

  final double breathe;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppTheme.ink);

    final energy = playing ? 1.15 : 1.0;
    final o1 = Offset(size.width * 0.5, size.height * (0.42 + breathe * 0.02));
    final o2 = Offset(size.width * 0.35, size.height * 0.72);

    canvas.drawCircle(
      o1,
      size.shortestSide * 0.42 * energy,
      Paint()
        ..color = AppTheme.moss.withValues(alpha: 0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80),
    );
    canvas.drawCircle(
      o2,
      size.shortestSide * 0.3,
      Paint()
        ..color = AppTheme.lime.withValues(alpha: 0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70),
    );
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) =>
      oldDelegate.breathe != breathe || oldDelegate.playing != playing;
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.t, required this.playing});

  final double t;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height);
    final amp = playing ? 28.0 : 10.0;
    for (double x = 0; x <= size.width; x += 4) {
      final n = x / size.width;
      final y = size.height * 0.55 +
          math.sin((n * 4 + t) * math.pi * 2) * amp +
          math.sin((n * 9 - t * 1.4) * math.pi * 2) * (amp * 0.35);
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.mossBright.withValues(alpha: playing ? 0.35 : 0.16),
            AppTheme.ink.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.playing != playing;
}
