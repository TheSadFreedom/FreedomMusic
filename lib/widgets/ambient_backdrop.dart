import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Soft color wash for category screens.
///
/// Static (no ticker): per-frame [CustomPaint] + [RadialGradient] shaders
/// were leaking multi‑GB of memory on Windows when settings/other tabs
/// stayed alive inside [IndexedStack].
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    this.accent = AppTheme.moss,
    this.secondary = const Color(0xFF5A3A6E),
  });

  final Color accent;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return ColoredBox(
            color: AppTheme.ink,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(AppTheme.ink, accent, 0.2)!,
                        AppTheme.ink,
                        Color.lerp(AppTheme.ink, secondary, 0.16)!,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: -side * 0.15,
                  top: -side * 0.2,
                  child: _Blob(color: accent, size: side * 0.95, opacity: 0.22),
                ),
                Positioned(
                  right: -side * 0.2,
                  top: -side * 0.15,
                  child: _Blob(
                    color: secondary,
                    size: side * 0.8,
                    opacity: 0.18,
                  ),
                ),
                Positioned(
                  left: side * 0.15,
                  bottom: -side * 0.25,
                  child: _Blob(color: accent, size: side * 1.05, opacity: 0.1),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
