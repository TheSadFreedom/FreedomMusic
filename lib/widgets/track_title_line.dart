import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Track title with the optional note immediately to its right.
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
    final titleStyle = DefaultTextStyle.of(context).style.merge(base);
    final titleText = Text(
      title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: titleStyle,
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

    final noteStyle = titleStyle.copyWith(
      color: (titleStyle.color ?? AppTheme.paper).withValues(alpha: 0.45),
    );
    final line = LayoutBuilder(
      builder: (context, constraints) {
        return _TitleNoteRow(
          title: titleWidget,
          note: label,
          noteStyle: noteStyle,
          maxWidth: constraints.maxWidth,
          centered: centered,
        );
      },
    );
    if (!centered) return line;
    return Center(child: line);
  }
}

class _TitleNoteRow extends StatelessWidget {
  const _TitleNoteRow({
    required this.title,
    required this.note,
    required this.noteStyle,
    required this.maxWidth,
    required this.centered,
  });

  final Widget title;
  final String note;
  final TextStyle noteStyle;
  final double maxWidth;
  final bool centered;

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final noteText = Text(
      note,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: noteStyle,
    );
    if (!maxWidth.isFinite) {
      return Row(
        mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Flexible(child: title),
          const SizedBox(width: _gap),
          noteText,
        ],
      );
    }

    final natural = _singleLineWidth(context, note, noteStyle);
    final noteFits = natural + _gap <= maxWidth;
    final noteWidth = noteFits ? natural : maxWidth;
    final titleWidth = noteFits ? maxWidth - _gap - natural : 0.0;

    return Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (titleWidth > 0)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: titleWidth),
            child: title,
          ),
        if (titleWidth > 0) const SizedBox(width: _gap),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.max(noteWidth, 0)),
          child: noteText,
        ),
      ],
    );
  }
}

double _singleLineWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width.ceilToDouble();
}
