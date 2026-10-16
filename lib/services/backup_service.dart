import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../data/app_paths.dart';
import '../data/database.dart';
import 'settings_service.dart';

class BackupResult {
  const BackupResult({required this.message, this.path});

  final String message;
  final String? path;
}

/// Export / import app data that is not file metadata:
/// playlists, play history, artist photos, playlist covers, chart deltas, settings.
class BackupService {
  BackupService({
    required AppPaths paths,
    required AppDatabase db,
    required SettingsService settings,
  })  : _paths = paths,
        _db = db,
        _settings = settings;

  static const formatVersion = 1;
  static const manifestName = 'manifest.json';

  final AppPaths _paths;
  final AppDatabase _db;
  final SettingsService _settings;

  Future<BackupResult> exportToFile(String destPath) async {
    await _paths.ensureDirectories();

    final playlists = await _db.getPlaylists();
    final playlistPayload = <Map<String, Object?>>[];
    final archive = Archive();

    final artistFiles = <String, String>{}; // zipPath -> absolute source
    final artistPhotos = <String, String>{};
    for (final entry in _settings.exportArtistPhotoPaths().entries) {
      final src = File(entry.value);
      if (!await src.exists()) continue;
      final ext =
          p.extension(src.path).isEmpty ? '.jpg' : p.extension(src.path);
      var zipName = 'artists/${_safeName(entry.key)}$ext';
      if (artistFiles.containsKey(zipName) &&
          artistFiles[zipName] != src.path) {
        zipName = 'artists/${_safeName(entry.key)}_${artistFiles.length}$ext';
      }
      artistFiles[zipName] = src.path;
      artistPhotos[entry.key] = zipName;
    }

    final playlistCoverFiles = <String, String>{};
    for (final pl in playlists) {
      String? coverZip;
      final cover = pl.coverPath;
      if (cover != null && cover.isNotEmpty) {
        final src = File(cover);
        if (await src.exists()) {
          final ext =
              p.extension(src.path).isEmpty ? '.jpg' : p.extension(src.path);
          coverZip = 'playlists/pl_${pl.id}$ext';
          playlistCoverFiles[coverZip] = src.path;
        }
      }
      final keys = await _db.getPlaylistTrackKeys(pl.id);
      playlistPayload.add({
        'name': pl.name,
        'createdAt': pl.createdAt.millisecondsSinceEpoch,
        'updatedAt': pl.updatedAt?.millisecondsSinceEpoch,
        'description': pl.description,
        'cover': coverZip,
        'systemKind': pl.systemKind,
        'tracks': keys,
      });
    }

    final events = await _db.getAllPlayEvents();
    final trashed = await _db.getTrashedTrackEntries();
    final added = await _db.getTrackAddedAtEntries();
    final manifest = <String, Object?>{
      'formatVersion': formatVersion,
      'app': 'Freedom Music',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': _settings.exportSettingsFlags(),
      'artistPhotos': artistPhotos,
      'chartSnapshots': _settings.exportChartSnapshots(),
      'playlists': playlistPayload,
      'trashedTracks': [
        for (final e in trashed)
          {'trackKey': e.trackKey, 'trashedAt': e.trashedAt},
      ],
      'trackAddedAt': [
        for (final e in added)
          {'trackKey': e.trackKey, 'addedAt': e.addedAt},
      ],
      'playEvents': [
        for (final e in events)
          {'trackKey': e.trackKey, 'playedAt': e.playedAt},
      ],
    };

    final manifestBytes =
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    archive.addFile(
      ArchiveFile(manifestName, manifestBytes.length, manifestBytes),
    );

    for (final entry in {...artistFiles, ...playlistCoverFiles}.entries) {
      final bytes = await File(entry.value).readAsBytes();
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }

    final encoded = ZipEncoder().encodeBytes(archive);
    final out = File(destPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(encoded, flush: true);

    final plCount = playlists.length;
    final evCount = events.length;
    final photoCount = artistPhotos.length;
    return BackupResult(
      path: destPath,
      message: 'Экспортировано: $plCount плейлистов, $evCount прослушиваний, '
          '$photoCount фото артистов.',
    );
  }

  Future<BackupResult> importFromBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = _findFile(archive, manifestName);
    if (manifestFile == null) {
      throw StateError('В архиве нет $manifestName');
    }
    final raw = utf8.decode(manifestFile.readBytes()!);
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) {
      throw StateError('Некорректный манифест');
    }
    final version = json['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw StateError('Неподдерживаемая версия бэкапа: $version');
    }

    await _paths.ensureDirectories();

    // Clear old custom images we manage (best-effort).
    await _clearDirContents(_paths.artistsDir);
    await _clearDirContents(_paths.playlistsDir);

