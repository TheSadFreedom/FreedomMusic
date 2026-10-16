import 'dart:io';

import 'package:path/path.dart' as p;

/// Portable layout:
///   root/
///     music/
///     data/
///     covers/
///
/// In release: root = folder with the .exe
/// In `flutter run`: root = project folder (where pubspec.yaml lives)
class AppPaths {
  AppPaths._(this.root);

  final String root;

  String get musicDir => p.join(root, 'music');
  String get dataDir => p.join(root, 'data');
  String get coversDir => p.join(root, 'covers');
  String get artistsDir => p.join(coversDir, 'artists');
  String get playlistsDir => p.join(coversDir, 'playlists');
  /// ASCII hardlinks for Windows Media Foundation (Cyrillic / `#` in names).
  String get playCacheDir => p.join(dataDir, 'playcache');
  String get databasePath => p.join(dataDir, 'library.db');

  static Future<AppPaths> resolve() async {
    final exeDir = File(Platform.resolvedExecutable).parent;
    var dir = exeDir;

    for (var i = 0; i < 10; i++) {
      final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
      if (await pubspec.exists()) {
        final paths = AppPaths._(dir.path);
        await paths.ensureDirectories();
        return paths;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    final paths = AppPaths._(exeDir.path);
    await paths.ensureDirectories();
    return paths;
  }

  Future<void> ensureDirectories() async {
    for (final dir in [
      musicDir,
      dataDir,
      coversDir,
      artistsDir,
      playlistsDir,
      playCacheDir,
    ]) {
      await Directory(dir).create(recursive: true);
    }
  }
}
