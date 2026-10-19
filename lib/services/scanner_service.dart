import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/app_paths.dart';
import '../data/database.dart';
import '../data/track_key.dart';
import '../models/track.dart';
import 'metadata_writer.dart';

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
    bool newOnly = false,
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
      onProgress?.call(
        ScanProgress(
          processed: processed,
          total: files.length,
          added: added,
          updated: updated,
          skipped: skipped,
          currentFile: p.basename(filePath),
        ),
      );

      // New-only walk leaves files that are already in the library alone.
      if (!force && newOnly && prev != null) {
        skipped++;
        continue;
      }

      if (!force && prev != null && prev == mtimeMs) {
        skipped++;
        continue;
      }

      final track = await _readTrack(file);
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
    if (!cancelled && !(newOnly && !force)) {
      actuallyRemoved = existingMtimes.keys
          .toSet()
          .difference(seenPaths)
          .length;
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

  /// Previous merges rewrote the index artist to the card name.
  /// Read the file tag back so tracks show the original name again.
  Future<int> restoreOriginalArtistTags() async {
    final aliases = await _db.getArtistAliases();
    if (aliases.isEmpty) return 0;
    final targets = {for (final a in aliases) normalizeTag(a.toDisplay)};
    final tracks = await _db.getAllTracks(includeTrashed: true);
    var changed = 0;

    for (final track in tracks) {
      final names = [...track.artists, ...splitArtists(track.albumArtist)];
      if (!names.any((n) => targets.contains(normalizeTag(n)))) continue;
      final path = track.primaryPath;
      if (path == null || !File(path).existsSync()) continue;
      try {
        final meta = readMetadata(File(path), getImage: false);
        final artist = storedArtists(meta.artist);
        final albumArtist = storedPeople(meta.albumArtist);
        if (artist == track.artist && albumArtist == track.albumArtist) {
          continue;
        }
        final updated = track.copyWith(
          trackKey: buildTrackKey(
            artist: artist,
            title: track.title,
            note: track.note,
          ),
          artist: artist,
          albumArtist: albumArtist,
        );
        await _db.applyMetadataEdit(
          oldTrackKey: track.trackKey,
          updated: updated,
        );
        changed++;
      } catch (e) {
        debugPrint('restore artist tag failed for $path: $e');
      }
    }
    return changed;
  }

  Future<Track?> _readTrack(File file) async {
    try {
      final meta = readMetadata(file, getImage: true);
      final title = _pickTitle(meta, file.path);
      // Keep the tag as written. Artist merges only group the artist card.
      final artist = storedArtists(meta.artist);
      final rawAlbum = meta.album?.trim();
      final album = isBlankMeta(rawAlbum) ? 'Unknown' : rawAlbum!;
      final genreRaw = meta.genres.isNotEmpty
          ? meta.genres
                .map((g) => g.trim())
                .where((g) => !isBlankMeta(g))
                .join(', ')
          : '';
      final genre = genreRaw.isEmpty ? 'Unknown' : genreRaw;
      final albumArtist = storedPeople(meta.albumArtist);
      final producer = readFileProducer(file.path);
      final note = readFileNote(file.path);
      final lyrics = meta.lyrics?.trim();
      final durationMs = meta.duration?.inMilliseconds;
      final year = meta.year?.year;
      final trackNumber = meta.trackNumber;
      final discNumber = meta.discNumber;

      final trackKey = buildTrackKey(artist: artist, title: title, note: note);

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
        producer: producer,
        note: note,
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
      final trackKey = buildTrackKey(artist: 'Unknown', title: title);
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
    if (!isBlankMeta(t)) return t!;
    return p.basenameWithoutExtension(filePath);
  }

  bool _isAudio(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {
      '.mp3',
      '.flac',
      '.m4a',
      '.aac',
      '.wav',
      '.ogg',
    }.contains(ext);
  }
}