    final artistPhotosRaw = json['artistPhotos'];
    final artistMap = <String, String>{};
    if (artistPhotosRaw is Map) {
      for (final e in artistPhotosRaw.entries) {
        final artistKey = e.key.toString();
        final zipPath = e.value?.toString();
        if (zipPath == null || zipPath.isEmpty) continue;
        final file = _findFile(archive, zipPath);
        if (file == null) continue;
        final bytes = file.readBytes();
        if (bytes == null) continue;
        final localName = p.basename(zipPath);
        final dest = File(p.join(_paths.artistsDir, localName));
        await dest.writeAsBytes(bytes, flush: true);
        artistMap[artistKey] = dest.path;
      }
    }

    final playlistRows = <PlaylistImportRow>[];
    final playlistsRaw = json['playlists'];
    if (playlistsRaw is List) {
      for (final item in playlistsRaw) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final createdAt = _asInt(item['createdAt']) ??
            DateTime.now().millisecondsSinceEpoch;
        final updatedAt = _asInt(item['updatedAt']);
        final description = item['description']?.toString();
        String? coverPath;
        final coverZip = item['cover']?.toString();
        if (coverZip != null && coverZip.isNotEmpty) {
          final file = _findFile(archive, coverZip);
          final bytes = file?.readBytes();
          if (bytes != null) {
            final localName = p.basename(coverZip);
            final dest = File(p.join(_paths.playlistsDir, localName));
            await dest.writeAsBytes(bytes, flush: true);
            coverPath = dest.path;
          }
        }
        final tracks = <String>[];
        final tracksRaw = item['tracks'];
        if (tracksRaw is List) {
          for (final t in tracksRaw) {
            final key = t?.toString();
            if (key != null && key.isNotEmpty) tracks.add(key);
          }
        }
        final systemKind = item['systemKind']?.toString();
        playlistRows.add(
          PlaylistImportRow(
            name: name,
            createdAtMs: createdAt,
            updatedAtMs: updatedAt,
            description: (description == null || description.trim().isEmpty)
                ? null
                : description.trim(),
            coverPath: coverPath,
            systemKind: (systemKind == null || systemKind.isEmpty)
                ? null
                : systemKind,
            trackKeys: tracks,
          ),
        );
      }
    }

    final playEvents = <({String trackKey, int playedAt})>[];
    final eventsRaw = json['playEvents'];
    if (eventsRaw is List) {
      for (final item in eventsRaw) {
        if (item is! Map) continue;
        final key = item['trackKey']?.toString();
        final at = _asInt(item['playedAt']);
        if (key == null || key.isEmpty || at == null) continue;
        playEvents.add((trackKey: key, playedAt: at));
      }
    }

    await _db.replaceAppUserData(
      playlists: playlistRows,
      playEvents: playEvents,
    );

    final trashedEntries = <({String trackKey, int trashedAt})>[];
    final trashedRaw = json['trashedTracks'];
    if (trashedRaw is List) {
      for (final item in trashedRaw) {
        if (item is! Map) continue;
        final key = item['trackKey']?.toString();
        final at = _asInt(item['trashedAt']);
        if (key == null || key.isEmpty || at == null) continue;
        trashedEntries.add((trackKey: key, trashedAt: at));
      }
    }
    await _db.applyTrashedFlags(trashedEntries);

    final addedEntries = <({String trackKey, int addedAt})>[];
    final addedRaw = json['trackAddedAt'];
    if (addedRaw is List) {
      for (final item in addedRaw) {
        if (item is! Map) continue;
        final key = item['trackKey']?.toString();
        final at = _asInt(item['addedAt']);
        if (key == null || key.isEmpty || at == null) continue;
        addedEntries.add((trackKey: key, addedAt: at));
      }
    }
    await _db.applyAddedAtFlags(addedEntries);

    await _db.ensureTrashPlaylist();
    await _db.ensureNewPlaylist();
    await _db.syncTrashPlaylistMembership();
    await _db.syncNewPlaylistMembership();

    final settingsRaw = json['settings'];
    if (settingsRaw is Map) {
      await _settings.importSettingsFlags(
        Map<String, dynamic>.from(settingsRaw),
      );
    }

    await _settings.replaceArtistPhotoPaths(artistMap);

    final snapsRaw = json['chartSnapshots'];
    if (snapsRaw is Map) {
      final snaps = <String, List<String>>{};
      for (final e in snapsRaw.entries) {
        final list = e.value;
        if (list is List) {
          snaps[e.key.toString()] = [
            for (final line in list) line.toString(),
          ];
        }
      }
      await _settings.replaceChartSnapshots(snaps);
    } else {
      await _settings.replaceChartSnapshots(const {});
    }

    return BackupResult(
      message: 'Импортировано: ${playlistRows.length} плейлистов, '
          '${playEvents.length} прослушиваний, '
          '${artistMap.length} фото артистов.',
    );
  }

  Future<BackupResult> importFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return importFromBytes(Uint8List.fromList(bytes));
  }

  static String _safeName(String input) {
    final cleaned = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\-]+', unicode: true), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty) return 'artist';
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static ArchiveFile? _findFile(Archive archive, String name) {
    final normalized = name.replaceAll('\\', '/');
    for (final file in archive.files) {
      if (file.name.replaceAll('\\', '/') == normalized) return file;
    }
    return null;
  }

  static Future<void> _clearDirContents(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }
}
