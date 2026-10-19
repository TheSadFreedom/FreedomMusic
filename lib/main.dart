import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'data/app_paths.dart';
import 'data/database.dart';
import 'navigation/app_navigator.dart';
import 'screens/shell.dart';
import 'services/audio_handler.dart';
import 'services/desktop_shell.dart';
import 'services/library_service.dart';
import 'services/player_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_player_layer.dart';
import 'widgets/startup_splash.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep decoded covers bounded (full-res Image.file can otherwise balloon RAM).
  final images = PaintingBinding.instance.imageCache;
  images.maximumSize = 200;
  images.maximumSizeBytes = 64 << 20; // 64 MB

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0E0E0C),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    // Dark HWND so we never flash a white empty frame before Flutter paints.
    const options = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(880, 560),
      center: true,
      backgroundColor: Color(0xFF0C1210),
      skipTaskbar: false,
      title: 'Freedom Music',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    // Prepare window but do NOT show yet — show after first Flutter frame.
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setTitle('Freedom Music');
      await windowManager.setMaximumSize(const Size(100000, 100000));
      await windowManager.setMinimumSize(const Size(880, 560));
    });
  }

  runApp(const _BootApp());

  if (_isDesktop) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class _BootApp extends StatefulWidget {
  const _BootApp();

  @override
  State<_BootApp> createState() => _BootAppState();
}

class _Ready {
  const _Ready({
    required this.settings,
    required this.library,
    required this.player,
    this.desktopShell,
  });

  final SettingsService settings;
  final LibraryService library;
  final PlayerService player;
  final DesktopShell? desktopShell;
}

class _BootAppState extends State<_BootApp> {
  _Ready? _ready;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    // Let the splash paint before SQLite, the scanner and Media Foundation.
    await Future<void>.delayed(Duration.zero);
    try {
      final settings = await SettingsService.create();
      final paths = await AppPaths.resolve();
      final db = await AppDatabase.open(paths);
      final library = LibraryService(paths: paths, db: db, settings: settings);
      final player = PlayerService(library, settings);
      await library.init();
      await player.restoreSession();
      await initAudioHandler(player);
      DesktopShell? desktopShell;
      if (_isDesktop) {
        desktopShell = DesktopShell(player);
        await desktopShell.init();
      }
      if (!mounted) return;
      setState(() {
        _ready = _Ready(
          settings: settings,
          library: library,
          player: player,
          desktopShell: desktopShell,
        );
      });
      if (settings.playOnStartup) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(player.startOnLaunch());
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    if (ready == null) {
      return MaterialApp(
        title: 'Freedom Music',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppTheme.ink,
        ),
        home: StartupSplash(error: _error),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ready.settings),
        ChangeNotifierProvider.value(value: ready.library),
        ChangeNotifierProvider.value(value: ready.player),
        if (ready.desktopShell != null)
          ChangeNotifierProvider.value(value: ready.desktopShell),
      ],
      child: const FreedomMusicApp(),
    );
  }
}

class FreedomMusicApp extends StatelessWidget {
  const FreedomMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Freedom Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (context, child) {
        return TooltipVisibility(
          visible: false,
          child: AppPlayerLayer(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const AppShell(),
    );
  }
}
