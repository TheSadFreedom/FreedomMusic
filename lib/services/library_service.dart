import 'dart:async';
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

class JobLogField {
  const JobLogField(this.label, this.value);

  final String label;
  final String value;
}

class JobLogEntry {
  const JobLogEntry({
    required this.artist,
    required this.title,
    required this.fields,
    required this.ok,
    required this.at,
    this.error,
  });

  final String artist;
  final String title;
  final List<JobLogField> fields;
  final bool ok;
  final DateTime at;
  final String? error;

  String get summary {
    final who = '$artist — $title';
    if (!ok) return '$who: ${error ?? 'не записалось'}';
    if (fields.isEmpty) return who;
    return '$who: ${fields.map((field) => '${field.label} ${field.value}').join(', ')}';
  }
}

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
  final List<JobLogEntry> _jobLog = [];

  AppPaths get paths => _paths;
  List<Track> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  bool get loading => _loading;
  bool get scanning => _scanning;
  ScanProgress? get scanProgress => _scanProgress;
  String? get lastScanMessage => _lastScanMessage;
  List<JobLogEntry> get jobLog => List.unmodifiable(_jobLog);
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
    await _db.ensureIncompletePlaylist();
    await _db.syncTrashPlaylistMembership();
    await _db.syncNewPlaylistMembership();
    _tracks = await _db.getAllTracks();
    await _db.syncIncompletePlaylistMembership([
      for (final track in _tracks)
        if (!track.isTrashed &&
            MetaLookupService.needsFill(
              album: track.album,
              albumArtist: track.albumArtist,
              year: track.year,
              trackNumber: track.trackNumber,
              trackTotal: track.trackTotal,
              producer: track.producer,
            ))
          track.trackKey,
    ]);
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
    final hay = track.searchableText;
    if (tokens.every(hay.contains)) return true;
    // Alias card names are short; only scan them when the file text missed.
    final extra = StringBuffer();
    final names = <String>[
      ...track.artists,
      ...splitArtists(track.albumArtist),
    ];
    for (final name in names) {
      final card = artistCardName(name);
      extra.write(' ');
      extra.write(card.toLowerCase());
      for (final alias in aliasLabelsForCard(card)) {
        extra.write(' ');
        extra.write(alias.toLowerCase());
      }
    }
    final more = extra.toString();
    return tokens.every((t) => hay.contains(t) || more.contains(t));
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
    _jobLog.clear();
    notifyListeners();

    try {
      final result = await _scanner.scan(
        force: force,
        onProgress: (p) {
          _scanProgress = p;
          notifyListeners();
        },
      );

      await reload();
      final forceLabel = force ? 'Полный перескан. ' : '';
      if (result.cancelled) {
        _lastScanMessage =
            '$forceLabel'
            'Сканирование остановлено. '
            'Успели: новых ${result.added}, обновлено ${result.updated}, '
            'без изменений ${result.skipped}.';
      } else {
        _lastScanMessage =
            '$forceLabel'
            'Файлов: ${result.totalFiles}. '
            'Новых: ${result.added}, обновлено: ${result.updated}, '
            'без изменений: ${result.skipped}, удалено: ${result.removed}.';
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

  /// Three steps: pick tracks with empty fields, look them up on the site,
  /// then write the hits. Genre and lyrics stay as they are.
  Future<void> fillEmptyMetadata() async {
    if (_scanning) return;
    _scanning = true;
    _cancelFill = false;
    _scanProgress = null;
    _lastScanMessage = null;
    _jobLog.clear();
    notifyListeners();

    try {
      final result = await _runMetadataPipeline();
      await reload();
      if (result.emptyCount == 0 && !result.cancelled) {
        _lastScanMessage =
            'Список «Без метаданных» пуст — заполнять нечего.';
      } else if (result.cancelled) {
        _lastScanMessage =
            'Поиск метаданных остановлен. В списке: ${result.emptyCount}. '
            'Найдено: ${result.found}. Записано: ${result.filled}.';
      } else {
        _lastScanMessage =
            'В списке без метаданных: ${result.emptyCount}. '
            'Найдено: ${result.found}. Записано: ${result.filled}.';
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

  /// Look up lyrics for tracks that have none and write only the lyrics tag.
  Future<void> fillMissingLyrics() async {
    if (_scanning) return;
    _scanning = true;
    _cancelFill = false;
    _scanProgress = null;
    _lastScanMessage = null;
    _jobLog.clear();
    notifyListeners();

    try {
      final candidates =
          _tracks.where((t) => !hasLyrics(t.lyrics)).toList(growable: false);
      if (candidates.isEmpty) {
        _lastScanMessage = 'Текстов для поиска нет — у всех треков текст уже есть.';
        return;
      }

      final result = await _fillLyrics(candidates);
      await reload();
      if (result.cancelled) {
        _lastScanMessage =
            'Поиск текстов остановлен. Записано: ${result.filled} '
            'из ${candidates.length}.';
      } else {
        _lastScanMessage =
            'Проверено треков без текста: ${candidates.length}. '
            'Записано: ${result.filled}.';
      }
    } catch (e) {
      _error = e.toString();
      _lastScanMessage = 'Ошибка поиска текстов: $e';
    } finally {
      _scanning = false;
      _cancelFill = false;
      _scanProgress = null;
      notifyListeners();
    }
  }

  /// Site lookup and file write run at the same time.
  /// Only tracks already in «Без метаданных» are queued: new files land there
  /// after a library scan, and filled tracks leave the list.
  /// Writing starts as soon as a lookup returns.
  Future<
      ({
        int scanned,
        int emptyCount,
        int found,
        int filled,
        bool cancelled,
      })> _runMetadataPipeline() async {
    final tracks = [
      for (final track in tracksMissingMetadata())
        if (_canSearchMetadata(track)) track,
    ];
    final total = tracks.length;
    final toSearch = _Pipe<Track>();
    final toWrite = _Pipe<({Track track, MetadataDraft draft, JobLogEntry entry})>();
    var scanned = 0;
    var emptyCount = 0;
    var searched = 0;
    var found = 0;
    var written = 0;
    String? detail;
    var lastUiAt = DateTime.fromMillisecondsSinceEpoch(0);
    const uiInterval = Duration(milliseconds: 400);

    void publish({bool force = false}) {
      final now = DateTime.now();
      if (!force && now.difference(lastUiAt) < uiInterval) return;
      lastUiAt = now;
      final workTotal = total == 0 ? 1 : total;
      final tail = detail == null ? '' : ' — $detail';
      _scanProgress = ScanProgress(
        processed: searched.clamp(0, total),
        total: workTotal,
        added: written,
        updated: found,
        skipped: total,
        currentFile: total == 0
            ? 'Список «Без метаданных» пуст'
            : 'Список $total · проверено $searched · '
                'найдено $found · записано $written$tail',
      );
      notifyListeners();
    }

    Future<void> searcher() async {
      while (!_cancelFill) {
        final track = await toSearch.take();
        if (track == null) return;
        detail = 'Ищем на сайте: ${track.displayArtist} — ${track.displayTitle}';
        publish();
        final prepared = await _lookupMetadata(track);
        searched++;
        if (prepared != null) {
          found++;
          toWrite.add((
            track: track,
            draft: prepared.draft,
            entry: prepared.entry,
          ));
        }
        publish();
      }
    }

    Future<void> writer() async {
      while (true) {
        final item = await toWrite.take();
        if (item == null) return;
        detail = 'Записываем: ${item.entry.summary}';
        publish(force: true);
        try {
          await saveTrackMetadata(item.track, item.draft, refreshLibrary: false);
          _pushJobLog(item.entry);
          written++;
        } catch (e) {
          _pushJobLog(
            JobLogEntry(
              artist: item.track.displayArtist,
              title: item.track.displayTitle,
              fields: const [],
              ok: false,
              at: DateTime.now(),
              error: 'не записалось ($e)',
            ),
          );
          debugPrint('auto-fill failed for ${item.track.trackKey}: $e');
        }
        publish(force: true);
      }
    }

    final searchJobs = List.generate(3, (_) => searcher());
    final writeJob = writer();
    emptyCount = total;
    try {
      for (final track in tracks) {
        if (_cancelFill) break;
        scanned++;
        detail = 'В очереди: ${track.displayArtist} — ${track.displayTitle}';
        toSearch.add(track);
        publish();
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      toSearch.close();
    }
    await Future.wait(searchJobs);
    toWrite.close();
    await writeJob;
    publish(force: true);
    return (
      scanned: scanned,
      emptyCount: emptyCount,
      found: found,
      filled: written,
      cancelled: _cancelFill,
    );
  }

  bool _canSearchMetadata(Track track) {
    final artist = track.artist.trim();
    return artist.isNotEmpty &&
        artist.toLowerCase() != 'unknown' &&
        track.title.trim().isNotEmpty;
  }

  Future<({MetadataDraft draft, JobLogEntry entry})?> _lookupMetadata(
    Track track,
  ) async {
    if (!MetaLookupService.needsFill(
      album: track.album,
      albumArtist: track.albumArtist,
      year: track.year,
      trackNumber: track.trackNumber,
      trackTotal: track.trackTotal,
      producer: track.producer,
    )) {
      return null;
    }
    if (track.title.trim().isEmpty ||
        track.artist.trim().isEmpty ||
        track.artist.toLowerCase() == 'unknown') {
      return null;
    }

    final hit = await _metaLookup.lookup(
      artist: track.artist,
      title: track.title,
    );
    if (hit == null) return null;

    final needAlbum = track.album.trim().isEmpty ||
        const {'unknown', 'мне нравится', 'мне нужен ui'}
            .contains(track.album.trim().toLowerCase());
    final needAlbumArtist =
        MetaLookupService.albumArtistMissing(track.albumArtist);
    final needYear = track.year == null || track.year! < 1000;
    final needTrackNo = track.trackNumber == null || track.trackNumber! < 1;
    final needTrackTotal = track.trackTotal == null || track.trackTotal! < 1;
    final needDisc = track.discNumber == null || track.discNumber! < 1;
    final needProducer =
        track.producer == null || track.producer!.trim().isEmpty;

    final newAlbum = (needAlbum && hit.album != null && hit.album!.isNotEmpty)
        ? MetaLookupService.cleanAlbum(hit.album!)
        : track.album;
    final newAlbumArtist = (needAlbumArtist &&
            hit.albumArtist != null &&
            hit.albumArtist!.trim().isNotEmpty)
        ? formatArtists(hit.albumArtist)
        : track.albumArtist;
    final newYear = (needYear && hit.year != null) ? hit.year : track.year;
    final newTrackNo = (needTrackNo && hit.trackNumber != null)
        ? hit.trackNumber
        : track.trackNumber;
    final newTrackTotal = (needTrackTotal && hit.trackTotal != null)
        ? hit.trackTotal
        : track.trackTotal;
    final newDisc =
        (needDisc && hit.discNumber != null) ? hit.discNumber : track.discNumber;
    final newProducer = (needProducer &&
            hit.producer != null &&
            hit.producer!.trim().isNotEmpty)
        ? hit.producer!.trim()
        : track.producer;

    if (newAlbum == track.album &&
        newAlbumArtist == track.albumArtist &&
        newYear == track.year &&
        newTrackNo == track.trackNumber &&
        newTrackTotal == track.trackTotal &&
        newDisc == track.discNumber &&
        newProducer == track.producer) {
      return null;
    }

    final draft = MetadataDraft.fromTrack(track)
      ..album = newAlbum
      ..albumArtist = newAlbumArtist
      ..year = newYear
      ..trackNumber = newTrackNo
      ..trackTotal = newTrackTotal
      ..discNumber = newDisc
      ..producer = newProducer;
    final entry = _metaLogEntry(
      track,
      album: newAlbum != track.album ? newAlbum : null,
      albumArtist: newAlbumArtist != track.albumArtist ? newAlbumArtist : null,
      year: newYear != track.year ? newYear : null,
      trackNumber: (newTrackNo != track.trackNumber ||
              newTrackTotal != track.trackTotal)
          ? newTrackNo
          : null,
      trackTotal: (newTrackNo != track.trackNumber ||
              newTrackTotal != track.trackTotal)
          ? newTrackTotal
          : null,
      discNumber: newDisc != track.discNumber ? newDisc : null,
      producer: newProducer != track.producer ? newProducer : null,
    );
    return (draft: draft, entry: entry);
  }

  Future<({int filled, bool cancelled})> _fillLyrics(
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
        currentFile: 'Ищем текст: ${track.displayArtist} — ${track.displayTitle}',
      );
      notifyListeners();
    }

    for (var i = 0; i < candidates.length; i++) {
      if (_cancelFill) {
        return (filled: filled, cancelled: true);
      }
      final track = candidates[i];
      publishProgress(i, track);
      if (hasLyrics(track.lyrics)) continue;
      if (track.title.trim().isEmpty ||
          track.artist.trim().isEmpty ||
          track.artist.toLowerCase() == 'unknown') {
        continue;
      }

      final text = await _lyrics.fetchForTrack(track);
      if (text == null || !hasLyrics(text)) continue;

      final entry = JobLogEntry(
        artist: track.displayArtist,
        title: track.displayTitle,
        fields: const [JobLogField('Текст', 'записан')],
        ok: true,
        at: DateTime.now(),
      );
      try {
        _scanProgress = ScanProgress(
          processed: i + 1,
          total: total,
          added: filled + 1,
          updated: 0,
          skipped: 0,
          currentFile: entry.summary,
        );
        await saveTrackMetadata(
          track,
          MetadataDraft.fromTrack(track)..lyrics = text,
          refreshLibrary: false,
        );
        _pushJobLog(entry);
        filled++;
        notifyListeners();
      } catch (e, st) {
        debugPrint('lyrics tag write ${track.trackKey}: $e\n$st');
        try {
          await _db.updateTrackLyrics(track.trackKey, text);
          final updated = track.copyWith(lyrics: text);
          final index =
              _tracks.indexWhere((t) => t.trackKey == track.trackKey);
          if (index >= 0) _tracks[index] = updated;
          _pushJobLog(entry);
          filled++;
          notifyListeners();
        } catch (e2) {
          _pushJobLog(
            JobLogEntry(
              artist: track.displayArtist,
              title: track.displayTitle,
              fields: const [],
              ok: false,
              at: DateTime.now(),
              error: 'текст не записался ($e2)',
            ),
          );
          debugPrint('lyrics db write ${track.trackKey}: $e2');
          notifyListeners();
        }
      }
      if (filled > 0 && filled % 25 == 0) {
        imageCache.clear();
        imageCache.clearLiveImages();
      }
    }
    return (filled: filled, cancelled: false);
  }

  void _pushJobLog(JobLogEntry entry) {
    _jobLog.add(entry);
    if (_jobLog.length > 500) {
      _jobLog.removeRange(0, _jobLog.length - 500);
    }
  }

  JobLogEntry _metaLogEntry(
    Track track, {
    String? album,
    String? albumArtist,
    int? year,
    int? trackNumber,
    int? trackTotal,
    int? discNumber,
    String? producer,
  }) {
    final fields = <JobLogField>[];
    if (album != null && album.trim().isNotEmpty) {
      fields.add(JobLogField('Альбом', album.trim()));
    }
    if (albumArtist != null && albumArtist.trim().isNotEmpty) {
      fields.add(JobLogField('Артист альбома', albumArtist.trim()));
    }
    if (year != null) fields.add(JobLogField('Год', '$year'));
    if (trackNumber != null || trackTotal != null) {
      final no = trackNumber?.toString() ?? '—';
      fields.add(
        JobLogField(
          'Номер',
          trackTotal != null ? '$no из $trackTotal' : no,
        ),
      );
    }
    if (discNumber != null) fields.add(JobLogField('Диск', '$discNumber'));
    if (producer != null && producer.trim().isNotEmpty) {
      fields.add(JobLogField('Продюсер', producer.trim()));
    }
    return JobLogEntry(
      artist: track.displayArtist,
      title: track.displayTitle,
      fields: fields,
      ok: true,
      at: DateTime.now(),
    );
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

  Map<String, List<Track>> tracksByProducer() {
    final map = <String, List<Track>>{};
    final displayName = <String, String>{};

    for (final t in _tracks) {
      for (final name in producerNames(t.producer)) {
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

  /// If the file has no lyrics, look them up and write them into the tag.
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
      final source = trackByKey(key) ?? track;
      try {
        final updated = await saveTrackMetadata(
          source,
          MetadataDraft.fromTrack(source)..lyrics = text,
          refreshLibrary: false,
        );
        _lyricsMisses.remove(key);
        return updated;
      } catch (e, st) {
        // The file can be locked while it is playing. Keep the text in the
        // library so the panel still shows it.
        debugPrint('lyrics tag write $key: $e\n$st');
        await _db.updateTrackLyrics(key, text);
        final updated = source.copyWith(lyrics: text);
        final i = _tracks.indexWhere((t) => t.trackKey == key);
        if (i >= 0) _tracks[i] = updated;
        _lyricsMisses.remove(key);
        return updated;
      }
    } catch (e, st) {
      debugPrint('lyrics lookup $key: $e\n$st');
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
    notifyListeners();
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

  /// Tracks still missing album, album artist, year, number, or producer.
  List<Track> tracksMissingMetadata() {
    return [
      for (final track in _tracks)
        if (!track.isTrashed &&
            MetaLookupService.needsFill(
              album: track.album,
              albumArtist: track.albumArtist,
              year: track.year,
              trackNumber: track.trackNumber,
              trackTotal: track.trackTotal,
              producer: track.producer,
            ))
          track,
    ];
  }

  Future<List<Track>> playlistTracks(int id) async {
    final playlist = playlistById(id);
    if (playlist != null && playlist.isIncomplete) {
      return tracksMissingMetadata();
    }
    return _db.getPlaylistTracks(id);
  }

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

class _Pipe<T> {
  final _items = <T>[];
  final _waiters = <Completer<T?>>[];
  var _closed = false;

  void add(T item) {
    if (_closed) return;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(item);
    } else {
      _items.add(item);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    _waiters.clear();
  }

  Future<T?> take() {
    if (_items.isNotEmpty) return Future<T?>.value(_items.removeAt(0));
    if (_closed) return Future<T?>.value(null);
    final waiter = Completer<T?>();
    _waiters.add(waiter);
    return waiter.future;
  }
}
