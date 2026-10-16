import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../data/app_paths.dart';
import '../data/database.dart';
import '../data/track_key.dart';
import '../models/track.dart';

class ScanProgress {
  const ScanProgress({
    required this.processed,
    required this.total,
    required this.added,
    required this.updated,
    required this.skipped,
    this.currentFile,
  });

  final int processed;
  final int total;
  final int added;
  final int updated;
  final int skipped;
  final String? currentFile;

  double get ratio => total == 0 ? 0 : processed / total;
}

class ScanResult {
  const ScanResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.removed,
    required this.totalFiles,
    this.addedTracks = const [],
    this.cancelled = false,
  });

  final int added;
  final int updated;
  final int skipped;
  final int removed;
  final int totalFiles;

  /// Newly indexed tracks (candidates for online metadata fill).
  final List<Track> addedTracks;
  final bool cancelled;
}

class ScannerService {
  ScannerService({
    required AppPaths this._paths,
    required AppDatabase this._db,
  });

  final AppPaths _paths;
  final AppDatabase _db;

  bool _cancelRequested = false;

  void requestCancel() => _cancelRequested = true;

  Future<ScanResult> scan({
    void Function(ScanProgress progress)? onProgress,
    bool force = false,
  }) async {
    _cancelRequested = false;
    await _paths.ensureDirectories();

    final musicRoot = Directory(_paths.musicDir);
    if (!await musicRoot.exists()) {
      await musicRoot.create(recursive: true);
    }

    final files = await musicRoot
        .list(recursive: true, followLinks: false)
        .where((e) => e is File && _isAudio(e.path))
        .cast<File>()
        .toList();

    final existingMtimes = await _db.getFileMtimes();
    final artistAliases = await _db.getArtistAliasMap();
    final seenPaths = <String>{};

    var added = 0;
    var updated = 0;
    var skipped = 0;
    var processed = 0;
    final addedTracks = <Track>[];
    var cancelled = false;

    for (final file in files) {
      if (_cancelRequested) {
        cancelled = true;
        break;
      }

      final filePath = p.normalize(file.path);
      seenPaths.add(filePath);

      final stat = await file.stat();
      final mtimeMs = stat.modified.millisecondsSinceEpoch;
      final prev = existingMtimes[filePath];

      processed++;
      onProgress?.call(ScanProgress(
        processed: processed,
        total: files.length,
        added: added,
        updated: updated,
        skipped: skipped,
        currentFile: p.basename(filePath),
      ));

      if (!force && prev != null && prev == mtimeMs) {
        skipped++;
        continue;
      }

      final track = await _readTrack(file, artistAliases);
      if (track == null) {
        skipped++;
        continue;
      }

      await _db.upsertTrackFile(
        track: track,
        filePath: filePath,
        mtimeMs: mtimeMs,
      );

      if (prev == null) {
        added++;
        addedTracks.add(track);
      } else {
        updated++;
      }
    }

    // Never prune missing files if cancelled — scan was incomplete.
    var actuallyRemoved = 0;
    if (!cancelled) {
      actuallyRemoved =
          existingMtimes.keys.toSet().difference(seenPaths).length;
      await _db.removeMissingFiles(seenPaths);
    }

    return ScanResult(
      added: added,
      updated: updated,
      skipped: skipped,
      removed: actuallyRemoved,
      totalFiles: files.length,
      addedTracks: addedTracks,
      cancelled: cancelled,
    );
  }

  Future<Track?> _readTrack(
    File file,
    Map<String, String> artistAliases,
  ) async {
    try {
      final meta = readMetadata(file, getImage: true);
      final title = _pickTitle(meta, file.path);
      // "A, B" stays one tag string but splits into two artists in UI.
      // Aliases remaps renamed/merged artists without rewriting files.
      final artist = applyArtistAliases(
        formatArtists(_firstOrUnknown(meta.artist)),
        artistAliases,
      );
      final album = meta.album?.trim().isNotEmpty == true
          ? meta.album!.trim()
          : 'Unknown';
      final genre = meta.genres.isNotEmpty
          ? meta.genres.map((g) => g.trim()).where((g) => g.isNotEmpty).join(', ')
          : 'Unknown';
      final rawAlbumArtist = meta.albumArtist?.trim();
      final albumArtist = (rawAlbumArtist == null || rawAlbumArtist.isEmpty)
          ? null
          : applyArtistAliases(rawAlbumArtist, artistAliases);
      final lyrics = meta.lyrics?.trim();
      final durationMs = meta.duration?.inMilliseconds;
      final year = meta.year?.year;
      final trackNumber = meta.trackNumber;
      final discNumber = meta.discNumber;

      final trackKey = buildTrackKey(
        artist: artist,
        title: title,
      );

      String? coverPath;
      final pictures = meta.pictures;
      if (pictures.isNotEmpty) {
        coverPath = await _saveCover(trackKey, pictures.first);
      }

      return Track(
        trackKey: trackKey,
        title: title,
        artist: artist,
        album: album,
        genre: genre.isEmpty ? 'Unknown' : genre,
        albumArtist: albumArtist,
        lyrics: (lyrics == null || lyrics.isEmpty) ? null : lyrics,
        year: year,
        trackNumber: trackNumber,
        discNumber: discNumber,
        durationMs: durationMs,
        coverPath: coverPath,
        filePaths: [file.path],
      );
    } catch (_) {
      // Fallback: filename-only track so library still shows something.
      final title = p.basenameWithoutExtension(file.path);
      final trackKey = buildTrackKey(
        artist: 'Unknown',
        title: title,
      );
      return Track(
        trackKey: trackKey,
        title: title,
        artist: 'Unknown',
        album: 'Unknown',
        genre: 'Unknown',
        filePaths: [file.path],
      );
    }
  }

  Future<String?> _saveCover(String trackKey, Picture picture) async {
    try {
      final bytes = picture.bytes;
      if (bytes.isEmpty) return null;
      final ext = switch (picture.mimetype) {
        'image/png' => '.png',
        'image/webp' => '.webp',
        _ => '.jpg',
      };
      final out = File(p.join(_paths.coversDir, '$trackKey$ext'));
      if (!await out.exists()) {
        await out.writeAsBytes(bytes, flush: true);
      }
      return out.path;
    } catch (_) {
      return null;
    }
  }

  String _pickTitle(AudioMetadata meta, String filePath) {
    final t = meta.title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return p.basenameWithoutExtension(filePath);
  }

  String _firstOrUnknown(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return 'Unknown';
    return v;
  }

  bool _isAudio(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {'.mp3', '.flac', '.m4a', '.aac', '.wav', '.ogg'}
        .contains(ext);
  }
}
