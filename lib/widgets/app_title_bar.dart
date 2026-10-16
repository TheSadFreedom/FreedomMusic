import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../services/desktop_shell.dart';
import '../theme/app_theme.dart';

const double kAppTitleBarHeight = 40;

/// Custom Windows title bar: brand + drag region + window controls.
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key});

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    final value = await windowManager.isMaximized();
    if (mounted && value != _maximized) {
      setState(() => _maximized = value);
    }
  }

  @override
  void onWindowMaximize() => _refreshMaximized();

  @override
  void onWindowUnmaximize() => _refreshMaximized();

  @override
  void onWindowRestore() => _refreshMaximized();

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.ink,
      child: SizedBox(
        height: kAppTitleBarHeight,
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _toggleMaximize,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFFDB4D),
                                AppTheme.mossBright,
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.graphic_eq_rounded,
                            size: 14,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Freedom',
                                style: GoogleFonts.syne(
                                  color: AppTheme.paper,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  letterSpacing: -0.3,
                                  height: 1,
                                ),
                              ),
                              TextSpan(
                                text: ' Music',
                                style: GoogleFonts.syne(
                                  color: AppTheme.mossBright,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: -0.2,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _CaptionButton(
              tooltip: 'Закрепить плеер',
              onPressed: () => context.read<DesktopShell>().enterCompactMode(),
              child: const Icon(Icons.push_pin_outlined, size: 15),
            ),
            _CaptionButton(
              tooltip: 'Свернуть в трей',
              onPressed: () => context.read<DesktopShell>().hideToTray(),
              child: const Icon(Icons.remove_rounded, size: 16),
            ),
            _CaptionButton(
              tooltip: _maximized ? 'Восстановить' : 'Развернуть',
              onPressed: _toggleMaximize,
              child: Icon(
                _maximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                size: _maximized ? 12 : 15,
              ),
            ),
            _CaptionButton(
              tooltip: 'Закрыть',
              danger: true,
              onPressed: () => context.read<DesktopShell>().quit(),
              child: const Icon(Icons.close_rounded, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.child,
    required this.onPressed,
    required this.tooltip,
    this.danger = false,
  });

  final Widget child;
  final VoidCallback onPressed;
  final String tooltip;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = !_hover
        ? Colors.transparent
        : widget.danger
            ? const Color(0xFFE81123)
            : AppTheme.paper.withValues(alpha: 0.08);
    final fg = _hover && widget.danger
        ? Colors.white
        : AppTheme.paperMuted;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: kAppTitleBarHeight,
            color: bg,
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(color: fg, size: 16),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
