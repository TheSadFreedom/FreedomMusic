import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../data/app_paths.dart';
import '../data/track_key.dart';
import '../models/track.dart';

class MetadataDraft {
  MetadataDraft({
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist,
    required this.genre,
    this.year,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.lyrics,
    this.coverBytes,
    this.coverMime,
    this.removeCover = false,
  });

  factory MetadataDraft.fromTrack(Track track) {
    return MetadataDraft(
      title: track.title,
      artist: track.artist,
      album: track.album,
      albumArtist: track.albumArtist,
      genre: track.genre,
      year: track.year,
      trackNumber: track.trackNumber,
      trackTotal: track.trackTotal,
      discNumber: track.discNumber,
      lyrics: track.lyrics,
    );
  }

  String title;
  String artist;
  String album;
  String? albumArtist;
  String genre;
  int? year;
  int? trackNumber;
  int? trackTotal;
  int? discNumber;
  String? lyrics;

  /// New cover to embed (null = keep existing unless [removeCover]).
  Uint8List? coverBytes;
  String? coverMime;
  bool removeCover;
}

class MetadataWriter {
  /// Writes tags into every file of [track] and returns the updated Track
  /// (new trackKey if identity fields changed).
  static Future<Track> write(
    Track track,
    MetadataDraft draft, {
    required AppPaths paths,
  }) async {
    final filePaths = track.filePaths;
    if (filePaths.isEmpty) {
      throw StateError('У трека нет файлов на диске');
    }

    final title = draft.title.trim().isEmpty ? 'Unknown' : draft.title.trim();
    final artist = formatArtists(draft.artist);
    final album = draft.album.trim().isEmpty ? 'Unknown' : draft.album.trim();
    final genre = draft.genre.trim().isEmpty ? 'Unknown' : draft.genre.trim();
    final albumArtist = draft.albumArtist?.trim();
    final lyrics = draft.lyrics?.trim();
    final year = draft.year;
    final trackNumber = draft.trackNumber;
    final trackTotal = draft.trackTotal;
    final discNumber = draft.discNumber;

    Picture? coverPicture;
    if (draft.coverBytes != null && draft.coverBytes!.isNotEmpty) {
      final mime = draft.coverMime ?? 'image/jpeg';
      coverPicture = Picture(
        draft.coverBytes!,
        mime,
        PictureType.coverFront,
      );
    }

    for (final path in filePaths) {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('Файл не найден', path);
      }
      await _writeFile(
        file,
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        genre: genre,
        year: year,
        trackNumber: trackNumber,
        trackTotal: trackTotal,
        discNumber: discNumber,
        lyrics: lyrics,
        cover: coverPicture,
        removeCover: draft.removeCover,
      );
    }

    final newKey = buildTrackKey(
      artist: artist,
      title: title,
    );

    String? coverPath = track.coverPath;
    if (draft.removeCover) {
      await _deleteCovers(paths, track.trackKey);
      await _deleteCovers(paths, newKey);
      coverPath = null;
    } else if (draft.coverBytes != null) {
      await _deleteCovers(paths, track.trackKey);
      await _deleteCovers(paths, newKey);
      coverPath = await _saveCoverCache(
        paths,
        newKey,
        draft.coverBytes!,
        draft.coverMime ?? 'image/jpeg',
      );
    } else if (track.trackKey != newKey && track.coverPath != null) {
      // Move cached cover to new key name.
      coverPath = await _renameCoverCache(
        paths,
        track.trackKey,
        newKey,
        track.coverPath!,
      );
    }

    return track.copyWith(
      trackKey: newKey,
      title: title,
      artist: artist,
      album: album,
      albumArtist: (albumArtist == null || albumArtist.isEmpty)
          ? null
          : albumArtist,
      genre: genre,
      year: year,
      trackNumber: trackNumber,
      trackTotal: trackTotal,
      discNumber: discNumber,
      lyrics: (lyrics == null || lyrics.isEmpty) ? null : lyrics,
      coverPath: coverPath,
    );
  }

  static Future<void> _writeFile(
    File file, {
    required String title,
    required String artist,
    required String album,
    required String? albumArtist,
    required String genre,
    required int? year,
    required int? trackNumber,
    required int? trackTotal,
    required int? discNumber,
    required String? lyrics,
    required Picture? cover,
    required bool removeCover,
  }) async {
    // Writer loads the whole audio file into RAM (package limitation).
    // Run in a short-lived isolate so that buffer is released after each file.
    final path = file.path;
    final coverBytes = cover?.bytes;
    final coverMime = cover?.mimetype;
    await Isolate.run(() {
      updateMetadata(File(path), (tag) {
        tag.setTitle(title);
        tag.setArtist(artist);
        tag.setAlbum(album);
        tag.setGenres(genre == 'Unknown' ? <String>[] : [genre]);
        tag.setYear(year != null ? DateTime(year) : null);
        tag.setTrackNumber(trackNumber);
        tag.setTrackTotal(trackTotal);
        tag.setCD(discNumber, null);
        tag.setLyrics(lyrics);

        if (tag is Mp3Metadata) {
          tag.bandOrOrchestra = albumArtist;
        }

        if (removeCover) {
          tag.setPictures([]);
        } else if (coverBytes != null && coverBytes.isNotEmpty) {
          tag.setPictures([
            Picture(
              coverBytes,
              coverMime ?? 'image/jpeg',
              PictureType.coverFront,
            ),
          ]);
        }
      });
    });
  }

  static Future<String> _saveCoverCache(
    AppPaths paths,
    String trackKey,
    Uint8List bytes,
    String mime,
  ) async {
    await paths.ensureDirectories();
    final ext = mime.contains('png')
        ? '.png'
        : mime.contains('webp')
            ? '.webp'
            : '.jpg';
    final out = File(p.join(paths.coversDir, '$trackKey$ext'));
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }

  static Future<void> deleteCovers(AppPaths paths, String trackKey) =>
      _deleteCovers(paths, trackKey);

  static Future<void> _deleteCovers(AppPaths paths, String trackKey) async {
    for (final ext in ['.jpg', '.jpeg', '.png', '.webp']) {
      final f = File(p.join(paths.coversDir, '$trackKey$ext'));
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  static Future<String?> _renameCoverCache(
    AppPaths paths,
    String oldKey,
    String newKey,
    String oldPath,
  ) async {
    final oldFile = File(oldPath);
    if (!await oldFile.exists()) return null;
    final ext = p.extension(oldPath);
    final newPath = p.join(paths.coversDir, '$newKey$ext');
    if (p.equals(oldPath, newPath)) return oldPath;
    await oldFile.copy(newPath);
    try {
      await oldFile.delete();
    } catch (_) {}
    return newPath;
  }
}
