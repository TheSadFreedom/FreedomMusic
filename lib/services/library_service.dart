import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../data/app_paths.dart';
import '../data/database.dart';
import '../data/track_key.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../utils/lyrics_format.dart';
import 'artist_photo_service.dart';
import 'backup_service.dart';
import 'lyrics_service.dart';
import 'meta_lookup_service.dart';
import 'metadata_writer.dart';
import 'scanner_service.dart';
import 'settings_service.dart';

class LibraryService extends ChangeNotifier {
  LibraryService({
    required AppPaths paths,
    required AppDatabase db,
    required SettingsService settings,
  })  : _paths = paths,
        _db = db,
        _settings = settings,
        _scanner = ScannerService(paths: paths, db: db),
        _metaLookup = MetaLookupService(),
        _artistPhotos = ArtistPhotoService(),
        _lyrics = LyricsService(),
        _backup = BackupService(paths: paths, db: db, settings: settings);

  final AppPaths _paths;
  final AppDatabase _db;
  final SettingsService _settings;
  final ScannerService _scanner;
  final MetaLookupService _metaLookup;
  final ArtistPhotoService _artistPhotos;
  final LyricsService _lyrics;
  final BackupService _backup;

  final Set<String> _lyricsFetching = {};
  final Set<String> _lyricsMisses = {};

  bool _artistPhotosRefreshing = false;
  ArtistPhotoProgress? _artistPhotoProgress;

  bool get artistPhotosRefreshing => _artistPhotosRefreshing;
  ArtistPhotoProgress? get artistPhotoProgress => _artistPhotoProgress;

  bool isFetchingLyrics(String trackKey) => _lyricsFetching.contains(trackKey);

  bool lyricsLookupFailed(String trackKey) => _lyricsMisses.contains(trackKey);

  List<Track> _tracks = [];
  List<Playlist> _playlists = [];

  /// normalizeTag(alias) → artist-card display name.
  Map<String, String> _aliasToCard = {};

  /// normalizeTag(card) → other names that open the same card.
  Map<String, List<String>> _aliasLabelsByCard = {};
  bool _loading = true;
  bool _scanning = false;
  ScanProgress? _scanProgress;
  String? _lastScanMessage;
  String? _error;

  AppPaths get paths => _paths;
  List<Track> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  bool get loading => _loading;
  bool get scanning => _scanning;
  ScanProgress? get scanProgress => _scanProgress;
  String? get lastScanMessage => _lastScanMessage;
  String? get error => _error;
  bool get isEmpty => _tracks.isEmpty;

