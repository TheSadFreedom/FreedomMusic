import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/lyrics_format.dart';
import 'app_title_bar.dart';

/// Full-window lyrics. The player bar stays visible underneath.
class LyricsStage extends StatefulWidget {
  const LyricsStage({
    super.key,
    required this.anchorKey,
    required this.title,
    required this.raw,
    required this.fetching,
    required this.notFound,
    required this.onClose,
  });

  final GlobalKey anchorKey;
  final String title;
  final String? raw;
  final bool fetching;
  final bool notFound;
  final VoidCallback onClose;

  @override
  State<LyricsStage> createState() => _LyricsStageState();
}

class _LyricsStageState extends State<LyricsStage> with WidgetsBindingObserver {
  double _top = 0;
  double _bottom = 96;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _measure();
  }

  @override
  void didUpdateWidget(covariant LyricsStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = widget.anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize || !overlay.hasSize) {
      return;
    }
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottom = (overlay.size.height - origin.dy).clamp(0.0, overlay.size.height);
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final top = desktop
        ? kAppTitleBarHeight
        : MediaQuery.paddingOf(context).top;
    if (top == _top && (bottom - _bottom).abs() < 0.5) return;
    setState(() {
      _top = top;
      _bottom = bottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = parseLyricLines(widget.raw);
    return Positioned(
      left: 0,
      right: 0,
      top: _top,
      bottom: _bottom,
      child: Material(
        color: AppTheme.ink,
        child: Column(
          children: [
            _Header(title: widget.title, onClose: widget.onClose),
            Expanded(
              child: lines.isEmpty
                  ? _EmptyLyrics(
                      fetching: widget.fetching,
                      notFound: widget.notFound,
                    )
                  : _LyricScroller(lines: lines),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Row(
        children: [
          const SizedBox(width: 72),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Сейчас играет',
                  style: GoogleFonts.figtree(
                    color: AppTheme.paperMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.syne(
                    color: AppTheme.paper,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              onPressed: onClose,
              mouseCursor: SystemMouseCursors.click,
              iconSize: 36,
              icon: const Icon(Icons.close, color: AppTheme.paper),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLyrics extends StatelessWidget {
  const _EmptyLyrics({required this.fetching, required this.notFound});

  final bool fetching;
  final bool notFound;

  @override
  Widget build(BuildContext context) {
    final message = fetching
        ? 'Ищем текст на LRCLIB…'
        : notFound
            ? 'Текст не найден'
            : 'Текста нет';
    return Center(
      child: fetching
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppTheme.lime,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  message,
                  style: GoogleFonts.figtree(
                    color: AppTheme.paperMuted,
                    fontSize: 18,
                  ),
                ),
              ],
            )
          : Text(
              message,
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

class _LyricScroller extends StatefulWidget {
  const _LyricScroller({required this.lines});

  final List<LyricLine> lines;

  @override
  State<_LyricScroller> createState() => _LyricScrollerState();
}

class _LyricScrollerState extends State<_LyricScroller> {
  final _scroll = ScrollController();
  late List<GlobalKey> _keys;
  int? _centered;
  int? _pending;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lines.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(covariant _LyricScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines.length != widget.lines.length) {
      _keys = List.generate(widget.lines.length, (_) => GlobalKey());
      _centered = null;
      _pending = null;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reveal(int index) {
    if (index < 0 || index == _centered || index == _pending) return;
    if (index >= _keys.length) return;
    _pending = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _keys[index].currentContext;
      if (target == null) {
        if (_pending == index) _pending = null;
        return;
      }
      _centered = index;
      _pending = null;
      Scrollable.ensureVisible(
        target,
        alignment: 0.34,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final synced = widget.lines.any((line) => line.synced);
    final position = synced
        ? context.select<PlayerService, Duration>((player) => player.position)
        : Duration.zero;
    final active = synced ? lyricIndexAt(widget.lines, position) : -1;
    if (synced) _reveal(active);

    final wide = MediaQuery.sizeOf(context).width >= 720;

    return RawScrollbar(
      controller: _scroll,
      thumbVisibility: true,
      interactive: true,
      thickness: 8,
      radius: const Radius.circular(8),
      thumbColor: AppTheme.paperMuted.withValues(alpha: 0.55),
      crossAxisMargin: 4,
      mainAxisMargin: 8,
      padding: EdgeInsets.zero,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.14, 0.78, 1.0],
          ).createShader(rect);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pad = constraints.maxHeight * 0.34;
            return SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                wide ? 72 : 28,
                pad,
                wide ? 28 : 20,
                pad,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < widget.lines.length; i++)
                    _Line(
                      key: _keys[i],
                      text: widget.lines[i].text,
                      role: _role(i, active, synced),
                      wide: wide,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  _LineRole _role(int index, int active, bool synced) {
    if (!synced || active < 0) return _LineRole.plain;
    final distance = index - active;
    if (distance == 0) return _LineRole.current;
    if (distance == 1) return _LineRole.next;
    if (distance > 1) return _LineRole.later;
    return _LineRole.past;
  }
}

enum _LineRole { current, next, later, past, plain }

class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.text,
    required this.role,
    required this.wide,
  });

  final String text;
  final _LineRole role;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final style = switch (role) {
      _LineRole.current => GoogleFonts.figtree(
          color: AppTheme.paper,
          fontSize: wide ? 40 : 30,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      _LineRole.next => GoogleFonts.figtree(
          color: AppTheme.paper.withValues(alpha: 0.55),
          fontSize: wide ? 26 : 20,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      _LineRole.later => GoogleFonts.figtree(
          color: AppTheme.paper.withValues(alpha: 0.28),
          fontSize: wide ? 24 : 18,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      _LineRole.past => GoogleFonts.figtree(
          color: AppTheme.paper.withValues(alpha: 0.22),
          fontSize: wide ? 22 : 17,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      _LineRole.plain => GoogleFonts.figtree(
          color: AppTheme.paper,
          fontSize: wide ? 32 : 24,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
    };

    return Padding(
      padding: EdgeInsets.symmetric(vertical: role == _LineRole.current ? 14 : 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}
