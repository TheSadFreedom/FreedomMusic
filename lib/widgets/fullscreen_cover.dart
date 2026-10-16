import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Opens [path] in a dismissible full-screen viewer (tap / Esc / back).
Future<void> showFullscreenCover(BuildContext context, String? path) async {
  if (path == null || path.isEmpty || !File(path).existsSync()) return;

  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondary) {
        return FadeTransition(
          opacity: animation,
          child: _FullscreenCoverPage(path: path),
        );
      },
    ),
  );
}

class _FullscreenCoverPage extends StatelessWidget {
  const _FullscreenCoverPage({required this.path});

  final String path;

  void _close(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _close(context),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _close(context),
                child: const ColoredBox(color: Colors.transparent),
              ),
              Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: GestureDetector(
                    onTap: () => _close(context),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.92,
                        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                      ),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: AppTheme.inkLift,
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 64,
                                color: AppTheme.paperMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: 12,
                child: IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => _close(context),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    foregroundColor: AppTheme.paper,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