  Future<void> init() async {
    _loading = true;
    notifyListeners();
    try {
      final remapped = await _db.remigrateTrackKeysToArtistTitle();
      if (remapped > 0) {
        await _settings.replaceChartSnapshots({});
      }
      if (!_settings.artistTagsRestored) {
        final restored = await _scanner.restoreOriginalArtistTags();
        if (restored > 0) {
          await _settings.replaceChartSnapshots({});
        }
        await _settings.setArtistTagsRestored();
      }
      await reload();
      if (_settings.scanOnStartup) {
        await scanLibrary();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    await _db.ensureTrashPlaylist();
    await _db.ensureNewPlaylist();
    await _db.syncTrashPlaylistMembership();
    await _db.syncNewPlaylistMembership();
    _tracks = await _db.getAllTracks();
    _playlists = await _db.getPlaylists();
    await _loadArtistAliases();
    _error = null;
    notifyListeners();
  }

  Future<void> _loadArtistAliases() async {
    final rows = await _db.getArtistAliases();
    final toCard = <String, String>{};
    final labels = <String, List<String>>{};
    for (final row in rows) {
      final card = row.toDisplay.trim();
      if (card.isEmpty) continue;
      toCard[row.fromNorm] = card;
      final bucket = labels.putIfAbsent(normalizeTag(card), () => []);
      final from = row.fromDisplay.trim();
      if (from.isNotEmpty &&
          normalizeTag(from) != normalizeTag(card) &&
          !bucket.any((n) => normalizeTag(n) == normalizeTag(from))) {
        bucket.add(from);
      }
    }
    _aliasToCard = toCard;
    _aliasLabelsByCard = labels;
  }

  /// Name shown on the artist card. Track tags are not rewritten.
  String artistCardName(String artistName) {
    final trimmed = artistName.trim();
    if (trimmed.isEmpty) return trimmed;
    return _aliasToCard[normalizeTag(trimmed)] ?? trimmed;
  }

  List<String> aliasLabelsForCard(String cardName) {
    return _aliasLabelsByCard[normalizeTag(cardName)] ?? const [];
  }

  bool artistCardMatchesQuery(String cardName, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (cardName.toLowerCase().contains(q)) return true;
    for (final alias in aliasLabelsForCard(cardName)) {
      if (alias.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  bool trackMatchesQuery(Track track, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final hay = StringBuffer(track.searchableText);
    final names = <String>[
      ...track.artists,
      ...splitArtists(track.albumArtist),
    ];
    for (final name in names) {
      final card = artistCardName(name);
      hay.write(' ');
      hay.write(card.toLowerCase());
      for (final alias in aliasLabelsForCard(card)) {
        hay.write(' ');
        hay.write(alias.toLowerCase());
      }
    }
    final text = hay.toString();
    return tokens.every(text.contains);
  }

  Playlist? get trashPlaylist {
    for (final pl in _playlists) {
      if (pl.isTrash) return pl;
    }
    return null;
  }

  /// Soft-delete: hide everywhere, keep files, put into Корзина.
  Future<void> moveToTrash(String trackKey) async {
    await _db.moveTrackToTrash(trackKey);
    await reload();
  }

  Future<void> restoreFromTrash(String trackKey) async {
    await _db.restoreTrackFromTrash(trackKey);
    await reload();
  }

  /// Permanently delete track files from disk and remove from the library.
  Future<void> deleteTrackPermanently(String trackKey) async {
    final meta = await _db.deleteTrackPermanently(trackKey);
    for (final path in meta.filePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (meta.coverPath != null) {
      try {
        final cover = File(meta.coverPath!);
        if (await cover.exists()) await cover.delete();
      } catch (_) {}
    }
    await MetadataWriter.deleteCovers(_paths, trackKey);
    await reload();
  }

  bool _cancelFill = false;

  void cancelScan() {
    if (!_scanning) return;
    _cancelFill = true;
    _scanner.requestCancel();
    notifyListeners();
  }

  Future<void> scanLibrary({bool force = false}) async {
    if (_scanning) return;
    _scanning = true;
    _cancelFill = false;
    _scanProgress = null;
    _lastScanMessage = null;
    notifyListeners();

    try {
      final result = await _scanner.scan(
        force: force,
        onProgress: (p) {
          _scanProgress = p;
          notifyListeners();
        },
      );

      var filled = 0;
      var fillCancelled = false;
      // Autofill only for newly added tracks (not on full rescan of thousands).
      if (!force &&
          !result.cancelled &&
          _settings.autoFillEmptyMetadata &&
          result.addedTracks.isNotEmpty) {
        final fillResult = await _autoFillTracks(result.addedTracks);
        filled = fillResult.filled;
        fillCancelled = fillResult.cancelled;
      }

      await reload();
      final forceLabel = force ? 'Полный перескан. ' : '';
      if (result.cancelled || fillCancelled) {
        _lastScanMessage =
            '$forceLabel'
            'Сканирование остановлено. '
            'Успели: новых ${result.added}, обновлено ${result.updated}, '
            'без изменений ${result.skipped}'
            '${filled > 0 ? ', дополнено метаданных $filled' : ''}.';
      } else {
        _lastScanMessage =
            '$forceLabel'
            'Файлов: ${result.totalFiles}. '
            'Новых: ${result.added}, обновлено: ${result.updated}, '
            'без изменений: ${result.skipped}, удалено: ${result.removed}.'
            '${filled > 0 ? ' Дополнено метаданных: $filled.' : ''}';
      }
    } catch (e) {
      _error = e.toString();
      _lastScanMessage = 'Ошибка сканирования: $e';
    } finally {
      _scanning = false;
      _cancelFill = false;
      _scanProgress = null;
      notifyListeners();
    }
  }

  /// Search the whole library for tracks with empty album/genre/year/track №
  /// and fill them from the network (title, artist, cover unchanged).
  Future<void> fillEmptyMetadata() async {
    if (_scanning) return;
    _scanning = true;
    _cancelFill = false;
    _scanProgress = null;
    _lastScanMessage = null;
    notifyListeners();

    try {
      final candidates = _tracks
          .where(
            (t) => MetaLookupService.needsFill(
              album: t.album,
              genre: t.genre,
              year: t.year,
              trackNumber: t.trackNumber,
              trackTotal: t.trackTotal,
            ),
          )
          .toList();

      if (candidates.isEmpty) {
        _lastScanMessage =
            'Пустых метаданных не найдено — у всех треков альбом, жанр, год '
            'и номер уже заполнены.';
        return;
      }

      final result = await _autoFillTracks(candidates);
      await reload();
      if (result.cancelled) {
        _lastScanMessage =
            'Поиск метаданных остановлен. Дополнено: ${result.filled} '
            'из ${candidates.length}.';
      } else {
        _lastScanMessage =
            'Проверено треков с пустыми полями: ${candidates.length}. '
            'Дополнено: ${result.filled}.';
      }
    } catch (e) {
      _error = e.toString();
      _lastScanMessage = 'Ошибка поиска метаданных: $e';
    } finally {
      _scanning = false;
      _cancelFill = false;
      _scanProgress = null;
      notifyListeners();
    }
  }

  /// Fills empty album / genre / year from the internet and writes into files.
  Future<({int filled, bool cancelled})> _autoFillTracks(
    List<Track> candidates,
  ) async {
    var filled = 0;
    final total = candidates.length;
    var lastUiAt = DateTime.fromMillisecondsSinceEpoch(0);
    const uiInterval = Duration(milliseconds: 400);

    void publishProgress(int index, Track track) {
      final now = DateTime.now();
      if (now.difference(lastUiAt) < uiInterval && index + 1 < total) {
        return;
      }
      lastUiAt = now;
      _scanProgress = ScanProgress(
        processed: index + 1,
        total: total,
        added: filled,
        updated: 0,
        skipped: 0,
        currentFile: 'Метаданные: ${track.displayTitle}',
      );
      notifyListeners();
    }

    for (var i = 0; i < candidates.length; i++) {
      if (_cancelFill) {
        return (filled: filled, cancelled: true);
      }
      final track = candidates[i];
      publishProgress(i, track);

      if (!MetaLookupService.needsFill(
        album: track.album,
        genre: track.genre,
        year: track.year,
        trackNumber: track.trackNumber,
        trackTotal: track.trackTotal,
      )) {
        continue;
      }
      if (track.title.trim().isEmpty ||
          track.artist.trim().isEmpty ||
          track.artist.toLowerCase() == 'unknown') {
        continue;
      }

      final hit = await _metaLookup.lookup(
        artist: track.artist,
        title: track.title,
      );
      if (hit == null) continue;

      final needAlbum = track.album.trim().isEmpty ||
          const {'unknown', 'мне нравится', 'мне нужен ui'}
              .contains(track.album.trim().toLowerCase());
      final needGenre = track.genre.trim().isEmpty ||
          track.genre.trim().toLowerCase() == 'unknown';
      final needYear = track.year == null || track.year! < 1000;
      final needTrackNo =
          track.trackNumber == null || track.trackNumber! < 1;
      final needTrackTotal =
          track.trackTotal == null || track.trackTotal! < 1;
      final needDisc = track.discNumber == null || track.discNumber! < 1;

      final newAlbum = (needAlbum && hit.album != null && hit.album!.isNotEmpty)
          ? MetaLookupService.cleanAlbum(hit.album!)
          : track.album;
      final newGenre = (needGenre && hit.genre != null && hit.genre!.isNotEmpty)
          ? hit.genre!
          : track.genre;
      final newYear = (needYear && hit.year != null) ? hit.year : track.year;
      final newTrackNo = (needTrackNo && hit.trackNumber != null)
          ? hit.trackNumber
          : track.trackNumber;
      final newTrackTotal = (needTrackTotal && hit.trackTotal != null)
          ? hit.trackTotal
          : track.trackTotal;
      final newDisc = (needDisc && hit.discNumber != null)
          ? hit.discNumber
          : track.discNumber;

      if (newAlbum == track.album &&
          newGenre == track.genre &&
          newYear == track.year &&
          newTrackNo == track.trackNumber &&
          newTrackTotal == track.trackTotal &&
          newDisc == track.discNumber) {
        continue;
      }

      try {
        final draft = MetadataDraft.fromTrack(track)
          ..album = newAlbum
          ..genre = newGenre
          ..year = newYear
          ..trackNumber = newTrackNo
          ..trackTotal = newTrackTotal
          ..discNumber = newDisc;
        // No full-library reload per track — that was blowing RAM to tens of GB.
        await saveTrackMetadata(track, draft, refreshLibrary: false);
        filled++;
        if (filled % 25 == 0) {
          imageCache.clear();
          imageCache.clearLiveImages();
        }
      } catch (e) {
        debugPrint('auto-fill failed for ${track.trackKey}: $e');
      }
    }
    return (filled: filled, cancelled: false);
  }

  Map<String, List<Track>> tracksByGenre() {
    final map = <String, List<Track>>{};
    for (final t in _tracks) {
      map.putIfAbsent(t.displayGenre, () => []).add(t);
    }
    final keys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final k in keys) k: map[k]!};
  }

  Map<String, List<Track>> tracksByArtist() {
    // One track can appear under several artists ("A, B" → A and B).
    final map = <String, List<Track>>{};
    final displayName = <String, String>{}; // lower -> preferred casing

    for (final t in _tracks) {
      for (final name in t.artists) {
        final card = artistCardName(name);
        final lower = card.toLowerCase();
        final label = displayName.putIfAbsent(lower, () => card);
        final list = map.putIfAbsent(label, () => []);
        if (!list.any((existing) => existing.trackKey == t.trackKey)) {
          list.add(t);
        }
      }
    }

    final keys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final k in keys) k: map[k]!};
  }

  Future<List<ChartEntry>> chart(ChartPeriod period) {
    return _db.getChart(library: _tracks, period: period);
  }

  Future<Map<String, int>> playCountsAllTime() => _db.getPlayCountsAllTime();

  Future<Map<String, int>> listenMsAllTime() => _db.getListenMsAllTime();

  List<Track> search(String query) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _tracks.where((t) => trackMatchesQuery(t, q)).toList();
  }

  Future<void> recordPlay(String trackKey) => _db.recordPlay(trackKey);

  Future<void> addListenMs(String trackKey, int ms) =>
      _db.addListenMs(trackKey, ms);

  /// Writes tags to disk and refreshes the local index.
  ///
  /// If the track has no lyrics tag, try LRCLIB and store the result in the DB.
  /// Returns the updated track when lyrics were found, otherwise null.
  Future<Track?> ensureRemoteLyrics(Track track) async {
    final key = track.trackKey;
    if (hasLyrics(track.lyrics)) return null;
    final cached = trackByKey(key);
    if (cached != null && hasLyrics(cached.lyrics)) return cached;
    if (_lyricsMisses.contains(key) || _lyricsFetching.contains(key)) {
      return null;
    }

    _lyricsFetching.add(key);
    notifyListeners();
    try {
      final text = await _lyrics.fetchForTrack(track);
      if (text == null || !hasLyrics(text)) {
        _lyricsMisses.add(key);
        return null;
      }
      await _db.updateTrackLyrics(key, text);
      final updated = (trackByKey(key) ?? track).copyWith(lyrics: text);
      final i = _tracks.indexWhere((t) => t.trackKey == key);
      if (i >= 0) _tracks[i] = updated;
      _lyricsMisses.remove(key);
      return updated;
    } catch (e, st) {
      debugPrint('LRCLIB lyrics $key: $e\n$st');
      _lyricsMisses.add(key);
      return null;
    } finally {
      _lyricsFetching.remove(key);
      notifyListeners();
    }
  }

  Track? trackByKey(String trackKey) {
    for (final t in _tracks) {
      if (t.trackKey == trackKey) return t;
    }
    return null;
  }

  /// Set [refreshLibrary] to false during batch autofill — a full [reload]
  /// after every file multiplies RAM (all tracks + lyrics + UI rebuilds).
  Future<Track> saveTrackMetadata(
    Track track,
    MetadataDraft draft, {
    bool refreshLibrary = true,
  }) async {
    final oldKey = track.trackKey;
    final updated = await MetadataWriter.write(
      track,
      draft,
      paths: _paths,
    );
    await _db.applyMetadataEdit(oldTrackKey: oldKey, updated: updated);
    if (refreshLibrary) {
      await reload();
      return _tracks.firstWhere(
        (t) => t.trackKey == updated.trackKey,
        orElse: () => updated,
      );
    }

    final i = _tracks.indexWhere((t) => t.trackKey == oldKey);
    if (i >= 0) {
      _tracks[i] = updated;
    } else if (oldKey != updated.trackKey) {
      final j = _tracks.indexWhere((t) => t.trackKey == updated.trackKey);
      if (j >= 0) _tracks[j] = updated;
    }
    return updated;
  }

  Future<int> createPlaylist(String name) async {
    final id = await _db.createPlaylist(name);
    await reload();
    return id;
  }

  Playlist? playlistById(int id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> renamePlaylist(int id, String name) async {
    final pl = playlistById(id);
    if (pl == null || pl.isSystem) return;
    await _db.renamePlaylist(id, name);
    await reload();
  }

  Future<void> deletePlaylist(int id) async {
    final pl = playlistById(id);
    if (pl == null || pl.isSystem) return;
    await _db.deletePlaylist(id);
    await reload();
  }

  Future<void> setPlaylistDescription(int id, String? description) async {
    await _db.updatePlaylistMeta(
      id: id,
      description: description ?? '',
      clearDescription: description == null || description.trim().isEmpty,
    );
    await reload();
  }

  Future<void> setPlaylistCover(int id, Uint8List bytes) async {
    await _paths.ensureDirectories();
    final hash = sha1.convert(utf8.encode('playlist_$id')).toString();
    final file = File(p.join(_paths.playlistsDir, '$hash.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    await _db.updatePlaylistMeta(id: id, coverPath: file.path);
    await reload();
  }

  Future<void> clearPlaylistCover(int id) async {
    await _db.updatePlaylistMeta(id: id, clearCover: true);
    await reload();
  }

  /// Custom artist photo, or null to fall back to album art.
  String? artistPhotoPath(String artistName) {
    final custom = _settings.artistPhotoPath(artistName);
    if (custom != null && File(custom).existsSync()) return custom;
    return null;
  }

  Future<void> setArtistPhoto(
    String artistName,
    Uint8List bytes, {
    bool manual = true,
    bool notify = true,
  }) async {
    await _paths.ensureDirectories();
    final hash =
        sha1.convert(utf8.encode(artistName.trim().toLowerCase())).toString();
    final file = File(p.join(_paths.artistsDir, '$hash.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    await _settings.setArtistPhotoPath(artistName, file.path, manual: manual);
    if (notify) notifyListeners();
  }

  Future<void> clearArtistPhoto(String artistName) async {
    await _settings.setArtistPhotoPath(artistName, null);
    notifyListeners();
  }

  /// Merge [from] into [into] in the library index (MP3 tags are not rewritten).
  Future<void> mergeArtists({
    required String into,
    required String from,
  }) async {
    final a = into.trim();
    final b = from.trim();
    if (a.isEmpty || b.isEmpty) return;
    if (a.toLowerCase() == b.toLowerCase()) return;

    await _db.upsertArtistAlias(fromDisplay: b, toDisplay: a);

    final fromPhoto = _settings.artistPhotoPath(b);
    final intoPhoto = _settings.artistPhotoPath(a);
    if (intoPhoto == null && fromPhoto != null) {
      await _settings.setArtistPhotoPath(
        a,
        fromPhoto,
        manual: _settings.isArtistPhotoManual(b),
      );
    }
    await _settings.setArtistPhotoPath(b, null);

    await reload();
  }

  /// Genius → Deezer portraits for library artists (skips manual picks).
  /// Returns how many photos were written.
  Future<int> refreshArtistPhotos() async {
    if (_artistPhotosRefreshing || _tracks.isEmpty) return 0;
    _artistPhotosRefreshing = true;
    _artistPhotoProgress = const ArtistPhotoProgress(done: 0, total: 0);
    notifyListeners();
    var updated = 0;
    var done = 0;
    try {
      final names = <String>{};
      for (final t in _tracks) {
        for (final a in t.artists) {
          final n = a.trim();
          if (n.isEmpty || n.toLowerCase() == 'unknown') continue;
          names.add(n);
        }
      }
      final queue = names.toList()..sort();
      if (queue.isEmpty) return 0;

      final total = queue.length;
      _artistPhotoProgress = ArtistPhotoProgress(done: 0, total: total);
      notifyListeners();

      const batch = 3;
      for (var i = 0; i < queue.length; i += batch) {
        final slice = queue.sublist(
          i,
          i + batch > queue.length ? queue.length : i + batch,
        );
        await Future.wait(slice.map((name) async {
          try {
            if (!_settings.isArtistPhotoManual(name)) {
              final bytes = await _artistPhotos.fetchPhotoBytes(name);
              if (bytes != null && bytes.isNotEmpty) {
                await setArtistPhoto(name, bytes, manual: false, notify: false);
                updated++;
              }
            }
          } catch (e, st) {
            debugPrint('artist photo $name: $e\n$st');
          } finally {
            done++;
            _artistPhotoProgress = ArtistPhotoProgress(
              done: done,
              total: total,
              updated: updated,
              current: name,
            );
            notifyListeners();
          }
        }));
      }
      return updated;
    } finally {
      _artistPhotosRefreshing = false;
      _artistPhotoProgress = null;
      notifyListeners();
    }
  }

  Future<List<Track>> playlistTracks(int id) => _db.getPlaylistTracks(id);

  /// Returns false when the track was already in the playlist.
  Future<bool> addToPlaylist(int playlistId, String trackKey) async {
    final pl = playlistById(playlistId);
    if (pl == null || pl.isSystem) return false;
    final added = await _db.addTrackToPlaylist(playlistId, trackKey);
    if (added) await reload();
    return added;
  }

  Future<void> removeFromPlaylist(int playlistId, String trackKey) async {
    await _db.removeFromPlaylist(playlistId, trackKey);
    await reload();
  }

  Future<void> clearPlayCounts() async {
    await _db.clearPlayEvents();
    await _settings.replaceChartSnapshots(const {});
    notifyListeners();
  }

  Future<BackupResult> exportAppData(String destPath) {
    return _backup.exportToFile(destPath);
  }

  Future<BackupResult> importAppData(String sourcePath) async {
    final result = await _backup.importFromFile(sourcePath);
    await reload();
    notifyListeners();
    return result;
  }
}
