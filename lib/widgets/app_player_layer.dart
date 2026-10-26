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
  final _playerBarKey = GlobalKey();
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
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final playerHeight = compact ? 0.0 : _dock.height;
    final lyricsTop = desktop
        ? kAppTitleBarHeight
        : MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: playerHeight),
          child: widget.child,
        ),
        // Keys keep the player state when the lyrics stage is inserted before
        // it. Without them the player is rebuilt and closes the lyrics again.
        if (!compact && _lyrics.visible)
          Positioned(
            key: const ValueKey('lyrics-stage'),
            top: lyricsTop,
            left: 0,
            right: 0,
            bottom: playerHeight,
            child: LyricsStage(
              title: _lyrics.title,
              note: _lyrics.note,
              raw: _lyrics.raw,
              fetching: _lyrics.fetching,
              notFound: _lyrics.notFound,
            ),
          ),
        if (!compact)
          Positioned(
            key: const ValueKey('player-dock'),
            left: 0,
            right: 0,
            bottom: 0,
            // Высота дока = только бар (без эквалайзера), чтобы контент
            // оставался под панелью, а клики по EQ доходили.
            child: _PlayerDockReporter(
              dock: _dock,
              measureKey: _playerBarKey,
              child: MiniPlayer(barKey: _playerBarKey),
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
  const _PlayerDockReporter({
    required this.dock,
    required this.measureKey,
    required this.child,
  });

  final PlayerDock dock;
  final GlobalKey measureKey;
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
    final box =
        widget.measureKey.currentContext?.findRenderObject() as RenderBox?;
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
