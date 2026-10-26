import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/track_key.dart';
import '../models/artist_release.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/screen_title.dart';
import '../widgets/track_overflow_menu.dart';
import 'release_detail_screen.dart';
import 'release_metadata_editor_screen.dart';

const _kSpineWidth = 28.0;
const _kCoverTop = 6.0;
const _kChipGap = 10.0;
const _kYearExtent = 52.0;
const _kCoverSize = 112.0;
const _kReleaseExtent = 200.0;
const _kReleasesPerRow = 100;
const _kListTopPadding = 4.0;
const _kCoverFallback = ColoredBox(
  color: AppTheme.inkLift,
  child: Icon(Icons.album, color: AppTheme.mossBright, size: 40),
);

/// All albums, EPs, and singles, newest year first, as one vertical timeline.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _scroll = ScrollController();
  final _horizontal = ScrollController();
  final _activeYear = ValueNotifier<int>(0);
  final _yearKeys = <GlobalKey>[];
  var _yearOffsets = const <double>[];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncActiveYear);
    _activeYear.addListener(_revealActiveChip);
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncActiveYear);
    _activeYear.removeListener(_revealActiveChip);
    _scroll.dispose();
    _horizontal.dispose();
    _activeYear.dispose();
    super.dispose();
  }

  void _syncKeys(int count) {
    while (_yearKeys.length < count) {
      _yearKeys.add(GlobalKey());
    }
    if (_yearKeys.length > count) {
      _yearKeys.removeRange(count, _yearKeys.length);
    }
  }

  void _syncActiveYear() {
    if (!_scroll.hasClients || _yearOffsets.isEmpty) return;
    final offset = _scroll.offset + 1;
    var index = 0;
    for (var i = 0; i < _yearOffsets.length; i++) {
      if (_yearOffsets[i] <= offset) {
        index = i;
      } else {
        break;
      }
    }
    if (_activeYear.value != index) _activeYear.value = index;
  }

  void _revealActiveChip() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _activeYear.value;
      if (index < 0 || index >= _yearKeys.length) return;
      final target = _yearKeys[index].currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToYear(int index) {
    if (!_scroll.hasClients || index < 0 || index >= _yearOffsets.length) {
      return;
    }
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      _yearOffsets[index].clamp(0.0, max),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  List<double> _offsetsFor(List<_TimelineRow> rows) {
    final offsets = <double>[];
    var y = _kListTopPadding;
    for (final row in rows) {
      if (row is _YearMark) offsets.add(y);
      y += row is _YearMark ? _kYearExtent : _kReleaseExtent;
    }
    return offsets;
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final sections = library.releaseCalendar();
    _syncKeys(sections.length);
    if (sections.isEmpty || _activeYear.value >= sections.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeYear.value != 0) _activeYear.value = 0;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenTitle(title: 'Календарь'),
        if (sections.isNotEmpty)
          _YearJumpBar(
            sections: sections,
            keys: _yearKeys,
            active: _activeYear,
            onSelect: _scrollToYear,
          ),
        Expanded(
          child: sections.isEmpty
              ? Center(
                  child: Text(
                    'Нет релизов',
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 16,
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final rows = _timelineRows(sections);
                    _yearOffsets = _offsetsFor(rows);
                    final width = math.max(
                      math.max(
                        0.0,
                        constraints.maxWidth - AppScrollBehavior.gutter,
                      ),
                      _timelineWidth(sections),
                    );
                    final height = math.max(
                      0.0,
                      constraints.maxHeight - AppScrollBehavior.gutter,
                    );
                    return Scrollbar(
                      controller: _scroll,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.vertical,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: AppScrollBehavior.gutter,
                        ),
                        child: Scrollbar(
                          controller: _horizontal,
                          notificationPredicate: (notification) =>
                              notification.metrics.axis == Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppScrollBehavior.gutter,
                            ),
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                                controller: _horizontal,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: width,
                                  height: height,
                                  child: CustomScrollView(
                                    controller: _scroll,
                                    slivers: [
                                      SliverPadding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          _kListTopPadding,
                                          20,
                                          28,
                                        ),
                                        sliver: SliverVariedExtentList.builder(
                                          itemCount: rows.length,
                                          itemExtentBuilder:
                                              (index, dimensions) {
                                                return rows[index] is _YearMark
                                                    ? _kYearExtent
                                                    : _kReleaseExtent;
                                              },
                                          itemBuilder: (context, index) {
                                            final row = rows[index];
                                            final above = index > 0;
                                            final below =
                                                index < rows.length - 1;
                                            return switch (row) {
                                              _YearMark(
                                                :final label,
                                                :final count,
                                              ) =>
                                                _YearNode(
                                                  label: label,
                                                  count: count,
                                                  above: above,
                                                  below: below,
                                                ),
                                              _ReleaseLine(:final releases) =>
                                                _ReleaseLineNode(
                                                  releases: releases,
                                                  above: above,
                                                  below: below,
                                                ),
                                            };
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _YearJumpBar extends StatelessWidget {
  const _YearJumpBar({
    required this.sections,
    required this.keys,
    required this.active,
    required this.onSelect,
  });

  final List<ReleaseCalendarSection> sections;
  final List<GlobalKey> keys;
  final ValueNotifier<int> active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ValueListenableBuilder<int>(
        valueListenable: active,
        builder: (context, selected, _) {
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  for (var index = 0; index < sections.length; index++) ...[
                    if (index > 0) const SizedBox(width: 6),
                    TextButton(
                      key: keys[index],
                      style: TextButton.styleFrom(
                        foregroundColor: index == selected
                            ? AppTheme.ink
                            : AppTheme.paper,
                        backgroundColor: index == selected
                            ? AppTheme.lime
                            : Colors.white.withValues(alpha: 0.06),
                        enabledMouseCursor: SystemMouseCursors.click,
                        disabledMouseCursor: SystemMouseCursors.basic,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => onSelect(index),
                      child: Text(
                        sections[index].year?.toString() ?? 'Без года',
                        style: GoogleFonts.figtree(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

sealed class _TimelineRow {
  const _TimelineRow();
}

class _YearMark extends _TimelineRow {
  const _YearMark(this.label, this.count);

  final String label;
  final int count;
}

class _ReleaseLine extends _TimelineRow {
  const _ReleaseLine(this.releases);

  final List<ArtistRelease> releases;
}

int _lineCount(int releaseCount) {
  if (releaseCount <= 0) return 0;
  return (releaseCount / _kReleasesPerRow).ceil();
}

/// Longest line after filling top-to-bottom, then the next column.
int _widestLine(int releaseCount) {
  final lines = _lineCount(releaseCount);
  if (lines == 0) return 0;
  return (releaseCount / lines).ceil();
}

double _timelineWidth(List<ReleaseCalendarSection> sections) {
  var maxCount = 0;
  for (final section in sections) {
    final count = _widestLine(section.releases.length);
    if (count > maxCount) maxCount = count;
  }
  return 12 + _kSpineWidth + maxCount * (_kCoverSize + _kChipGap) + 20;
}

/// Biggest releases go down the left column, then the next column.
List<List<ArtistRelease>> _linesByTrackCount(List<ArtistRelease> releases) {
  if (releases.isEmpty) return const [];
  final lineCount = _lineCount(releases.length);
  final lines = List.generate(lineCount, (_) => <ArtistRelease>[]);
  for (var index = 0; index < releases.length; index++) {
    lines[index % lineCount].add(releases[index]);
  }
  return lines;
}

List<_TimelineRow> _timelineRows(List<ReleaseCalendarSection> sections) {
  final rows = <_TimelineRow>[];
  for (final section in sections) {
    rows.add(
      _YearMark(
        section.year?.toString() ?? 'Без года',
        section.releases.length,
      ),
    );
    for (final line in _linesByTrackCount(section.releases)) {
      rows.add(_ReleaseLine(line));
    }
  }
  return rows;
}

class _YearNode extends StatelessWidget {
  const _YearNode({
    required this.label,
    required this.count,
    required this.above,
    required this.below,
  });

  final String label;
  final int count;
  final bool above;
  final bool below;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kYearExtent,
      child: Row(
        children: [
          _Spine(above: above, below: below, year: true),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.syne(
              color: AppTheme.paper,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _releaseCountLabel(count),
            style: GoogleFonts.figtree(
              color: AppTheme.paperMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseLineNode extends StatelessWidget {
  const _ReleaseLineNode({
    required this.releases,
    required this.above,
    required this.below,
  });

  final List<ArtistRelease> releases;
  final bool above;
  final bool below;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kReleaseExtent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _kReleaseExtent,
            child: _Spine(
              above: above,
              below: below,
              year: false,
              dotCenter: _kCoverTop + _kCoverSize / 2,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: _kCoverTop),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < releases.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(right: _kChipGap),
                    child: _ReleaseChip(release: releases[index]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseChip extends StatelessWidget {
  const _ReleaseChip({required this.release});

  final ArtistRelease release;

  @override
  Widget build(BuildContext context) {
    final path = context.read<LibraryService>().releaseCover(release);
    final credit = release.credit?.trim() ?? '';
    final artistLine = credit.isEmpty ? '—' : credit;
    final primary = credit;
    return TrackContextMenu(
      actions: releaseMenuActions(context, release),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ReleaseDetailScreen(release: release, primaryArtist: primary),
            ),
          );
        },
        child: SizedBox(
          width: _kCoverSize,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: _kCoverSize,
                  height: _kCoverSize,
                  child: _cover(context, path),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                metaFieldText(release.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.figtree(
                  color: AppTheme.paper,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.15,
                ),
              ),
              Text(
                artistLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.figtree(
                  color: AppTheme.mossBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
              Text(
                '${releaseKindLabel(release.kind)} · ${formatTrackCount(release.tracks.length)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.figtree(
                  color: AppTheme.paperMuted,
                  fontSize: 11,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _cover(BuildContext context, String? path) {
  if (path == null || path.isEmpty) return _kCoverFallback;
  return fileCover(
    context,
    path,
    logicalSize: _kCoverSize,
    errorBuilder: (context, error, stackTrace) => _kCoverFallback,
  );
}

class _Spine extends StatelessWidget {
  const _Spine({
    required this.above,
    required this.below,
    required this.year,
    this.dotCenter,
  });

  final bool above;
  final bool below;
  final bool year;
  final double? dotCenter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kSpineWidth,
      child: CustomPaint(
        painter: _SpinePainter(
          above: above,
          below: below,
          year: year,
          dotCenter: dotCenter,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SpinePainter extends CustomPainter {
  const _SpinePainter({
    required this.above,
    required this.below,
    required this.year,
    required this.dotCenter,
  });

  final bool above;
  final bool below;
  final bool year;
  final double? dotCenter;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final y = dotCenter ?? size.height / 2;
    final line = Paint()
      ..color = AppTheme.moss.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (above) {
      canvas.drawLine(Offset(x, 0), Offset(x, y), line);
    }
    if (below) {
      canvas.drawLine(Offset(x, y), Offset(x, size.height), line);
    }
    final radius = year ? 6.0 : 4.0;
    canvas.drawCircle(
      Offset(x, y),
      radius,
      Paint()..color = year ? AppTheme.lime : AppTheme.mossBright,
    );
    if (!year) {
      canvas.drawLine(Offset(x + radius, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _SpinePainter oldDelegate) {
    return oldDelegate.above != above ||
        oldDelegate.below != below ||
        oldDelegate.year != year ||
        oldDelegate.dotCenter != dotCenter;
  }
}

String _releaseCountLabel(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return '$count релиз';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$count релиза';
  }
  return '$count релизов';
}
