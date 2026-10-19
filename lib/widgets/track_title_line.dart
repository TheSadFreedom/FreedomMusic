import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Track title with the optional note badge beside it.
class TrackTitleLine extends StatelessWidget {
  const TrackTitleLine({
    super.key,
    required this.title,
    this.note,
    this.style,
    this.maxLines = 1,
    this.onTap,
    this.centered = false,
  });

  final String title;
  final String? note;
  final TextStyle? style;
  final int maxLines;
  final VoidCallback? onTap;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final label = note?.trim() ?? '';
    final text = Text(
      title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: style,
    );
    final titleWidget = onTap == null
        ? text
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: text,
            ),
          );
    if (label.isEmpty) return titleWidget;
    final line = Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: titleWidget),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: TrackNoteBadge(label),
        ),
      ],
    );
    if (!centered) return line;
    return Center(child: line);
  }
}

class TrackNoteBadge extends StatelessWidget {
  const TrackNoteBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.figtree(
            color: AppTheme.paper,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
