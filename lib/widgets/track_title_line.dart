import 'package:flutter/material.dart';

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
    final base = style ?? const TextStyle(color: AppTheme.paper);
    final titleText = Text(
      title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: base,
    );
    final titleWidget = onTap == null
        ? titleText
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: titleText,
            ),
          );
    if (label.isEmpty) return titleWidget;
    final line = Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Flexible(child: titleWidget),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(
              color: (base.color ?? AppTheme.paper).withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
    if (!centered) return line;
    return Center(child: line);
  }
}
