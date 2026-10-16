import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../services/desktop_shell.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/breakpoints.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/compact_player.dart';
import '../widgets/mini_player.dart';
import 'artists_screen.dart';
import 'chart_screen.dart';
import 'home_screen.dart';
import 'playlists_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// Per-tab navigators so detail pages don't cover the mini player.
  final List<GlobalKey<NavigatorState>> _navKeys = List.generate(
    6,
    (_) => GlobalKey<NavigatorState>(),
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  static const _navItems = <_NavItem>[
    _NavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Главная',
    ),
    _NavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Артисты',
    ),
    _NavItem(
      icon: Icons.headphones_rounded,
      selectedIcon: Icons.headphones_rounded,
      label: 'Продюсеры',
    ),
    _NavItem(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Чарт',
    ),
    _NavItem(
      icon: Icons.queue_music_outlined,
      selectedIcon: Icons.queue_music,
      label: 'Плейлисты',
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Настройки',
    ),
  ];

  static const _topCount = 5;
  static const _settingsIndex = 5;

  Widget _tabRoot(int index) {
    final page = switch (index) {
      0 => const HomeScreen(),
      1 => const ArtistsScreen(),
      2 => const ArtistsScreen(producers: true),
      3 => const ChartScreen(),
      4 => const PlaylistsScreen(),
      _ => const SettingsScreen(),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        if (index != 0)
          AmbientBackdrop(
            accent: switch (index) {
              1 => const Color(0xFF3D6B8B),
              2 => const Color(0xFF6B8B3D),
              3 => const Color(0xFF8B6B3D),
              4 => const Color(0xFF5A3A6E),
              _ => AppTheme.moss,
            },
            secondary: switch (index) {
              4 => const Color(0xFF3D2A5C),
              3 => const Color(0xFF5A3A2A),
              2 => const Color(0xFF3A4A2A),
              _ => const Color(0xFF2A4A5C),
            },
          ),
        page,
      ],
    );
  }

  void _select(int i) {
    if (i == _index) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _index = i);
  }

  bool get _textInputFocused {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_textInputFocused) return false;
    if (!mounted) return false;

    final player = context.read<PlayerService>();
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      // Space only on key down — avoid double toggle on key repeat.
      if (event is KeyDownEvent) {
        player.togglePlayPause();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      player.seekBy(const Duration(seconds: 10));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      player.seekBy(const Duration(seconds: -10));
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    final phone = isPhone(context);
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final shell = desktop ? context.watch<DesktopShell>() : null;
    final compact = shell?.compactMode ?? false;

    if (compact) {
      return const Material(
        color: Color(0xFF1A1A1A),
        child: CompactPlayer(),
      );
    }

    final body = Row(
      children: [
        if (wide)
          _SideRail(
            selectedIndex: _index,
            onSelect: _select,
            items: _navItems,
            topCount: _topCount,
            settingsIndex: _settingsIndex,
          ),
        if (wide) const VerticalDivider(width: 1),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _navItems.length; i++)
                // Stop tickers on hidden tabs — otherwise HomeStage / old
                // backdrops kept animating and leaking GPU memory.
                TickerMode(
                  enabled: i == _index,
                  child: Navigator(
                    key: _navKeys[i],
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute<void>(
                        settings: settings,
                        builder: (_) => _tabRoot(i),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Material(
      color: AppTheme.ink,
      child: SafeArea(
        top: !desktop,
        bottom: false,
        child: Column(
          children: [
            if (desktop) const AppTitleBar(),
            Expanded(
              child: desktop ? DragToResizeArea(child: body) : body,
            ),
            const MiniPlayer(),
            if (!wide)
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                height: phone ? 64 : 56,
                labelBehavior: phone
                    ? NavigationDestinationLabelBehavior.alwaysShow
                    : NavigationDestinationLabelBehavior.alwaysHide,
                destinations: [
                  for (final item in _navItems)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.selectedIndex,
    required this.onSelect,
    required this.items,
    required this.topCount,
    required this.settingsIndex,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<_NavItem> items;
  final int topCount;
  final int settingsIndex;

  static const double _width = 72;
  static const double _btnSize = 48;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.ink,
      child: SizedBox(
        width: _width,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                for (var i = 0; i < topCount; i++)
                  _RailButton(
                    item: items[i],
                    selected: selectedIndex == i,
                    size: _btnSize,
                    onTap: () => onSelect(i),
                  ),
                const Spacer(),
                _RailButton(
                  item: items[settingsIndex],
                  selected: selectedIndex == settingsIndex,
                  size: _btnSize,
                  onTap: () => onSelect(settingsIndex),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.item,
    required this.selected,
    required this.size,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.lime : AppTheme.paperMuted;
    final fill = selected
        ? AppTheme.moss.withValues(alpha: 0.35)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: item.label,
        waitDuration: const Duration(milliseconds: 400),
        child: Material(
          color: fill,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            mouseCursor: SystemMouseCursors.click,
            onTap: onTap,
            hoverColor: AppTheme.moss.withValues(alpha: 0.22),
            splashColor: AppTheme.moss.withValues(alpha: 0.28),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                color: color,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
