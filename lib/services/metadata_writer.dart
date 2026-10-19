import 'dart:convert';
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
    this.producer,
    this.note,
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
      producer: track.producer,
      note: track.note,
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
  String? producer;
  String? note;
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

    final title = isBlankMeta(draft.title) ? 'Unknown' : draft.title.trim();
    final artist = storedArtists(draft.artist);
    final album = isBlankMeta(draft.album) ? 'Unknown' : draft.album.trim();
    final genre = isBlankMeta(draft.genre) ? 'Unknown' : draft.genre.trim();
    final albumArtist = storedPeople(draft.albumArtist);
    final producerNamesOnly = producerNames(draft.producer);
    final producer = producerNamesOnly.isEmpty
        ? null
        : producerNamesOnly.join(', ');
    final noteText = draft.note?.trim() ?? '';
    final note = isBlankMeta(noteText) ? null : noteText;
    final lyrics = draft.lyrics?.trim();
    final year = draft.year;
    final trackNumber = draft.trackNumber;
    final trackTotal = draft.trackTotal;
    final discNumber = draft.discNumber;

    Picture? coverPicture;
    if (draft.coverBytes != null && draft.coverBytes!.isNotEmpty) {
      final mime = draft.coverMime ?? 'image/jpeg';
      coverPicture = Picture(draft.coverBytes!, mime, PictureType.coverFront);
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
        producer: (producer == null || producer.isEmpty) ? null : producer,
        note: note,
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

    final newKey = buildTrackKey(artist: artist, title: title, note: note);

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
      producer: (producer == null || producer.isEmpty) ? null : producer,
      note: note,
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
    required String? producer,
    required String? note,
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
        final keptPictures = _picturesOf(tag);
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
        } else if (tag is VorbisMetadata) {
          tag.producer = (producer == null || producer.isEmpty)
              ? []
              : [producer];
          final label = note?.trim() ?? '';
          if (label.isEmpty) {
            tag.unknowns.remove('NOTE');
          } else {
            tag.unknowns['NOTE'] = label;
          }
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
        } else {
          // Metadata fill only writes text fields. Put the original pictures
          // back so the rewrite cannot replace or drop the cover.
          tag.setPictures(keptPictures);
        }
      });
      // The ID3 writer drops TXXX frames, so producer and note are appended after.
      writeMp3SideFrames(path, producer: producer, note: note);
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

List<Picture> _picturesOf(Object tag) {
  return switch (tag) {
    Mp3Metadata meta => List<Picture>.from(meta.pictures),
    VorbisMetadata meta => List<Picture>.from(meta.pictures),
    RiffMetadata meta => List<Picture>.from(meta.pictures),
    ApeMetadata meta => List<Picture>.from(meta.pictures),
    Mp4Metadata meta => meta.picture == null ? <Picture>[] : [meta.picture!],
    _ => const <Picture>[],
  };
}

