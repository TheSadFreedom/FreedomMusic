import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/desktop_shell.dart';
import 'app_title_bar.dart';
import 'lyrics_view.dart';
import 'mini_player.dart';

/// Height of the player bar, so the rest of the window can sit above it.
class PlayerDock extends ChangeNotifier {
  double _height = 0;
  double get height => _height;

  void setHeight(double value) {
    if ((value - _height).abs() < 0.5) return;
    _height = value;
    notifyListeners();
  }
}

/// Paints the player above routes, dialogs and lyrics.
class AppPlayerLayer extends StatefulWidget {
  const AppPlayerLayer({super.key, required this.child});

  final Widget child;

  @override
  State<AppPlayerLayer> createState() => _AppPlayerLayerState();
}

class _AppPlayerLayerState extends State<AppPlayerLayer> {
  final _dock = PlayerDock();
  final _lyrics = LyricsPresentation();
  late final OverlayEntry _entry = OverlayEntry(builder: _buildStack);

  @override
  void initState() {
    super.initState();
    _dock.addListener(_entry.markNeedsBuild);
    _lyrics.addListener(_entry.markNeedsBuild);
  }

  @override
  void dispose() {
    _dock.removeListener(_entry.markNeedsBuild);
    _lyrics.removeListener(_entry.markNeedsBuild);
    _entry.remove();
    _entry.dispose();
    _dock.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  bool _compact(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return false;
    }
    return context.watch<DesktopShell>().compactMode;
  }

  Widget _buildStack(BuildContext context) {
    final compact = _compact(context);
    final desktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final playerHeight = compact ? 0.0 : _dock.height;
    final lyricsTop = desktop
        ? kAppTitleBarHeight
        : MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: playerHeight),
          child: widget.child,
        ),
        if (!compact && _lyrics.visible)
          Positioned(
            top: lyricsTop,
            left: 0,
            right: 0,
            bottom: playerHeight,
            child: LyricsStage(
              title: _lyrics.title,
              raw: _lyrics.raw,
              fetching: _lyrics.fetching,
              notFound: _lyrics.notFound,
              onClose: _lyrics.requestClose,
            ),
          ),
        if (!compact)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _PlayerDockReporter(
              dock: _dock,
              child: const MiniPlayer(),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _entry.markNeedsBuild();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _dock),
        ChangeNotifierProvider.value(value: _lyrics),
      ],
      child: Overlay(initialEntries: [_entry]),
    );
  }
}

class _PlayerDockReporter extends StatefulWidget {
  const _PlayerDockReporter({required this.dock, required this.child});

  final PlayerDock dock;
  final Widget child;

  @override
  State<_PlayerDockReporter> createState() => _PlayerDockReporterState();
}

class _PlayerDockReporterState extends State<_PlayerDockReporter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  void _report() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final height = box != null && box.hasSize ? box.size.height : 0.0;
    widget.dock.setHeight(height);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _report());
        return false;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}
