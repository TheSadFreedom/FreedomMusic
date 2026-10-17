import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'app_paths.dart';
import 'track_key.dart';

class AppDatabase {
  AppDatabase(this._db);

  final Database _db;

  static Future<AppDatabase> open(AppPaths paths) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await databaseFactory.openDatabase(
      paths.databasePath,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tracks (
              track_key TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT NOT NULL,
              genre TEXT NOT NULL,
              album_artist TEXT,
              producer TEXT,
              lyrics TEXT,
              year INTEGER,
              track_number INTEGER,
              track_total INTEGER,
              disc_number INTEGER,
              duration_ms INTEGER,
              cover_path TEXT,
              trashed_at INTEGER,
              added_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE track_files (
              file_path TEXT PRIMARY KEY,
              track_key TEXT NOT NULL,
              mtime_ms INTEGER NOT NULL,
              FOREIGN KEY (track_key) REFERENCES tracks(track_key)
            )
          ''');
          await db.execute('''
            CREATE INDEX idx_track_files_key ON track_files(track_key)
          ''');
          await db.execute('''
            CREATE TABLE play_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_key TEXT NOT NULL,
              played_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE INDEX idx_play_events_key_at
            ON play_events(track_key, played_at)
          ''');
          await db.execute('''
            CREATE TABLE track_listen_ms (
              track_key TEXT PRIMARY KEY,
              ms INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE artist_aliases (
              from_norm TEXT PRIMARY KEY,
              from_display TEXT NOT NULL,
              to_display TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE playlists (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER,
              description TEXT,
              cover_path TEXT,
              system_kind TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE playlist_tracks (
              playlist_id INTEGER NOT NULL,
              track_key TEXT NOT NULL,
              position INTEGER NOT NULL,
              PRIMARY KEY (playlist_id, track_key),
              FOREIGN KEY (playlist_id) REFERENCES playlists(id)
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE tracks ADD COLUMN album_artist TEXT',
            );
            await db.execute('ALTER TABLE tracks ADD COLUMN lyrics TEXT');
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE playlists ADD COLUMN updated_at INTEGER',
            );
            await db.execute(
              'ALTER TABLE playlists ADD COLUMN description TEXT',
            );
            await db.execute(
              'ALTER TABLE playlists ADD COLUMN cover_path TEXT',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE tracks ADD COLUMN track_number INTEGER',
            );
            await db.execute(
              'ALTER TABLE tracks ADD COLUMN track_total INTEGER',
            );
            await db.execute(
              'ALTER TABLE tracks ADD COLUMN disc_number INTEGER',
            );
          }
          if (oldVersion < 5) {
            await db.execute(
              'ALTER TABLE tracks ADD COLUMN trashed_at INTEGER',
            );
            await db.execute(
              'ALTER TABLE playlists ADD COLUMN system_kind TEXT',
            );
          }
          if (oldVersion < 6) {
            await db.execute(
              'ALTER TABLE tracks ADD COLUMN added_at INTEGER',
            );
          }
          if (oldVersion < 7) {
            await db.execute('''
              CREATE TABLE track_listen_ms (
                track_key TEXT PRIMARY KEY,
                ms INTEGER NOT NULL DEFAULT 0
              )
            ''');
            // Seed from play events: each counted play ≈ full track length.
            await db.execute('''
              INSERT INTO track_listen_ms (track_key, ms)
              SELECT pe.track_key,
                     COUNT(*) * CASE
                       WHEN MAX(t.duration_ms) IS NULL OR MAX(t.duration_ms) <= 0
                       THEN 180000
                       ELSE MAX(t.duration_ms)
                     END
              FROM play_events pe
              LEFT JOIN tracks t ON t.track_key = pe.track_key
              GROUP BY pe.track_key
            ''');
          }
          if (oldVersion < 8) {
            await db.execute('''
              CREATE TABLE artist_aliases (
                from_norm TEXT PRIMARY KEY,
                from_display TEXT NOT NULL,
                to_display TEXT NOT NULL
              )
            ''');
          }
          if (oldVersion < 9) {
            await db.execute('ALTER TABLE tracks ADD COLUMN producer TEXT');
          }
        },
      ),
    );