/// Note stored as an ID3 `TXXX:NOTE` frame or a Vorbis `NOTE` tag.
String? readFileNote(String path) {
  try {
    final tag = readAllMetadata(File(path), getImage: false);
    return switch (tag) {
      Mp3Metadata meta => _customText(meta, 'note'),
      VorbisMetadata meta => _vorbisNote(meta),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

String? _vorbisNote(VorbisMetadata meta) {
  for (final entry in meta.unknowns.entries) {
    if (entry.key.trim().toLowerCase() != 'note') continue;
    final value = entry.value.replaceAll('\u0000', '').trim();
    if (!isBlankMeta(value)) return value;
  }
  return null;
}

String? _customText(Mp3Metadata meta, String key) {
  for (final entry in meta.customMetadata.entries) {
    if (entry.key.trim().toLowerCase() != key) continue;
    final value = entry.value.replaceAll('\u0000', '').trim();
    if (!isBlankMeta(value)) return value;
  }
  return null;
}

/// Producer stored as an ID3 `TXXX:PRODUCER` frame or a Vorbis `PRODUCER` tag.
String? readFileProducer(String path) {
  try {
    final tag = readAllMetadata(File(path), getImage: false);
    return switch (tag) {
      Mp3Metadata meta => _producerFromMp3(meta),
      VorbisMetadata meta => _firstNonEmpty(meta.producer),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

String? _producerFromMp3(Mp3Metadata meta) {
  final direct = _customText(meta, 'producer');
  if (direct != null) return direct;
  for (final entry in meta.customMetadata.entries) {
    final key = entry.key.trim().toLowerCase();
    if (key == 'tipl' || key == 'ipls') {
      final fromList = _producerFromInvolved(entry.value);
      if (fromList != null) return fromList;
    }
  }
  return null;
}

String? _producerFromInvolved(String raw) {
  final parts = raw.split(RegExp(r'[\u0000/]'));
  for (var i = 0; i + 1 < parts.length; i++) {
    if (parts[i].trim().toLowerCase() != 'producer') continue;
    final name = parts[i + 1].trim();
    if (!isBlankMeta(name)) return name;
  }
  return null;
}

String? _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.replaceAll('\u0000', '').trim();
    if (!isBlankMeta(trimmed)) return trimmed;
  }
  return null;
}

/// Rewrites `TXXX:PRODUCER` and `TXXX:NOTE` on an ID3v2.4 tag.
void writeMp3SideFrames(String path, {String? producer, String? note}) {
  final file = File(path);
  final bytes = file.readAsBytesSync();
  if (bytes.length < 10 ||
      bytes[0] != 0x49 ||
      bytes[1] != 0x44 ||
      bytes[2] != 0x33 ||
      bytes[3] != 4) {
    return;
  }
  final payloadSize = _readSyncSafe(bytes, 6);
  final tagEnd = 10 + payloadSize;
  if (tagEnd <= 10 || tagEnd > bytes.length) return;

  final kept = BytesBuilder(copy: false);
  var offset = 10;
  if ((bytes[5] & 0x40) == 0) {
    while (offset + 10 <= tagEnd) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      if (id.codeUnitAt(0) == 0) break;
      final size = _readSyncSafe(bytes, offset + 4);
      final frameEnd = offset + 10 + size;
      if (size < 0 || frameEnd > tagEnd) {
        kept.add(bytes.sublist(offset, tagEnd));
        offset = tagEnd;
        break;
      }
      final description = id == 'TXXX'
          ? _txxxDescription(bytes, offset + 10, size)?.toLowerCase()
          : null;
      final drop = description == 'producer' || description == 'note';
      if (!drop) kept.add(bytes.sublist(offset, frameEnd));
      offset = frameEnd;
    }
  } else {
    kept.add(bytes.sublist(10, tagEnd));
  }

  final frames = BytesBuilder(copy: false)..add(kept.toBytes());
  final producerValue = producer?.trim() ?? '';
  if (!isBlankMeta(producerValue)) {
    frames.add(_txxxFrame('PRODUCER', producerValue));
  }
  final noteValue = note?.trim() ?? '';
  if (!isBlankMeta(noteValue)) {
    frames.add(_txxxFrame('NOTE', noteValue));
  }
  final body = frames.toBytes();
  final header = Uint8List.fromList(bytes.sublist(0, 10));
  _writeSyncSafe(header, 6, body.length);
  final out = BytesBuilder(copy: false)
    ..add(header)
    ..add(body)
    ..add(bytes.sublist(tagEnd));
  file.writeAsBytesSync(out.takeBytes());
}

String? _txxxDescription(Uint8List data, int start, int size) {
  if (size < 2 || start + size > data.length) return null;
  final encoding = data[start];
  final payload = data.sublist(start + 1, start + size);
  if (encoding == 1 || encoding == 2) {
    for (var i = 0; i + 1 < payload.length; i += 2) {
      if (payload[i] == 0 && payload[i + 1] == 0) {
        return String.fromCharCodes(payload.sublist(0, i)).toLowerCase();
      }
    }
    return null;
  }
  final zero = payload.indexOf(0);
  final bytes = zero < 0 ? payload : payload.sublist(0, zero);
  return utf8.decode(bytes, allowMalformed: true);
}

int _readSyncSafe(Uint8List data, int offset) {
  return ((data[offset] & 0x7F) << 21) |
      ((data[offset + 1] & 0x7F) << 14) |
      ((data[offset + 2] & 0x7F) << 7) |
      (data[offset + 3] & 0x7F);
}

void _writeSyncSafe(Uint8List data, int offset, int value) {
  data[offset] = (value >> 21) & 0x7F;
  data[offset + 1] = (value >> 14) & 0x7F;
  data[offset + 2] = (value >> 7) & 0x7F;
  data[offset + 3] = value & 0x7F;
}

Uint8List _syncSafe(int value) {
  return Uint8List.fromList([
    (value >> 21) & 0x7F,
    (value >> 14) & 0x7F,
    (value >> 7) & 0x7F,
    value & 0x7F,
  ]);
}

Uint8List _txxxFrame(String description, String value) {
  final payload = BytesBuilder(copy: false)
    ..addByte(3)
    ..add(utf8.encode(description))
    ..addByte(0)
    ..add(utf8.encode(value));
  final data = payload.takeBytes();
  return (BytesBuilder(copy: false)
        ..add(utf8.encode('TXXX'))
        ..add(_syncSafe(data.length))
        ..addByte(0)
        ..addByte(0)
        ..add(data))
      .takeBytes();
}
