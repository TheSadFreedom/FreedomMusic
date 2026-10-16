import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// First frame of the window: a spinning mark while the library loads.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, this.error});

  final String? error;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: AnimatedBuilder(
                animation: _spin,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _MarkPainter(turn: _spin.value),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Freedom',
                    style: GoogleFonts.syne(
                      color: AppTheme.paper,
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      letterSpacing: -0.6,
                      height: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  TextSpan(
                    text: ' Music',
                    style: GoogleFonts.syne(
                      color: AppTheme.mossBright,
                      fontWeight: FontWeight.w700,
                      fontSize: 28,
                      letterSpacing: -0.4,
                      height: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 360,
                child: Text(
                  widget.error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.figtree(
                    color: AppTheme.paperMuted,
                    fontSize: 13,
                    height: 1.4,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.turn});

  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final track = Paint()
      ..color = AppTheme.paper.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(c, radius, track);

    final arc = Paint()
      ..color = AppTheme.lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      turn * math.pi * 2,
      math.pi * 0.85,
      false,
      arc,
    );

    final disc = Paint()..color = AppTheme.inkLift;
    canvas.drawCircle(c, radius * 0.62, disc);
    final hole = Paint()..color = AppTheme.ink;
    canvas.drawCircle(c, radius * 0.12, hole);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.turn != turn;
}
