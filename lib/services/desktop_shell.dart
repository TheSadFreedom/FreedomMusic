import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'player_service.dart';

/// Windows tray + close-to-tray + compact always-on-top player.
class DesktopShell extends ChangeNotifier with WindowListener {
  DesktopShell(this._player);

  final PlayerService _player;
  TrayIcon? _tray;
  MenuItem? _playItem;
  final List<ListenerId> _listeners = [];
  bool _quitting = false;

  bool _compactMode = false;
  bool get compactMode => _compactMode;

  Rect? _savedBounds;
  bool _savedAlwaysOnTop = false;

  static const Size compactSize = Size(540, 100);
  static const Size normalMinSize = Size(880, 560);
  static const Size unlockedMaxSize = Size(100000, 100000);

  Future<void> init() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return;
    }

    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    if (Platform.isWindows) {
      await _initTray();
    }
  }

  Future<void> _initTray() async {
    try {
      final tray = TrayIcon.create();
      if (tray == null) {
        debugPrint('TrayIcon.create returned null');
        return;
      }
      _tray = tray;

      final icon = ImageAsset.fromAsset('assets/app_icon.ico');
      if (icon != null) {
        tray.icon = icon;
      } else {
        final fromFile = Image.fromFile('assets/app_icon.ico');
        if (fromFile != null) tray.icon = fromFile;
      }
      tray.setTooltip('Freedom Music');

      final menu = Menu.create();
      if (menu != null) {
        _addMenuItem(menu, 'Открыть', showWindow);
        menu.addSeparator();
        _playItem = _addMenuItem(
          menu,
          _playLabel(),
          () => _player.togglePlayPause(),
        );
        _addMenuItem(menu, 'Следующий', () => _player.next());
        _addMenuItem(menu, 'Предыдущий', () => _player.previous());
        menu.addSeparator();
        _addMenuItem(menu, 'Выход', quit);
        tray.setContextMenu(menu);
        tray.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      }

      _listeners.add(
        tray.addListener((event) {
          switch (event) {
            case TrayIconClickedEvent():
            case TrayIconDoubleClickedEvent():
              unawaited(showWindow());
            case TrayIconRightClickedEvent():
              _playItem?.label = _playLabel();
          }
        }),
      );

      tray.setVisible(true);
    } catch (e, st) {
      debugPrint('Tray init failed: $e\n$st');
    }
  }

  String _playLabel() => _player.playing ? 'Пауза' : 'Воспроизвести';

  MenuItem? _addMenuItem(
    Menu menu,
    String label,
    FutureOr<void> Function() action,
  ) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) return null;
    _listeners.add(
      item.addListener((event) {
        if (event is MenuItemClickedEvent) {
          unawaited(Future.sync(action));
        }
      }),
    );
    menu.addItem(item);
    return item;
  }

  Future<void> showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideToTray() async {
    await _player.persistSession();
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> toggleCompactMode() async {
    if (_compactMode) {
      await exitCompactMode();
    } else {
      await enterCompactMode();
    }
  }

  Future<void> enterCompactMode() async {
    if (_compactMode) return;

    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }

    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    _savedBounds = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
    _savedAlwaysOnTop = await windowManager.isAlwaysOnTop();

    await windowManager.setAlwaysOnTop(true);
    await windowManager.setMinimumSize(compactSize);
    await windowManager.setMaximumSize(compactSize);
    await windowManager.setSize(compactSize);
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();

    _compactMode = true;
    notifyListeners();
  }

  /// Keeps the compact window locked, but tall enough for an inline panel.
  /// If the extra height would leave the screen, the window shifts up.
  Future<void> resizeCompact(Size size, {required Rect workArea}) async {
    if (!_compactMode) return;
    final pos = await windowManager.getPosition();
    var top = pos.dy;
    var left = pos.dx;
    final maxTop = workArea.bottom - size.height;
    if (top > maxTop) top = maxTop;
    if (top < workArea.top) top = workArea.top;
    final maxLeft = workArea.right - size.width;
    if (left > maxLeft) left = maxLeft;
    if (left < workArea.left) left = workArea.left;

    final current = await windowManager.getSize();
    final growing = size.width > current.width + 0.5 ||
        size.height > current.height + 0.5;
    if (growing) {
      await windowManager.setMaximumSize(size);
      await windowManager.setMinimumSize(size);
    } else {
      await windowManager.setMinimumSize(size);
      await windowManager.setMaximumSize(size);
    }
    await windowManager.setSize(size);
    if ((top - pos.dy).abs() > 0.5 || (left - pos.dx).abs() > 0.5) {
      await windowManager.setPosition(Offset(left, top));
    }
  }

  Future<void> exitCompactMode() async {
    if (!_compactMode) return;

    await windowManager.setMaximumSize(unlockedMaxSize);
    await windowManager.setMinimumSize(normalMinSize);
    await windowManager.setAlwaysOnTop(_savedAlwaysOnTop);

    final bounds = _savedBounds;
    if (bounds != null && bounds.width >= normalMinSize.width) {
      await windowManager.setSize(Size(bounds.width, bounds.height));
      await windowManager.setPosition(Offset(bounds.left, bounds.top));
    } else {
      await windowManager.setSize(const Size(1280, 720));
      await windowManager.center();
    }

    _savedBounds = null;
    _compactMode = false;
    notifyListeners();
    await windowManager.focus();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    await _player.persistSession();
    windowManager.removeListener(this);
    _listeners.clear();
    _tray?.dispose();
    _tray = null;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    unawaited(quit());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tray?.dispose();
    _tray = null;
    super.dispose();
  }
}
