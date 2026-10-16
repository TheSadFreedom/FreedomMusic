import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Compact Yandex-Music-style pill segmented control (no Material checkmarks).
class PillSegmented<T> extends StatelessWidget {
  const PillSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Matches Listen / chart accent yellow used elsewhere in the app.
  static const accent = Color(0xFFFFDB4D);

  @override
  Widget build(BuildContext context) {
    assert(segments.isNotEmpty);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.inkLift.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.paper.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final segment in segments)
              _PillSegmentButton(
                label: segment.label,
                selected: segment.value == selected,
                onTap: () {
                  if (segment.value != selected) {
                    onChanged(segment.value);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class PillSegment<T> {
  const PillSegment({required this.value, required this.label});

  final T value;
  final String label;
}

class _PillSegmentButton extends StatelessWidget {
  const _PillSegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashColor: Colors.black.withValues(alpha: 0.08),
        highlightColor: Colors.black.withValues(alpha: 0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? PillSegmented.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            style: GoogleFonts.figtree(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: -0.1,
              height: 1.15,
              color: selected ? AppTheme.ink : AppTheme.paperMuted,
            ),
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }
}