    return AppDatabase(db);
  }

  /// Recompute keys as artist+title only. Merges collisions; keeps plays/playlists.
  /// Idempotent. Returns how many rows had their key changed (including merges).
  Future<int> remigrateTrackKeysToArtistTitle() async {
    final rows = await _db.query('tracks');
    var changed = 0;
    for (final row in rows) {
      final oldKey = row['track_key'] as String;
      final still = await _db.query(
        'tracks',
        columns: ['track_key'],
        where: 'track_key = ?',
        whereArgs: [oldKey],
        limit: 1,
      );
      if (still.isEmpty) continue;

      final newKey = buildTrackKey(
        artist: row['artist'] as String? ?? 'Unknown',
        title: row['title'] as String? ?? 'Unknown',
      );
      if (oldKey == newKey) continue;
      changed++;
      await _mergeTrackIntoKey(oldKey: oldKey, newKey: newKey, sourceRow: row);
    }
    return changed;
  }

  Future<void> _mergeTrackIntoKey({
    required String oldKey,
    required String newKey,
    required Map<String, Object?> sourceRow,
  }) async {
    await _db.transaction((txn) async {
      final dest = await txn.query(
        'tracks',
        where: 'track_key = ?',
        whereArgs: [newKey],
        limit: 1,
      );

      if (dest.isEmpty) {
        final inserted = Map<String, Object?>.from(sourceRow)..['track_key'] = newKey;
        await txn.insert('tracks', inserted);
      } else {
        final destRow = dest.first;
        final destTrashed = destRow['trashed_at'] as int?;
        final srcTrashed = sourceRow['trashed_at'] as int?;
        final mergedTrashed =
            (destTrashed == null || srcTrashed == null)
                ? null
                : (destTrashed <= srcTrashed ? destTrashed : srcTrashed);
        final destAdded = destRow['added_at'] as int?;
        final srcAdded = sourceRow['added_at'] as int?;
        final int? mergedAdded;
        if (destAdded == null) {
          mergedAdded = srcAdded;
        } else if (srcAdded == null) {
          mergedAdded = destAdded;
        } else {
          mergedAdded = destAdded <= srcAdded ? destAdded : srcAdded;
        }
        await txn.update(
          'tracks',
          {
            'trashed_at': mergedTrashed,
            'added_at': mergedAdded,
          },
          where: 'track_key = ?',
          whereArgs: [newKey],
        );
      }

      await txn.rawUpdate(
        'UPDATE track_files SET track_key = ? WHERE track_key = ?',
        [newKey, oldKey],
      );
      await txn.rawUpdate(
        'UPDATE play_events SET track_key = ? WHERE track_key = ?',
        [newKey, oldKey],
      );
      await txn.rawInsert(
        '''
        INSERT INTO track_listen_ms (track_key, ms)
        SELECT ?, COALESCE(SUM(ms), 0)
        FROM track_listen_ms
        WHERE track_key IN (?, ?)
        ON CONFLICT(track_key) DO UPDATE SET ms = excluded.ms
        ''',
        [newKey, oldKey, newKey],
      );
      await txn.delete(
        'track_listen_ms',
        where: 'track_key = ?',
        whereArgs: [oldKey],
      );
      await txn.rawDelete(
        '''
        DELETE FROM playlist_tracks
        WHERE track_key = ?
          AND playlist_id IN (
            SELECT playlist_id FROM playlist_tracks WHERE track_key = ?
          )
        ''',
        [oldKey, newKey],
      );
      await txn.rawUpdate(
        'UPDATE playlist_tracks SET track_key = ? WHERE track_key = ?',
        [newKey, oldKey],
      );
      await txn.delete(
        'tracks',
        where: 'track_key = ?',
        whereArgs: [oldKey],
      );
    });
  }

  /// Visible library tracks (not in trash). Pass [includeTrashed] for all.
  Future<List<Track>> getAllTracks({bool includeTrashed = false}) async {
    final rows = await _db.rawQuery('''
      SELECT t.*, GROUP_CONCAT(f.file_path, '||') AS paths
      FROM tracks t
      INNER JOIN track_files f ON f.track_key = t.track_key
      WHERE (? = 1 OR t.trashed_at IS NULL)
      GROUP BY t.track_key
      ORDER BY t.artist COLLATE NOCASE, t.title COLLATE NOCASE
    ''', [includeTrashed ? 1 : 0]);
    return rows.map(_trackFromRow).toList();
  }

  Future<List<Track>> getTrashedTracks() async {
    final rows = await _db.rawQuery('''
      SELECT t.*, GROUP_CONCAT(f.file_path, '||') AS paths
      FROM tracks t
      INNER JOIN track_files f ON f.track_key = t.track_key
      WHERE t.trashed_at IS NOT NULL
      GROUP BY t.track_key
      ORDER BY t.trashed_at DESC
    ''');
    return rows.map(_trackFromRow).toList();
  }

  Future<List<({String trackKey, int trashedAt})>> getTrashedTrackEntries() async {
    final rows = await _db.query(
      'tracks',
      columns: ['track_key', 'trashed_at'],
      where: 'trashed_at IS NOT NULL',
    );
    return [
      for (final row in rows)
        (
          trackKey: row['track_key'] as String,
          trashedAt: row['trashed_at'] as int,
        ),
    ];
  }

  Future<void> applyTrashedFlags(
    List<({String trackKey, int trashedAt})> entries,
  ) async {
    await _db.transaction((txn) async {
      await txn.rawUpdate('UPDATE tracks SET trashed_at = NULL');
      for (final e in entries) {
        await txn.update(
          'tracks',
          {'trashed_at': e.trashedAt},
          where: 'track_key = ?',
          whereArgs: [e.trackKey],
        );
      }
    });
  }

  Future<Track?> getTrack(String trackKey) async {
    final rows = await _db.rawQuery('''
      SELECT t.*, GROUP_CONCAT(f.file_path, '||') AS paths
      FROM tracks t
      INNER JOIN track_files f ON f.track_key = t.track_key
      WHERE t.track_key = ?
      GROUP BY t.track_key
    ''', [trackKey]);
    if (rows.isEmpty) return null;
    return _trackFromRow(rows.first);
  }

  Future<Map<String, int>> getFileMtimes() async {
    final rows = await _db.query('track_files', columns: ['file_path', 'mtime_ms']);
    return {
      for (final row in rows)
        row['file_path'] as String: row['mtime_ms'] as int,
    };
  }

  Future<Set<String>> getIndexedPaths() async {
    final rows = await _db.query('track_files', columns: ['file_path']);
    return rows.map((r) => r['file_path'] as String).toSet();
  }

  /// Persist lyrics found online without rewriting audio tags.
  Future<void> updateTrackLyrics(String trackKey, String lyrics) async {
    final text = lyrics.trim();
    if (text.isEmpty) return;
    await _db.update(
      'tracks',
      {'lyrics': text},
      where: 'track_key = ?',
      whereArgs: [trackKey],
    );
  }

  /// Upsert logical track + link file. Never duplicates track_key.
  /// Preserves [trashed_at] / [added_at]; sets [added_at] for brand-new tracks.
  /// Keeps existing lyrics when the file tag has none (e.g. LRCLIB fill).
  Future<void> upsertTrackFile({
    required Track track,
    required String filePath,
    required int mtimeMs,
  }) async {
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'tracks',
        columns: ['trashed_at', 'added_at', 'lyrics'],
        where: 'track_key = ?',
        whereArgs: [track.trackKey],
        limit: 1,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final trashedAt = existing.isEmpty
          ? track.trashedAt?.millisecondsSinceEpoch
          : existing.first['trashed_at'] as int?;
      final addedAt = existing.isEmpty
          ? (track.addedAt?.millisecondsSinceEpoch ?? now)
          : (existing.first['added_at'] as int? ??
              track.addedAt?.millisecondsSinceEpoch);
      final incomingLyrics = track.lyrics?.trim();
      final existingLyrics = existing.isEmpty
          ? null
          : (existing.first['lyrics'] as String?)?.trim();
      final lyrics = (incomingLyrics != null && incomingLyrics.isNotEmpty)
          ? incomingLyrics
          : (existingLyrics != null && existingLyrics.isNotEmpty
              ? existingLyrics
              : null);

      await txn.insert(
        'tracks',
        {
          'track_key': track.trackKey,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'genre': track.genre,
          'album_artist': track.albumArtist,
          'producer': track.producer,
          'lyrics': lyrics,
          'year': track.year,
          'track_number': track.trackNumber,
          'track_total': track.trackTotal,
          'disc_number': track.discNumber,
          'duration_ms': track.durationMs,
          'cover_path': track.coverPath,
          'trashed_at': trashedAt,
          'added_at': addedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // If this path was linked to another key, move it.
      await txn.insert(
        'track_files',
        {
          'file_path': filePath,
          'track_key': track.trackKey,
          'mtime_ms': mtimeMs,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// After editing tags: rebind files, migrate stats/playlists if key changed.
  Future<void> applyMetadataEdit({
    required String oldTrackKey,
    required Track updated,
  }) async {
    final newKey = updated.trackKey;
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'tracks',
        columns: ['trashed_at', 'added_at'],
        where: 'track_key = ?',
        whereArgs: [oldTrackKey],
        limit: 1,
      );
      final trashedAt = existing.isEmpty
          ? updated.trashedAt?.millisecondsSinceEpoch
          : existing.first['trashed_at'] as int?;
      final addedAt = existing.isEmpty
          ? updated.addedAt?.millisecondsSinceEpoch
          : (existing.first['added_at'] as int? ??
              updated.addedAt?.millisecondsSinceEpoch);

      await txn.insert(
        'tracks',
        {
          'track_key': newKey,
          'title': updated.title,
          'artist': updated.artist,
          'album': updated.album,
          'genre': updated.genre,
          'album_artist': updated.albumArtist,
          'producer': updated.producer,
          'lyrics': updated.lyrics,
          'year': updated.year,
          'track_number': updated.trackNumber,
          'track_total': updated.trackTotal,
          'disc_number': updated.discNumber,
          'duration_ms': updated.durationMs,
          'cover_path': updated.coverPath,
          'trashed_at': trashedAt,
          'added_at': addedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final path in updated.filePaths) {
        final file = await File(path).stat();
        await txn.insert(
          'track_files',
          {
            'file_path': path,
            'track_key': newKey,
            'mtime_ms': file.modified.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (oldTrackKey != newKey) {
        await txn.rawUpdate(
          'UPDATE play_events SET track_key = ? WHERE track_key = ?',
          [newKey, oldTrackKey],
        );
        await txn.rawInsert(
          '''
          INSERT INTO track_listen_ms (track_key, ms)
          SELECT ?, COALESCE(SUM(ms), 0)
          FROM track_listen_ms
          WHERE track_key IN (?, ?)
          ON CONFLICT(track_key) DO UPDATE SET ms = excluded.ms
          ''',
          [newKey, oldTrackKey, newKey],
        );
        await txn.delete(
          'track_listen_ms',
          where: 'track_key = ?',
          whereArgs: [oldTrackKey],
        );

        // Avoid PK conflicts when both keys exist in a playlist.
        await txn.rawDelete(
          '''
          DELETE FROM playlist_tracks
          WHERE track_key = ?
            AND playlist_id IN (
              SELECT playlist_id FROM playlist_tracks WHERE track_key = ?
            )
          ''',
          [oldTrackKey, newKey],
        );
        await txn.rawUpdate(
          'UPDATE playlist_tracks SET track_key = ? WHERE track_key = ?',
          [newKey, oldTrackKey],
        );

        await txn.delete(
          'track_files',
          where: 'track_key = ?',
          whereArgs: [oldTrackKey],
        );
        await txn.delete(
          'tracks',
          where: 'track_key = ?',
          whereArgs: [oldTrackKey],
        );
      }
    });
  }

  /// normalizeTag(from) → display name of canonical artist card.
  Future<Map<String, String>> getArtistAliasMap() async {
    final rows = await getArtistAliases();
    return {
      for (final row in rows) row.fromNorm: row.toDisplay,
    };
  }

  Future<List<ArtistAlias>> getArtistAliases() async {
    final rows = await _db.query('artist_aliases');
    return [
      for (final row in rows)
        ArtistAlias(
          fromNorm: row['from_norm'] as String,
          fromDisplay: row['from_display'] as String,
          toDisplay: row['to_display'] as String,
        ),
    ];
  }

  Future<void> upsertArtistAlias({
    required String fromDisplay,
    required String toDisplay,
  }) async {
    final fromNorm = normalizeTag(fromDisplay);
    final toNorm = normalizeTag(toDisplay);
    if (fromNorm.isEmpty || toNorm.isEmpty || fromNorm == toNorm) return;

    await _db.transaction((txn) async {
      // Follow chain if target is itself an alias.
      final existingTo = await txn.query(
        'artist_aliases',
        where: 'from_norm = ?',
        whereArgs: [toNorm],
        limit: 1,
      );
      var finalTo = toDisplay.trim();
      if (existingTo.isNotEmpty) {
        finalTo = (existingTo.first['to_display'] as String).trim();
      }

      // Retarget aliases that pointed at the absorbed name.
      final all = await txn.query('artist_aliases');
      for (final row in all) {
        final rowFrom = row['from_norm'] as String;
        final rowTo = row['to_display'] as String;
        if (normalizeTag(rowTo) == fromNorm) {
          await txn.update(
            'artist_aliases',
            {'to_display': finalTo},
            where: 'from_norm = ?',
            whereArgs: [rowFrom],
          );
        }
      }

      await txn.insert(
        'artist_aliases',
        {
          'from_norm': fromNorm,
          'from_display': fromDisplay.trim(),
          'to_display': finalTo,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Rewrite artist strings in the index (MP3 tags untouched).
  Future<int> rewriteArtistName({
    required String fromDisplay,
    required String toDisplay,
  }) async {
    final aliases = await getArtistAliasMap();
    final fromNorm = normalizeTag(fromDisplay);
    final tracks = await getAllTracks(includeTrashed: true);
    var changed = 0;

    for (final track in tracks) {
      final touches = track.artists
          .any((a) => normalizeTag(a) == fromNorm);
      final albumTouches = track.albumArtist != null &&
          splitArtists(track.albumArtist)
              .any((a) => normalizeTag(a) == fromNorm);
      if (!touches && !albumTouches) continue;

      final newArtist = applyArtistAliases(track.artist, aliases);
      final newAlbumArtist = track.albumArtist == null
          ? null
          : applyArtistAliases(track.albumArtist!, aliases);
      if (newArtist == track.artist && newAlbumArtist == track.albumArtist) {
        continue;
      }

      final newKey = buildTrackKey(artist: newArtist, title: track.title);
      final updated = track.copyWith(
        trackKey: newKey,
        artist: newArtist,
        albumArtist: newAlbumArtist,
      );
      await applyMetadataEdit(oldTrackKey: track.trackKey, updated: updated);
      changed++;
    }
    return changed;
  }

  Future<void> removeMissingFiles(Set<String> existingPaths) async {
    final indexed = await getIndexedPaths();
    final missing = indexed.difference(existingPaths);
    if (missing.isEmpty) return;

    await _db.transaction((txn) async {
      for (final path in missing) {
        await txn.delete(
          'track_files',
          where: 'file_path = ?',
          whereArgs: [path],
        );
      }
      // Drop logical tracks that no longer have any file.
      await txn.execute('''
        DELETE FROM tracks
        WHERE track_key NOT IN (SELECT DISTINCT track_key FROM track_files)
      ''');
    });
  }

  Future<void> recordPlay(String trackKey, {DateTime? at}) async {
    await _db.insert('play_events', {
      'track_key': trackKey,
      'played_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }

  Future<void> addListenMs(String trackKey, int ms) async {
    if (ms <= 0) return;
    await _db.rawInsert(
      '''
      INSERT INTO track_listen_ms (track_key, ms) VALUES (?, ?)
      ON CONFLICT(track_key) DO UPDATE SET ms = ms + excluded.ms
      ''',
      [trackKey, ms],
    );
  }

  Future<void> clearPlayEvents() async {
    await _db.delete('play_events');
    await _db.delete('track_listen_ms');
  }

  /// All-time play counts keyed by track_key.
  Future<Map<String, int>> getPlayCountsAllTime() async {
    final rows = await _db.rawQuery('''
      SELECT track_key, COUNT(*) AS cnt
      FROM play_events
      GROUP BY track_key
    ''');
    return {
      for (final row in rows)
        row['track_key'] as String: row['cnt'] as int,
    };
  }

  /// Accumulated listening time (ms) keyed by track_key.
  Future<Map<String, int>> getListenMsAllTime() async {
    final rows = await _db.query('track_listen_ms');
    return {
      for (final row in rows)
        row['track_key'] as String: row['ms'] as int? ?? 0,
    };
  }

  Future<List<ChartEntry>> getChart({
    required List<Track> library,
    required ChartPeriod period,
  }) async {
    final since = period.sinceMs;
    final rows = await _db.rawQuery('''
      SELECT track_key, COUNT(*) AS cnt
      FROM play_events
      WHERE (? IS NULL OR played_at >= ?)
      GROUP BY track_key
    ''', [since, since]);

    final counts = <String, int>{
      for (final row in rows)
        row['track_key'] as String: row['cnt'] as int,
    };

    // Full library chart: include tracks with 0 plays.
    final result = library
        .map(
          (track) => ChartEntry(
            track: track,
            playCount: counts[track.trackKey] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byPlays = b.playCount.compareTo(a.playCount);
        if (byPlays != 0) return byPlays;
        final byTitle = a.track.displayTitle
            .toLowerCase()
            .compareTo(b.track.displayTitle.toLowerCase());
        if (byTitle != 0) return byTitle;
        return a.track.displayArtist
            .toLowerCase()
            .compareTo(b.track.displayArtist.toLowerCase());
      });
    return result;
  }

  Future<List<Playlist>> getPlaylists() async {
    final rows = await _db.rawQuery('''
      SELECT p.*, COUNT(pt.track_key) AS track_count
      FROM playlists p
      LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
      GROUP BY p.id
      ORDER BY
        CASE p.system_kind
          WHEN '${Playlist.kindNew}' THEN 0
          WHEN '${Playlist.kindIncomplete}' THEN 1
          WHEN '${Playlist.kindTrash}' THEN 2
          ELSE 3
        END,
        p.created_at DESC
    ''');
    return rows.map(_playlistFromRow).toList();
  }

  static int get _newTracksSinceMs => DateTime.now()
      .subtract(const Duration(days: Playlist.newTrackDays))
      .millisecondsSinceEpoch;

  /// Creates the Корзина system playlist if missing. Returns its id.
  Future<int> ensureTrashPlaylist() async {
    final existing = await _db.query(
      'playlists',
      columns: ['id'],
      where: 'system_kind = ?',
      whereArgs: [Playlist.kindTrash],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.insert('playlists', {
      'name': 'Корзина',
      'created_at': now,
      'updated_at': now,
      'description':
          'Удалённые треки. Восстановите или удалите файл навсегда.',
      'system_kind': Playlist.kindTrash,
    });
  }

  /// Creates the «Без метаданных» system playlist if missing. Returns its id.
  Future<int> ensureIncompletePlaylist() async {
    final existing = await _db.query(
      'playlists',
      columns: ['id'],
      where: 'system_kind = ?',
      whereArgs: [Playlist.kindIncomplete],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.insert('playlists', {
      'name': 'Без метаданных',
      'created_at': now,
      'updated_at': now,
      'description':
          'Треки, у которых не заполнены альбом, артист альбома, год, номер или продюсер.',
      'system_kind': Playlist.kindIncomplete,
    });
  }

  /// Creates the Новинки system playlist if missing. Returns its id.
  Future<int> ensureNewPlaylist() async {
    final existing = await _db.query(
      'playlists',
      columns: ['id'],
      where: 'system_kind = ?',
      whereArgs: [Playlist.kindNew],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.insert('playlists', {
      'name': 'Новинки',
      'created_at': now,
      'updated_at': now,
      'description':
          'Треки, добавленные за последние ${Playlist.newTrackDays} дней.',
      'system_kind': Playlist.kindNew,
    });
  }

  Future<List<Track>> getNewTracks() async {
    final since = _newTracksSinceMs;
    final rows = await _db.rawQuery('''
      SELECT t.*, GROUP_CONCAT(f.file_path, '||') AS paths
      FROM tracks t
      INNER JOIN track_files f ON f.track_key = t.track_key
      WHERE t.trashed_at IS NULL
        AND t.added_at IS NOT NULL
        AND t.added_at >= ?
      GROUP BY t.track_key
      ORDER BY t.added_at DESC
    ''', [since]);
    return rows.map(_trackFromRow).toList();
  }

  Future<List<({String trackKey, int addedAt})>> getTrackAddedAtEntries() async {
    final rows = await _db.query(
      'tracks',
      columns: ['track_key', 'added_at'],
      where: 'added_at IS NOT NULL',
    );
    return [
      for (final row in rows)
        (
          trackKey: row['track_key'] as String,
          addedAt: row['added_at'] as int,
        ),
    ];
  }

  Future<void> applyAddedAtFlags(
    List<({String trackKey, int addedAt})> entries,
  ) async {
    await _db.transaction((txn) async {
      for (final e in entries) {
        await txn.update(
          'tracks',
          {'added_at': e.addedAt},
          where: 'track_key = ?',
          whereArgs: [e.trackKey],
        );
      }
    });
  }

  Future<Playlist?> getPlaylist(int id) async {
    final rows = await _db.rawQuery('''
      SELECT p.*, COUNT(pt.track_key) AS track_count
      FROM playlists p
      LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
      WHERE p.id = ?
      GROUP BY p.id
    ''', [id]);
    if (rows.isEmpty) return null;
    return _playlistFromRow(rows.first);
  }

  Future<int> createPlaylist(String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.insert('playlists', {
      'name': name.trim(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> renamePlaylist(int id, String name) async {
    final pl = await getPlaylist(id);
    if (pl == null || pl.isSystem) return;
    await _db.update(
      'playlists',
      {
        'name': name.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePlaylistMeta({
    required int id,
    String? name,
    String? description,
    String? coverPath,
    bool clearDescription = false,
    bool clearCover = false,
  }) async {
    final map = <String, Object?>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (name != null) map['name'] = name.trim();
    if (clearDescription) {
      map['description'] = null;
    } else if (description != null) {
      map['description'] = description.trim().isEmpty ? null : description.trim();
    }
    if (clearCover) {
      map['cover_path'] = null;
    } else if (coverPath != null) {
      map['cover_path'] = coverPath;
    }
    await _db.update(
      'playlists',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Playlist _playlistFromRow(Map<String, Object?> r) {
    final updated = r['updated_at'] as int?;
    return Playlist(
      id: r['id'] as int,
      name: r['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      updatedAt: updated != null
          ? DateTime.fromMillisecondsSinceEpoch(updated)
          : null,
      description: r['description'] as String?,
      coverPath: r['cover_path'] as String?,
      trackCount: (r['track_count'] as int?) ?? 0,
      systemKind: r['system_kind'] as String?,
    );
  }

  Future<void> deletePlaylist(int id) async {
    final pl = await getPlaylist(id);
    if (pl == null || pl.isSystem) return;
    await _db.transaction((txn) async {
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'playlists',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Track>> getPlaylistTracks(int playlistId) async {
    final pl = await getPlaylist(playlistId);
    if (pl != null && pl.isTrash) {
      return getTrashedTracks();
    }
    if (pl != null && pl.isNew) {
      return getNewTracks();
    }
    final rows = await _db.rawQuery('''
      SELECT t.*, GROUP_CONCAT(f.file_path, '||') AS paths
      FROM playlist_tracks pt
      INNER JOIN tracks t ON t.track_key = pt.track_key
      INNER JOIN track_files f ON f.track_key = t.track_key
      WHERE pt.playlist_id = ? AND t.trashed_at IS NULL
      GROUP BY t.track_key
      ORDER BY pt.position ASC
    ''', [playlistId]);
    return rows.map(_trackFromRow).toList();
  }

  Future<void> moveTrackToTrash(String trackKey) async {
    final trashId = await ensureTrashPlaylist();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await txn.update(
        'tracks',
        {'trashed_at': now},
        where: 'track_key = ?',
        whereArgs: [trackKey],
      );
      // Remove from every playlist except trash.
      await txn.rawDelete(
        '''
        DELETE FROM playlist_tracks
        WHERE track_key = ?
          AND playlist_id != ?
        ''',
        [trackKey, trashId],
      );
      final existing = await txn.query(
        'playlist_tracks',
        where: 'playlist_id = ? AND track_key = ?',
        whereArgs: [trashId, trackKey],
      );
      if (existing.isEmpty) {
        final posRows = await txn.rawQuery(
          'SELECT COALESCE(MAX(position), -1) + 1 AS next_pos '
          'FROM playlist_tracks WHERE playlist_id = ?',
          [trashId],
        );
        final position = posRows.first['next_pos'] as int;
        await txn.insert('playlist_tracks', {
          'playlist_id': trashId,
          'track_key': trackKey,
          'position': position,
        });
      }
      await txn.update(
        'playlists',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [trashId],
      );
    });
  }

  Future<void> restoreTrackFromTrash(String trackKey) async {
    final trashId = await ensureTrashPlaylist();
    await _db.transaction((txn) async {
      await txn.update(
        'tracks',
        {'trashed_at': null},
        where: 'track_key = ?',
        whereArgs: [trackKey],
      );
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ? AND track_key = ?',
        whereArgs: [trashId, trackKey],
      );
      await txn.update(
        'playlists',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [trashId],
      );
    });
  }

  /// Returns file paths and cover path before wiping DB rows.
  Future<({List<String> filePaths, String? coverPath})>
      deleteTrackPermanently(String trackKey) async {
    final track = await getTrack(trackKey);
    final filePaths = track?.filePaths ?? const <String>[];
    final coverPath = track?.coverPath;

    await _db.transaction((txn) async {
      await txn.delete(
        'playlist_tracks',
        where: 'track_key = ?',
        whereArgs: [trackKey],
      );
      await txn.delete(
        'play_events',
        where: 'track_key = ?',
        whereArgs: [trackKey],
      );
      await txn.delete(
        'track_files',
        where: 'track_key = ?',
        whereArgs: [trackKey],
      );
      await txn.delete(
        'tracks',
        where: 'track_key = ?',
        whereArgs: [trackKey],
      );
    });

    return (filePaths: filePaths, coverPath: coverPath);
  }

  /// Sync trash playlist membership with trashed_at flags.
  Future<void> syncTrashPlaylistMembership() async {
    final trashId = await ensureTrashPlaylist();
    final trashed = await getTrashedTrackEntries();
    await _db.transaction((txn) async {
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [trashId],
      );
      for (var i = 0; i < trashed.length; i++) {
        await txn.insert('playlist_tracks', {
          'playlist_id': trashId,
          'track_key': trashed[i].trackKey,
          'position': i,
        });
      }
    });
  }

  /// Replace «Без метаданных» membership with [trackKeys], in that order.
  Future<void> syncIncompletePlaylistMembership(List<String> trackKeys) async {
    final id = await ensureIncompletePlaylist();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [id],
      );
      const chunk = 400;
      for (var i = 0; i < trackKeys.length; i += chunk) {
        final end = (i + chunk).clamp(0, trackKeys.length);
        final batch = txn.batch();
        for (var j = i; j < end; j++) {
          batch.insert('playlist_tracks', {
            'playlist_id': id,
            'track_key': trackKeys[j],
            'position': j,
          });
        }
        await batch.commit(noResult: true);
      }
      await txn.update(
        'playlists',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Sync Новинки membership with tracks added in the last 7 days.
  Future<void> syncNewPlaylistMembership() async {
    final newId = await ensureNewPlaylist();
    final tracks = await getNewTracks();
    await _db.transaction((txn) async {
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [newId],
      );
      for (var i = 0; i < tracks.length; i++) {
        await txn.insert('playlist_tracks', {
          'playlist_id': newId,
          'track_key': tracks[i].trackKey,
          'position': i,
        });
      }
      await txn.update(
        'playlists',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [newId],
      );
    });
  }

  Future<bool> addTrackToPlaylist(int playlistId, String trackKey) async {
    final existing = await _db.query(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_key = ?',
      whereArgs: [playlistId, trackKey],
    );
    if (existing.isNotEmpty) return false;

    final posRows = await _db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next_pos '
      'FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId],
    );
    final position = posRows.first['next_pos'] as int;
    await _db.insert('playlist_tracks', {
      'playlist_id': playlistId,
      'track_key': trackKey,
      'position': position,
    });
    await _touchPlaylist(playlistId);
    return true;
  }

  Future<void> removeFromPlaylist(int playlistId, String trackKey) async {
    await _db.delete(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_key = ?',
      whereArgs: [playlistId, trackKey],
    );
    await _touchPlaylist(playlistId);
  }

  /// Ordered track keys for a playlist (keeps keys even if track is missing).
  Future<List<String>> getPlaylistTrackKeys(int playlistId) async {
    final rows = await _db.query(
      'playlist_tracks',
      columns: ['track_key'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    return rows.map((r) => r['track_key'] as String).toList();
  }

  Future<List<({String trackKey, int playedAt})>> getAllPlayEvents() async {
    final rows = await _db.query(
      'play_events',
      columns: ['track_key', 'played_at'],
      orderBy: 'id ASC',
    );
    return [
      for (final row in rows)
        (
          trackKey: row['track_key'] as String,
          playedAt: row['played_at'] as int,
        ),
    ];
  }

  /// Replace playlists, membership, and play history (app data, not metadata).
  Future<void> replaceAppUserData({
    required List<PlaylistImportRow> playlists,
    required List<({String trackKey, int playedAt})> playEvents,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('playlist_tracks');
      await txn.delete('playlists');
      await txn.delete('play_events');

      for (final pl in playlists) {
        final id = await txn.insert('playlists', {
          'name': pl.name,
          'created_at': pl.createdAtMs,
          'updated_at': pl.updatedAtMs,
          'description': pl.description,
          'cover_path': pl.coverPath,
          'system_kind': pl.systemKind,
        });
        for (var i = 0; i < pl.trackKeys.length; i++) {
          await txn.insert('playlist_tracks', {
            'playlist_id': id,
            'track_key': pl.trackKeys[i],
            'position': i,
          });
        }
      }

      const chunk = 400;
      for (var i = 0; i < playEvents.length; i += chunk) {
        final end = (i + chunk).clamp(0, playEvents.length);
        final batch = playEvents.sublist(i, end);
        final batchOp = txn.batch();
        for (final e in batch) {
          batchOp.insert('play_events', {
            'track_key': e.trackKey,
            'played_at': e.playedAt,
          });
        }
        await batchOp.commit(noResult: true);
      }
    });
  }

  Future<void> _touchPlaylist(int playlistId) async {
    await _db.update(
      'playlists',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Track _trackFromRow(Map<String, Object?> row) {
    final pathsRaw = row['paths'] as String? ?? '';
    final paths = pathsRaw
        .split('||')
        .where((e) => e.isNotEmpty)
        .toList();
    final trashedMs = row['trashed_at'] as int?;
    final addedMs = row['added_at'] as int?;
    return Track(
      trackKey: row['track_key'] as String,
      title: row['title'] as String,
      artist: row['artist'] as String,
      album: row['album'] as String,
      genre: row['genre'] as String,
      albumArtist: row['album_artist'] as String?,
      producer: row['producer'] as String?,
      lyrics: row['lyrics'] as String?,
      year: row['year'] as int?,
      trackNumber: row['track_number'] as int?,
      trackTotal: row['track_total'] as int?,
      discNumber: row['disc_number'] as int?,
      durationMs: row['duration_ms'] as int?,
      coverPath: row['cover_path'] as String?,
      trashedAt: trashedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(trashedMs),
      addedAt: addedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(addedMs),
      filePaths: paths,
    );
  }

  Future<void> close() => _db.close();
}

class PlaylistImportRow {
  const PlaylistImportRow({
    required this.name,
    required this.createdAtMs,
    required this.trackKeys,
    this.updatedAtMs,
    this.description,
    this.coverPath,
    this.systemKind,
  });

  final String name;
  final int createdAtMs;
  final int? updatedAtMs;
  final String? description;
  final String? coverPath;
  final String? systemKind;
  final List<String> trackKeys;
}

class ArtistAlias {
  const ArtistAlias({
    required this.fromNorm,
    required this.fromDisplay,
    required this.toDisplay,
  });

  final String fromNorm;
  final String fromDisplay;
  final String toDisplay;
}

enum ChartPeriod {
  allTime,
  year,
  month,
}

extension ChartPeriodX on ChartPeriod {
  String get label => switch (this) {
        ChartPeriod.allTime => 'Всё время',
        ChartPeriod.year => 'Год',
        ChartPeriod.month => 'Месяц',
      };

  int? get sinceMs {
    final now = DateTime.now();
    return switch (this) {
      ChartPeriod.allTime => null,
      ChartPeriod.year =>
        DateTime(now.year - 1, now.month, now.day).millisecondsSinceEpoch,
      ChartPeriod.month =>
        DateTime(now.year, now.month - 1, now.day).millisecondsSinceEpoch,
    };
  }
}
