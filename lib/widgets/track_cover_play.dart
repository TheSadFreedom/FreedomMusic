import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Square cover that shows a white play button on hover.
class TrackCoverPlay extends StatefulWidget {
  const TrackCoverPlay({
    super.key,
    required this.onPlay,
    this.path,
    this.size = 48,
    this.borderRadius = 6,
  });

  final String? path;
  final double size;
  final double borderRadius;
  final VoidCallback onPlay;

  @override
  State<TrackCoverPlay> createState() => _TrackCoverPlayState();
}

class _TrackCoverPlayState extends State<TrackCoverPlay> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget image = ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(
        Icons.music_note,
        color: AppTheme.mossBright,
        size: widget.size * 0.45,
      ),
    );
    final path = widget.path;
    if (path != null && path.isNotEmpty) {
      final placeholder = image;
      final px = (widget.size * 2).round().clamp(48, 256);
      image = Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: px,
        cacheHeight: px,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => placeholder,
        gaplessPlayback: true,
      );
    }

    return MouseRegion(
      onEnter: (_) {
        final scrolling =
            Scrollable.maybeOf(context)?.position.isScrollingNotifier.value ??
                false;
        if (scrolling || _hover) return;
        setState(() => _hover = true);
      },
      onExit: (_) {
        if (!_hover) return;
        setState(() => _hover = false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPlay,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (_hover) ...[
                  ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                  Center(
                    child: Container(
                      width: widget.size * 0.52,
                      height: widget.size * 0.52,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black87,
                        size: widget.size * 0.36,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
