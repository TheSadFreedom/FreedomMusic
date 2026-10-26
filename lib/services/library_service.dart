import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import '../data/app_paths.dart';
import '../data/database.dart';
import '../data/track_key.dart';
import '../data/track_meta.dart';
import '../models/artist_release.dart';
import '../models/catalog_search.dart';
import '../models/playlist.dart';
import '../models/playlist_mosaic.dart';
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
  Map<int, List<String>> _mosaicCache = {};
  final Map<String, String> _trackKeyAlias = {};

  /// normalizeTag(alias) → artist-card display name.
  Map<String, String> _aliasToCard = {};

  /// normalizeTag(card) → other names that open the same artist card.
  Map<String, List<String>> _aliasLabelsByCard = {};

  /// normalizeTag(alias) → producer-card display name.
  Map<String, String> _producerAliasToCard = {};

  /// normalizeTag(card) → other names that open the same producer card.
  Map<String, List<String>> _producerAliasLabelsByCard = {};
  _CatalogIndex? _catalogIndex;
  String? _catalogQuery;
  CatalogSearch? _catalogHit;
  bool _loading = true;
  bool _scanning = false;
  ScanProgress? _scanProgress;
  String? _lastScanMessage;
  String? _error;
  final List<JobLogEntry> _jobLog = [];

  AppPaths get paths => _paths;
  List<Track> get tracks => _tracks;

  List<Track>? _catalogCache;
  List<Track>? _battleCache;
  Map<String, List<Track>>? _genreCache;
  Map<String, List<Track>>? _artistCache;
  Map<String, List<Track>>? _producerCache;
  Map<String, List<Track>>? _battleArtistCache;
  List<ReleaseCalendarSection>? _calendarCache;

  void _dropSlices() {
    _catalogCache = null;
    _battleCache = null;
    _genreCache = null;
    _artistCache = null;
    _producerCache = null;
    _battleArtistCache = null;
    _calendarCache = null;
  }

  void _ensureTrackSlices() {
    if (_catalogCache != null) return;
    final catalog = <Track>[];
    final battle = <Track>[];
    final genre = <String, List<Track>>{};
    final artist = <String, List<Track>>{};
    final artistLabels = <String, String>{};
    final producer = <String, List<Track>>{};
    final producerLabels = <String, String>{};
    final battleArtist = <String, List<Track>>{};
    final battleLabels = <String, String>{};

    for (final track in _tracks) {
      if (track.isBattle) {
        battle.add(track);
        _putArtist(track, battleArtist, battleLabels);
        continue;
      }
      catalog.add(track);
      final name = track.displayGenre;
      if (name.isNotEmpty) {
        genre.putIfAbsent(name, () => []).add(track);
      }
      _putArtist(track, artist, artistLabels);
      for (final raw in producerNames(track.producer)) {
        final card = producerCardName(raw);
        final label = producerLabels.putIfAbsent(card.toLowerCase(), () => card);
        final list = producer.putIfAbsent(label, () => []);
        if (!list.any((existing) => existing.trackKey == track.trackKey)) {
          list.add(track);
        }
      }
    }

    _catalogCache = catalog;
    _battleCache = battle;
    _genreCache = _sortedTrackMap(genre);
    _artistCache = _sortedTrackMap(artist);
    _producerCache = _sortedTrackMap(producer);
    _battleArtistCache = _sortedTrackMap(battleArtist);
  }

  void _putArtist(
    Track track,
    Map<String, List<Track>> map,
    Map<String, String> labels,
  ) {
    for (final raw in track.artists) {
      final card = artistCardName(raw);
      final label = labels.putIfAbsent(card.toLowerCase(), () => card);
      final list = map.putIfAbsent(label, () => []);
      if (!list.any((existing) => existing.trackKey == track.trackKey)) {
        list.add(track);
      }
    }
  }

  Map<String, List<Track>> _sortedTrackMap(Map<String, List<Track>> map) {
    final keys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final key in keys) key: map[key]!};
  }

  /// Library without Battle-Rap. Main screens read this.
  List<Track> get catalogTracks {
    _ensureTrackSlices();
    return _catalogCache!;
  }

  /// Battle-Rap only. Shown on the Battles page.
  List<Track> get battleTracks {
    _ensureTrackSlices();
    return _battleCache!;
  }

  /// Named releases for the calendar. Rebuilt only when slices drop.
  List<ReleaseCalendarSection> releaseCalendar() {
    final cached = _calendarCache;
    if (cached != null) return cached;
    final sections = buildReleaseCalendar(
      catalogTracks,
      cardName: artistCardName,
    );
    _calendarCache = sections;
    return sections;
  }
  List<Playlist> get playlists => _playlists;
  bool get loading => _loading;
  bool get scanning => _scanning;
  ScanProgress? get scanProgress => _scanProgress;
  String? get lastScanMessage => _lastScanMessage;
  List<JobLogEntry> get jobLog => List.unmodifiable(_jobLog);
  /// Progress ticks for settings. Other screens do not listen to this.
  final jobUi = _JobUi();
  DateTime _jobPaintAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _paintJob({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_jobPaintAt) < const Duration(milliseconds: 400)) {
      return;
    }
    _jobPaintAt = now;
    jobUi.ping();
  }

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
    _trackKeyAlias.clear();
    await _syncMetaPlaylists();
    _playlists = await _db.getPlaylists();
    await _refreshMosaics();
    await _loadArtistAliases();
    _invalidateSearch();
    _error = null;
    notifyListeners();
  }

  Future<void> _loadArtistAliases() async {
    final artist = _aliasIndex(await _db.getArtistAliases());
    _aliasToCard = artist.toCard;
    _aliasLabelsByCard = artist.labels;
    final producer = _aliasIndex(await _db.getProducerAliases());
    _producerAliasToCard = producer.toCard;
    _producerAliasLabelsByCard = producer.labels;
  }

  ({Map<String, String> toCard, Map<String, List<String>> labels}) _aliasIndex(
    List<ArtistAlias> rows,
  ) {
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
    return (toCard: toCard, labels: labels);
  }

  String _cardName(String name, Map<String, String> toCard) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    return toCard[normalizeTag(trimmed)] ?? trimmed;
  }

  /// Name shown on the artist card. Track tags are not rewritten.
  String artistCardName(String artistName) => _cardName(artistName, _aliasToCard);

  /// Name shown on the producer card. Track tags are not rewritten.
  String producerCardName(String producerName) =>
      _cardName(producerName, _producerAliasToCard);

  List<String> aliasLabelsForCard(String cardName) {
    return _aliasLabelsByCard[normalizeTag(cardName)] ?? const [];
  }

  List<String> producerAliasLabelsForCard(String cardName) {
    return _producerAliasLabelsByCard[normalizeTag(cardName)] ?? const [];
  }

  bool artistCardMatchesQuery(String cardName, String query) {
    return _cardMatchesQuery(cardName, query, aliasLabelsForCard(cardName));
  }

  bool producerCardMatchesQuery(String cardName, String query) {
    return _cardMatchesQuery(
      cardName,
      query,
      producerAliasLabelsForCard(cardName),
    );
  }

  bool _cardMatchesQuery(String cardName, String query, List<String> aliases) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (cardName.toLowerCase().contains(q)) return true;
    for (final alias in aliases) {
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
    for (final name in producerNames(track.producer)) {
      final card = producerCardName(name);
      extra.write(' ');
      extra.write(card.toLowerCase());
      for (final alias in producerAliasLabelsForCard(card)) {
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
    _paintJob(force: true);
  }

  Future<void> scanLibrary({bool force = false, bool newOnly = false}) async {
    if (_scanning) return;
    _scanning = true;
    _cancelFill = false;
    _scanProgress = null;
    _lastScanMessage = null;
    _jobLog.clear();
    _paintJob(force: true);

    try {
      final result = await _scanner.scan(
        force: force,
        newOnly: newOnly,
        onProgress: (p) {
          _scanProgress = p;
          _paintJob();
        },
      );

      await reload();
      final modeLabel = force
          ? 'Полный перескан. '
          : newOnly
              ? 'Только новые файлы. '
              : '';
      if (result.cancelled) {
        _lastScanMessage =
            '$modeLabel'
            'Сканирование остановлено. '
            'Успели: новых ${result.added}, обновлено ${result.updated}, '
            'без изменений ${result.skipped}.';
      } else {
        _lastScanMessage =
            '$modeLabel'
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
      _paintJob(force: true);
    }
  }

  /// Writes the metadata lists and records what is still empty. Does not edit files.
  Future<void> reportEmptyMetadata() async {
    if (_scanning) return;
    _scanning = true;
    _cancelFill = false;
    _scanProgress = null;
    _lastScanMessage = null;
    _jobLog.clear();
    _paintJob(force: true);

    try {
      final tracks = [
        for (final track in _tracks)
          if (!track.isTrashed) track,
      ];
      final total = tracks.length;
      var processed = 0;
      var cancelled = false;
      var core = 0;
      var producers = 0;
      var genres = 0;
      var lyrics = 0;
      var ready = 0;
      for (final track in tracks) {
        if (_cancelFill) {
          cancelled = true;
          break;
        }
        processed++;
        final gaps = trackMetaGaps(track);
        if (gaps.genre) genres++;
        if (gaps.ready) {
          ready++;
        } else {
          if (gaps.core) core++;
          if (gaps.producer) producers++;
          if (gaps.lyrics) lyrics++;
        }
        if (processed == total || processed % 250 == 0) {
          _scanProgress = ScanProgress(
            processed: processed,
            total: total,
            added: ready,
            updated: core,
            skipped: 0,
            currentFile: track.displayTitle,
          );
          _paintJob();
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (!cancelled) {
        _scanProgress = ScanProgress(
          processed: total,
          total: total,
          added: ready,
          updated: core,
          skipped: 0,
          currentFile: 'Сохраняем списки…',
        );
        _paintJob(force: true);
        await _syncMetaPlaylists();
        _playlists = await _db.getPlaylists();
      }
      final summary =
          '${Playlist.missingMetadataName}: $core. '
          '${Playlist.missingProducerName}: $producers. '
          '${Playlist.missingGenreName}: $genres. '
          '${Playlist.missingLyricsName}: $lyrics. '
          '${Playlist.metadataReadyName}: $ready.';
      if (cancelled) {
        _lastScanMessage = 'Поиск остановлен. $summary';
      } else {
        _lastScanMessage = summary;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      _lastScanMessage = 'Ошибка поиска метаданных: $e';
    } finally {
      _scanning = false;
      _cancelFill = false;
      _scanProgress = null;
      _paintJob(force: true);
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
    _paintJob(force: true);

    try {
      final result = await _runMetadataPipeline();
      await reload();
      if (result.emptyCount == 0 && !result.cancelled) {
        _lastScanMessage =
            'Искать нечего: готовые файлы пропущены, у остальных эти поля уже заполнены.';
      } else if (result.cancelled) {
        _lastScanMessage =
            'Поиск метаданных остановлен. Проверено: ${result.scanned}. '
            'Найдено: ${result.found}. Записано: ${result.filled}.';
      } else {
        _lastScanMessage =
            'Проверено файлов, кроме «${Playlist.metadataReadyName}»: '
            '${result.emptyCount}. '
            'Найдено: ${result.found}. Записано: ${result.filled}.';
      }
    } catch (e) {
      _error = e.toString();
      _lastScanMessage = 'Ошибка поиска метаданных: $e';
    } finally {
      _scanning = false;
      _cancelFill = false;
      _scanProgress = null;
      _paintJob(force: true);
    }
  }

  /// Site lookup that writes only the producer, for «Без продюсера».
  Future<void> fillMissingProducers() async {
    if (_scanning) return;
    _scanning = true;
    _cancelFill = false;
    _scanProgress = null;
    _lastScanMessage = null;
    _jobLog.clear();
    _paintJob(force: true);

    try {
      final result = await _runMetadataPipeline(producersOnly: true);
      await reload();
      if (result.emptyCount == 0 && !result.cancelled) {
        _lastScanMessage =
            'Искать нечего: готовые файлы пропущены, у остальных продюсер уже указан.';
      } else if (result.cancelled) {
        _lastScanMessage =
            'Поиск продюсеров остановлен. Проверено: ${result.scanned}. '
            'Найдено: ${result.found}. Записано: ${result.filled}.';
      } else {
        _lastScanMessage =
            'Проверено файлов, кроме «${Playlist.metadataReadyName}»: '
            '${result.emptyCount}. '
            'Найдено: ${result.found}. Записано продюсеров: ${result.filled}.';
      }
    } catch (e) {
      _error = e.toString();
      _lastScanMessage = 'Ошибка поиска продюсеров: $e';
    } finally {
      _scanning = false;
      _cancelFill = false;
      _scanProgress = null;
      _paintJob(force: true);
    }
  }

  /// Rewrite titles and albums that end with a feat. or prod credit.
  Future<void> fixTitleCredits({
    void Function(Track updated, String oldTrackKey)? onUpdated,
  }) async {
    if (_scanning) return;
    _scanning = true;
    _cancelFill = false;
    _scanProgress = null;
    _lastScanMessage = null;
    _jobLog.clear();
    _paintJob(force: true);

    try {
      final tracks = await _db.getAllTracks(includeTrashed: true);
      final total = tracks.length;
      var changed = 0;
      var checked = 0;
      for (final track in tracks) {
        if (_cancelFill) break;
        checked++;
        final title = stripTrailingCredit(track.title);
        final album = stripTrailingCredit(track.album);
        final newTitle = title.isEmpty || title == track.title.trim()
            ? null
            : title;
        final newAlbum = album.isEmpty || album == track.album.trim()
            ? null
            : album;
        _scanProgress = ScanProgress(
          processed: checked,
          total: total,
          added: changed,
          updated: 0,
          skipped: checked - changed,
          currentFile: '${track.displayArtist} — ${track.displayTitle}',
        );
        if (newTitle == null && newAlbum == null) {
          if (checked == total || checked % 200 == 0) {
            _paintJob();
            await Future<void>.delayed(Duration.zero);
          }
          continue;
        }
        final draft = MetadataDraft.fromTrack(track);
        if (newTitle != null) draft.title = newTitle;
        if (newAlbum != null) draft.album = newAlbum;
        try {
          final updated = await saveTrackMetadata(
            track,
            draft,
            refreshLibrary: false,
            notify: false,
          );
          onUpdated?.call(updated, track.trackKey);
          _pushJobLog(
            JobLogEntry(
              artist: track.displayArtist,
              title: newTitle ?? track.displayTitle,
              fields: [
                if (newTitle != null) JobLogField('Название', newTitle),
                if (newAlbum != null) JobLogField('Альбом', newAlbum),
              ],
              ok: true,
              at: DateTime.now(),
            ),
          );
          changed++;
        } catch (e, st) {
          debugPrint('title fix ${track.trackKey}: $e\n$st');
          _pushJobLog(
            JobLogEntry(
              artist: track.displayArtist,
              title: track.displayTitle,
              fields: const [],
              ok: false,
              at: DateTime.now(),
              error: '$e',
            ),
          );
        }
        _paintJob(force: true);
        await Future<void>.delayed(Duration.zero);
      }
      await reload();
      if (_cancelFill) {
        _lastScanMessage = 'Правка названий остановлена. Исправлено: $changed.';
      } else if (changed == 0) {
        _lastScanMessage = 'Лишних feat. и prod в названиях нет.';
      } else {
        _lastScanMessage = 'Исправлено названий: $changed.';
      }
    } catch (e) {
      _error = e.toString();
      _lastScanMessage = 'Ошибка правки названий: $e';
    } finally {
      _scanning = false;
      _cancelFill = false;
      _scanProgress = null;
      _paintJob(force: true);
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
    _paintJob(force: true);

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
      _paintJob(force: true);
    }
  }

  /// Site lookup and file write run at the same time.
  /// Every library file is queued, except tracks already in «Метаданные готовы».
  /// Writing starts as soon as a lookup returns.
  Future<
      ({
        int scanned,
        int emptyCount,
        int found,
        int filled,
        bool cancelled,
      })> _runMetadataPipeline({bool producersOnly = false}) async {
    final tracks = <Track>[];
    var walked = 0;
    for (final track in _tracks) {
      if (_cancelFill) break;
      if (track.isTrashed ||
          track.isBattle ||
          trackMetaGaps(track).ready) {
        continue;
      }
      walked++;
      if (_metadataSearchNeeded(track, producersOnly: producersOnly)) {
        tracks.add(track);
      }
      if (walked % 250 == 0) {
        _scanProgress = ScanProgress(
          processed: walked,
          total: _tracks.length,
          added: 0,
          updated: tracks.length,
          skipped: walked - tracks.length,
          currentFile: 'Отбираем файлы…',
        );
        _paintJob();
        await Future<void>.delayed(Duration.zero);
      }
    }
    final emptyLabel = Playlist.metadataReadyName;
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
            ? 'Все файлы в «$emptyLabel»'
            : 'К поиску: $total · проверено $searched · '
                'найдено $found · записано $written$tail',
      );
      _paintJob(force: force);
    }

    Future<void> searcher() async {
      while (!_cancelFill) {
        final track = await toSearch.take();
        if (track == null) return;
        detail = 'Ищем на сайте: ${_searchLabel(track)}';
        publish();
        final prepared = producersOnly
            ? await _lookupProducer(track)
            : await _lookupMetadata(track);
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
        publish();
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
        publish();
      }
    }

    final searchJobs = List.generate(3, (_) => searcher());
    final writeJob = writer();
    emptyCount = total;
    try {
      for (final track in tracks) {
        if (_cancelFill) break;
        scanned++;
        toSearch.add(track);
        if (scanned % 200 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
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

  Future<({MetadataDraft draft, JobLogEntry entry})?> _lookupProducer(
    Track track,
  ) async {
    if (!isBlankMeta(track.producer) || !_canSearchMetadata(track)) {
      return null;
    }
    final hit = await _metaLookup.lookup(
      artist: track.artist,
      title: track.title,
      note: track.displayNote,
    );
    final producer = hit?.producer?.trim();
    if (isBlankMeta(producer)) return null;
    final draft = MetadataDraft.fromTrack(track)..producer = producer;
    return (
      draft: draft,
      entry: _metaLogEntry(track, producer: producer),
    );
  }

  bool _metadataSearchNeeded(Track track, {required bool producersOnly}) {
    if (!_canSearchMetadata(track)) return false;
    if (producersOnly) return isBlankMeta(track.producer);
    final album = track.album.trim().toLowerCase();
    final albumMissing = album.isEmpty ||
        album == 'unknown' ||
        album == 'мне нравится' ||
        album == 'мне нужен ui';
    return albumMissing ||
        MetaLookupService.albumArtistMissing(track.albumArtist) ||
        track.year == null ||
        track.year! < 1000 ||
        track.trackNumber == null ||
        track.trackNumber! < 1 ||
        track.trackTotal == null ||
        track.trackTotal! < 1 ||
        track.discNumber == null ||
        track.discNumber! < 1 ||
        isBlankMeta(track.producer);
  }

  String _searchLabel(Track track) {
    final note = track.displayNote;
    final base = '${track.displayArtist} — ${track.displayTitle}';
    return note == null ? base : '$base $note';
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
    final needAlbum = track.album.trim().isEmpty ||
        const {'unknown', 'мне нравится', 'мне нужен ui'}
            .contains(track.album.trim().toLowerCase());
    final needAlbumArtist =
        MetaLookupService.albumArtistMissing(track.albumArtist);
    final needYear = track.year == null || track.year! < 1000;
    final needTrackNo = track.trackNumber == null || track.trackNumber! < 1;
    final needTrackTotal = track.trackTotal == null || track.trackTotal! < 1;
    final needDisc = track.discNumber == null || track.discNumber! < 1;
    final needProducer = isBlankMeta(track.producer);
    if (!needAlbum &&
        !needAlbumArtist &&
        !needYear &&
        !needTrackNo &&
        !needTrackTotal &&
        !needDisc &&
        !needProducer) {
      return null;
    }
    if (!_canSearchMetadata(track)) return null;

    final hit = await _metaLookup.lookup(
      artist: track.artist,
      title: track.title,
      note: track.displayNote,
    );

    final newAlbum = (hit != null &&
            needAlbum &&
            hit.album != null &&
            hit.album!.isNotEmpty)
        ? MetaLookupService.cleanAlbum(hit.album!)
        : track.album;
    var newAlbumArtist = (hit != null &&
            needAlbumArtist &&
            hit.albumArtist != null &&
            hit.albumArtist!.trim().isNotEmpty)
        ? formatArtists(hit.albumArtist)
        : track.albumArtist;
    final newYear =
        (hit != null && needYear && hit.year != null) ? hit.year : track.year;
    final newTrackNo = (hit != null && needTrackNo && hit.trackNumber != null)
        ? hit.trackNumber
        : track.trackNumber;
    final newTrackTotal =
        (hit != null && needTrackTotal && hit.trackTotal != null)
            ? hit.trackTotal
            : track.trackTotal;
    final newDisc = (hit != null && needDisc && hit.discNumber != null)
        ? hit.discNumber
        : track.discNumber;
    final newProducer = (hit != null &&
            needProducer &&
            hit.producer != null &&
            hit.producer!.trim().isNotEmpty)
        ? hit.producer!.trim()
        : track.producer;
    if (needAlbumArtist &&
        MetaLookupService.albumArtistMissing(newAlbumArtist) &&
        newTrackTotal == 1) {
      final copied = storedArtists(track.artist);
      if (!isBlankMeta(copied)) newAlbumArtist = copied;
    }
    if (hit == null && newAlbumArtist == track.albumArtist) return null;

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
        currentFile: 'Ищем текст: ${_searchLabel(track)}',
      );
      _paintJob();
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
        _paintJob();
      } catch (e, st) {
        debugPrint('lyrics tag write ${track.trackKey}: $e\n$st');
        try {
          await _db.updateTrackLyrics(track.trackKey, text);
          final updated = track.copyWith(lyrics: text);
          final index =
              _tracks.indexWhere((t) => t.trackKey == track.trackKey);
          if (index >= 0) _tracks[index] = updated;
          _invalidateSearch();
          _pushJobLog(entry);
          filled++;
          _paintJob();
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
          _paintJob();
        }
      }
    }
    return (filled: filled, cancelled: false);
  }

  void _pushJobLog(JobLogEntry entry) {
    _jobLog.add(entry);
    if (_jobLog.length > 80) {
      _jobLog.removeRange(0, _jobLog.length - 80);
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
    _ensureTrackSlices();
    return _genreCache!;
  }

  /// One track can appear under several artists ("A, B" → A and B).
  Map<String, List<Track>> tracksByArtist() {
    _ensureTrackSlices();
    return _artistCache!;
  }

  Map<String, List<Track>> tracksByProducer() {
    _ensureTrackSlices();
    return _producerCache!;
  }

  /// Battle-Rap tracks grouped by artist card. Same lifetime as [battleTracks].
  Map<String, List<Track>> battleTracksByArtist() {
    _ensureTrackSlices();
    return _battleArtistCache!;
  }

  /// Tracks whose producer tag is empty. They have no producer card.
  List<Track> tracksWithoutProducer() {
    final list = _tracks
        .where((track) => producerNames(track.producer).isEmpty)
        .toList();
    list.sort((a, b) {
      final byArtist = a.displayArtist.toLowerCase().compareTo(
            b.displayArtist.toLowerCase(),
          );
      if (byArtist != 0) return byArtist;
      return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
    });
    return list;
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

  /// Home search: each list is empty when nothing in that category matched.
  ///
  /// The catalog is indexed once per library change. A keystroke only scans
  /// those prepared strings. Lyrics are checked for words of 3+ letters, so a
  /// single character does not walk every lyric.
  CatalogSearch searchCatalog(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return CatalogSearch.empty;
    if (normalized == _catalogQuery && _catalogHit != null && _catalogIndex != null) {
      return _catalogHit!;
    }

    final tokens = normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final index = _ensureCatalogIndex();
    final tracks = <Track>[];
    for (final row in index.tracks) {
      if (_rowHits(row.meta, row.lyrics, tokens)) tracks.add(row.track);
    }
    final artists = <SearchPerson>[
      for (final row in index.artists)
        if (_hayHits(row.hay, tokens))
          SearchPerson(name: row.name, trackCount: row.trackCount),
    ];
    final producers = <SearchPerson>[
      for (final row in index.producers)
        if (_hayHits(row.hay, tokens))
          SearchPerson(name: row.name, trackCount: row.trackCount),
    ];
    final albums = <SearchAlbum>[
      for (final row in index.albums)
        if (_hayHits(row.hay, tokens)) row.album,
    ];
    final playlists = <Playlist>[
      for (final row in index.playlists)
        if (_hayHits(row.hay, tokens)) row.playlist,
    ];
    final hit = CatalogSearch(
      tracks: tracks,
      artists: artists,
      producers: producers,
      albums: albums,
      playlists: playlists,
    );
    _catalogQuery = normalized;
    _catalogHit = hit;
    return hit;
  }

  void _invalidateSearch() {
    _catalogIndex = null;
    _catalogQuery = null;
    _catalogHit = null;
    _dropSlices();
  }

  _CatalogIndex _ensureCatalogIndex() {
    final cached = _catalogIndex;
    if (cached != null) return cached;

    final artistCounts = <String, int>{};
    final artistLabels = <String, String>{};
    final producerCounts = <String, int>{};
    final producerLabels = <String, String>{};
    final albumGroups = <String, List<Track>>{};
    final albumTitle = <String, String>{};
    final albumArtist = <String, String>{};
    final tracks = <_IxTrack>[];

    for (final track in _tracks) {
      if (track.isBattle) continue;
      final lyrics = track.lyrics?.trim();
      tracks.add(
        _IxTrack(
          track,
          _metaHay(track),
          lyrics == null || lyrics.isEmpty ? '' : lyrics.toLowerCase(),
        ),
      );
      _tallyPeople(track.artists, artistCounts, artistLabels);
      _tallyPeople(
        producerNames(track.producer),
        producerCounts,
        producerLabels,
        cardOf: producerCardName,
      );

      final album = track.displayAlbum.trim();
      if (album.isEmpty || album.toLowerCase() == 'unknown') continue;
      final artist = (track.albumArtist != null &&
              track.albumArtist!.trim().isNotEmpty)
          ? track.albumArtist!.trim()
          : track.displayArtist;
      final key = '${artist.toLowerCase()}\u0001${album.toLowerCase()}';
      albumGroups.putIfAbsent(key, () => []).add(track);
      albumTitle.putIfAbsent(key, () => album);
      albumArtist.putIfAbsent(key, () => artist);
    }

    final albums = <_IxAlbum>[];
    for (final entry in albumGroups.entries) {
      final list = entry.value;
      list.sort((a, b) {
        final byNumber = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
        if (byNumber != 0) return byNumber;
        return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
      });
      final title = albumTitle[entry.key]!;
      final artist = albumArtist[entry.key]!;
      final years = list.map((t) => t.year).whereType<int>();
      String? cover;
      for (final track in list) {
        final path = track.coverPath;
        if (path != null && path.isNotEmpty) {
          cover = path;
          break;
        }
      }
      int? year;
      for (final value in years) {
        if (year == null || value > year) year = value;
      }
      albums.add(
        _IxAlbum(
          SearchAlbum(
            artist: artist,
            release: ArtistRelease(
              title: title,
              tracks: list,
              kind: releaseKindForTracks(list),
              year: year,
              coverPath: cover,
            ),
          ),
          _albumHay(title, artist),
        ),
      );
    }
    albums.sort((a, b) {
      final byTitle = a.album.release.title.toLowerCase().compareTo(
            b.album.release.title.toLowerCase(),
          );
      if (byTitle != 0) return byTitle;
      return a.album.artist.toLowerCase().compareTo(b.album.artist.toLowerCase());
    });

    final playlists = [
      for (final playlist in _playlists)
        _IxPlaylist(playlist, playlist.name.toLowerCase()),
    ]..sort(
        (a, b) => a.hay.compareTo(b.hay),
      );

    final built = _CatalogIndex(
      tracks: tracks,
      artists: _indexedPeople(artistCounts, artistLabels),
      producers: _indexedPeople(
        producerCounts,
        producerLabels,
        producer: true,
      ),
      albums: albums,
      playlists: playlists,
    );
    _catalogIndex = built;
    return built;
  }

  void _tallyPeople(
    List<String> names,
    Map<String, int> counts,
    Map<String, String> labels, {
    String Function(String name)? cardOf,
  }) {
    final resolve = cardOf ?? artistCardName;
    final seen = <String>{};
    for (final rawName in names) {
      final card = resolve(rawName);
      final key = card.toLowerCase();
      if (key.isEmpty || key == 'unknown' || !seen.add(key)) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      labels.putIfAbsent(key, () => card);
    }
  }

  List<_IxPerson> _indexedPeople(
    Map<String, int> counts,
    Map<String, String> labels, {
    bool producer = false,
  }) {
    final people = [
      for (final entry in counts.entries)
        _IxPerson(
          labels[entry.key] ?? entry.key,
          _personHay(labels[entry.key] ?? entry.key, producer: producer),
          entry.value,
        ),
    ]..sort((a, b) => a.hay.compareTo(b.hay));
    return people;
  }

  String _personHay(String card, {bool producer = false}) {
    final buf = StringBuffer(card.toLowerCase());
    final aliases = producer
        ? producerAliasLabelsForCard(card)
        : aliasLabelsForCard(card);
    for (final alias in aliases) {
      buf.write(' ');
      buf.write(alias.toLowerCase());
    }
    return buf.toString();
  }

  String _albumHay(String title, String artist) {
    final buf = StringBuffer()
      ..write(title.toLowerCase())
      ..write(' ')
      ..write(artist.toLowerCase());
    if (artist.trim().isEmpty) return buf.toString();
    for (final name in splitArtists(artist)) {
      final card = artistCardName(name);
      buf.write(' ');
      buf.write(card.toLowerCase());
      for (final alias in aliasLabelsForCard(card)) {
        buf.write(' ');
        buf.write(alias.toLowerCase());
      }
    }
    return buf.toString();
  }

  String _metaHay(Track track) {
    final buf = StringBuffer();
    void add(String? value) {
      if (isBlankMeta(value)) return;
      buf
        ..write(value)
        ..write(' ');
    }

    add(track.title);
    add(track.artist);
    add(track.albumArtist);
    add(track.producer);
    add(track.album);
    add(track.genre);
    if (track.year != null) add('${track.year}');
    for (final path in track.filePaths) {
      add(p.basenameWithoutExtension(path));
    }

    final seen = <String>{};
    void addName(
      String raw,
      String Function(String) cardOf,
      List<String> Function(String) aliasesOf,
    ) {
      final card = cardOf(raw);
      final key = card.toLowerCase();
      if (key.isEmpty || key == 'unknown' || !seen.add(key)) return;
      add(card);
      for (final alias in aliasesOf(card)) {
        add(alias);
      }
    }

    for (final name in track.artists) {
      addName(name, artistCardName, aliasLabelsForCard);
    }
    final albumArtist = track.albumArtist;
    if (albumArtist != null && albumArtist.trim().isNotEmpty) {
      for (final name in splitArtists(albumArtist)) {
        addName(name, artistCardName, aliasLabelsForCard);
      }
    }
    for (final name in producerNames(track.producer)) {
      addName(name, producerCardName, producerAliasLabelsForCard);
    }
    return buf.toString().toLowerCase();
  }

  bool _hayHits(String hay, List<String> tokens) {
    for (final token in tokens) {
      if (!hay.contains(token)) return false;
    }
    return true;
  }

  bool _rowHits(String meta, String lyrics, List<String> tokens) {
    for (final token in tokens) {
      if (meta.contains(token)) continue;
      if (token.length >= 3 && lyrics.isNotEmpty && lyrics.contains(token)) {
        continue;
      }
      return false;
    }
    return true;
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
        _invalidateSearch();
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

  /// The library copy of [track] after a metadata edit, including a new key.
  Track resolveTrack(Track track) {
    final byKey = trackByKey(track.trackKey);
    if (byKey != null) return byKey;
    final path = track.primaryPath;
    if (path == null) return track;
    for (final candidate in _tracks) {
      if (candidate.filePaths.contains(path)) return candidate;
    }
    return track;
  }

  Future<void> _evictCover(String? path) async {
    if (path == null || path.isEmpty) return;
    forgetCoverFingerprint(path);
    try {
      await FileImage(File(path)).evict();
    } catch (_) {}
  }

  void _replaceTrack(String oldKey, Track updated) {
    final next = <Track>[];
    var placed = false;
    for (final track in _tracks) {
      if (track.trackKey == oldKey || track.trackKey == updated.trackKey) {
        if (!placed) {
          next.add(updated);
          placed = true;
        }
        continue;
      }
      next.add(track);
    }
    if (!placed) next.add(updated);
    _tracks = next;
    _dropSlices();
    if (oldKey == updated.trackKey) return;
    _trackKeyAlias[oldKey] = updated.trackKey;
    final rewired = <String, String>{};
    for (final entry in _trackKeyAlias.entries) {
      rewired[entry.key] =
          entry.value == oldKey ? updated.trackKey : entry.value;
    }
    _trackKeyAlias
      ..clear()
      ..addAll(rewired);
  }

  /// Play count after a metadata edit changed the track key.
  int playCountFor(Map<String, int> counts, String trackKey) {
    final direct = counts[trackKey];
    if (direct != null) return direct;
    var best = 0;
    var found = false;
    for (final entry in _trackKeyAlias.entries) {
      if (entry.value != trackKey) continue;
      final value = counts[entry.key];
      if (value == null) continue;
      found = true;
      if (value > best) best = value;
    }
    return found ? best : 0;
  }

  /// One UI refresh after a track edit or a finished album batch.
  ///
  /// The editor covers the shell, so a notify during the save can miss the
  /// page underneath. A second notify after the next frame reaches it once
  /// the editor has closed.
  Future<void> publishMetadata() async {
    await _refreshMosaics();
    _invalidateSearch();
    notifyListeners();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
    unawaited(_syncMetaPlaylists());
  }

  /// Set [refreshLibrary] to false during batch autofill — publishing the
  /// library after every file rebuilds every open screen.
  Future<Track> saveTrackMetadata(
    Track track,
    MetadataDraft draft, {
    bool refreshLibrary = true,
    bool notify = true,
  }) async {
    final oldKey = track.trackKey;
    final updated = await MetadataWriter.write(
      track,
      draft,
      paths: _paths,
    );
    await _db.applyMetadataEdit(oldTrackKey: oldKey, updated: updated);
    await _evictCover(track.coverPath);
    await _evictCover(updated.coverPath);
    _replaceTrack(oldKey, updated);
    if (refreshLibrary) {
      await publishMetadata();
    } else if (notify) {
      _invalidateSearch();
      notifyListeners();
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

  /// Moves every track from a user playlist into another, then deletes the source.
  Future<void> movePlaylistTracks({
    required int fromId,
    required int toId,
  }) async {
    final source = playlistById(fromId);
    final target = playlistById(toId);
    if (source == null || target == null) return;
    if (source.isSystem || target.isSystem || source.id == target.id) return;
    await _db.movePlaylistTracks(fromId: fromId, toId: toId);
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

  String? releaseCoverTrackKey(ArtistRelease release) {
    return _settings.releaseCoverTrackKey(releaseCoverKey(release));
  }

  /// Chosen track cover for an album, EP, or single. Falls back to the first cover.
  String? releaseCover(ArtistRelease release) {
    final preferred = _settings.releaseCoverTrackKey(releaseCoverKey(release));
    final chosen = coverFromTracks(
      release.tracks,
      preferredTrackKey: preferred,
    );
    if (chosen != null && File(chosen).existsSync()) return chosen;
    for (final track in release.tracks) {
      final path = track.coverPath;
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        return path;
      }
    }
    return chosen;
  }

  Future<void> setReleaseCover(ArtistRelease release, String trackKey) async {
    await _settings.setReleaseCoverTrackKey(releaseCoverKey(release), trackKey);
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
    await _movePersonPhoto(from: b, into: a);
    await reload();
  }

  /// Merge [from] into [into] on the producer card. MP3 tags stay as written.
  Future<void> mergeProducers({
    required String into,
    required String from,
  }) async {
    final a = into.trim();
    final b = from.trim();
    if (a.isEmpty || b.isEmpty) return;
    if (a.toLowerCase() == b.toLowerCase()) return;

    await _db.upsertProducerAlias(fromDisplay: b, toDisplay: a);
    await _movePersonPhoto(from: b, into: a);
    await reload();
  }

  Future<void> _movePersonPhoto({
    required String from,
    required String into,
  }) async {
    final fromPhoto = _settings.artistPhotoPath(from);
    final intoPhoto = _settings.artistPhotoPath(into);
    if (intoPhoto == null && fromPhoto != null) {
      await _settings.setArtistPhotoPath(
        into,
        fromPhoto,
        manual: _settings.isArtistPhotoManual(from),
      );
    }
    await _settings.setArtistPhotoPath(from, null);
  }

  /// Genius → Deezer portraits for library artists (skips manual picks).
  /// Returns how many photos were written.
  Future<int> refreshArtistPhotos() async {
    if (_artistPhotosRefreshing || _tracks.isEmpty) return 0;
    _artistPhotosRefreshing = true;
    _artistPhotoProgress = const ArtistPhotoProgress(done: 0, total: 0);
    _paintJob(force: true);
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
      _paintJob(force: true);

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
            _paintJob();
          }
        }));
      }
      return updated;
    } finally {
      _artistPhotosRefreshing = false;
      _artistPhotoProgress = null;
      notifyListeners();
      _paintJob(force: true);
    }
  }

  /// Tracks for a metadata system playlist, or null for any other playlist.
  List<Track>? metaPlaylistTracks(Playlist playlist) {
    final pick = switch (playlist.systemKind) {
      Playlist.kindIncomplete => (TrackMetaGaps gaps) => gaps.core,
      Playlist.kindNoProducer => (TrackMetaGaps gaps) => gaps.producer,
      Playlist.kindMissingGenre => (TrackMetaGaps gaps) => gaps.genre,
      Playlist.kindMissingLyrics => (TrackMetaGaps gaps) => gaps.lyrics,
      Playlist.kindMetadataReady => (TrackMetaGaps gaps) => gaps.ready,
      _ => null,
    };
    if (pick == null) return null;
    final list = <Track>[
      for (final track in _tracks)
        if (!track.isTrashed && !track.isBattle && pick(trackMetaGaps(track)))
          track,
    ];
    list.sort(_byArtistTitle);
    return list;
  }

  /// Tracks still missing cover, title, artist, album fields, or disc.
  List<Track> tracksMissingMetadata() {
    final list = <Track>[
      for (final track in _tracks)
        if (!track.isTrashed &&
            !track.isBattle &&
            trackMetaGaps(track).core)
          track,
    ];
    list.sort(_byArtistTitle);
    return list;
  }

  static int _byArtistTitle(Track a, Track b) {
    final byArtist = a.displayArtist.toLowerCase().compareTo(
          b.displayArtist.toLowerCase(),
        );
    if (byArtist != 0) return byArtist;
    return a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        );
  }

  Future<void> _syncMetaPlaylists() async {
    final groups = <String, List<Track>>{
      Playlist.kindIncomplete: [],
      Playlist.kindNoProducer: [],
      Playlist.kindMissingGenre: [],
      Playlist.kindMissingLyrics: [],
      Playlist.kindMetadataReady: [],
    };
    var seen = 0;
    for (final track in _tracks) {
      if (track.isTrashed || track.isBattle) continue;
      final gaps = trackMetaGaps(track);
      if (gaps.genre) groups[Playlist.kindMissingGenre]!.add(track);
      if (gaps.ready) {
        groups[Playlist.kindMetadataReady]!.add(track);
      } else {
        if (gaps.core) groups[Playlist.kindIncomplete]!.add(track);
        if (gaps.producer) groups[Playlist.kindNoProducer]!.add(track);
        if (gaps.lyrics) groups[Playlist.kindMissingLyrics]!.add(track);
      }
      seen++;
      if (seen % 400 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    const specs = <(String, String, String)>[
      (
        Playlist.kindIncomplete,
        Playlist.missingMetadataName,
        Playlist.missingMetadataDescription,
      ),
      (
        Playlist.kindNoProducer,
        Playlist.missingProducerName,
        Playlist.missingProducerDescription,
      ),
      (
        Playlist.kindMissingGenre,
        Playlist.missingGenreName,
        Playlist.missingGenreDescription,
      ),
      (
        Playlist.kindMissingLyrics,
        Playlist.missingLyricsName,
        Playlist.missingLyricsDescription,
      ),
      (
        Playlist.kindMetadataReady,
        Playlist.metadataReadyName,
        Playlist.metadataReadyDescription,
      ),
    ];
    for (final spec in specs) {
      final tracks = groups[spec.$1]!;
      tracks.sort(_byArtistTitle);
      await _db.syncSystemPlaylistMembership(
        systemKind: spec.$1,
        name: spec.$2,
        description: spec.$3,
        trackKeys: [for (final track in tracks) track.trackKey],
      );
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void dispose() {
    jobUi.dispose();
    super.dispose();
  }

  /// Stable random covers for a user playlist that has no chosen cover.
  List<String> playlistMosaic(int playlistId) =>
      _mosaicCache[playlistId] ?? const [];

  /// Covers for a genre card. One path, or four cells.
  List<String> genreMosaic(String genre) =>
      _genreMosaicCache[genre] ?? const [];

  final Map<String, List<String>> _genreMosaicCache = {};
  final Map<int, String> _playlistMosaicSig = {};
  final Map<String, String> _genreMosaicSig = {};

  String _coverSetSig(Iterable<String?> paths) {
    final buf = StringBuffer();
    for (final path in paths) {
      if (path == null || path.isEmpty) continue;
      buf
        ..write(path)
        ..write('#')
        ..write(cachedCoverFingerprint(path) ?? '?')
        ..write('\u0001');
    }
    return buf.toString();
  }

  Future<void> _refreshMosaics() async {
    final next = <int, List<String>>{};
    final nextPlaylistSig = <int, String>{};
    final byKey = {for (final track in _tracks) track.trackKey: track};
    var stepped = 0;
    for (final playlist in _playlists) {
      if (playlist.isSystem) continue;
      final cover = playlist.coverPath;
      if (cover != null && cover.isNotEmpty) continue;
      final keys = await _db.getPlaylistTrackKeys(playlist.id);
      final covers = [
        for (final key in keys)
          if (byKey[key]?.isBattle != true) byKey[key]?.coverPath,
      ];
      final known = _coverSetSig(covers);
      final previous = _mosaicCache[playlist.id];
      if (!known.contains('?') &&
          known == _playlistMosaicSig[playlist.id] &&
          previous != null) {
        next[playlist.id] = previous;
        nextPlaylistSig[playlist.id] = known;
      } else {
        next[playlist.id] = pickPlaylistMosaic(
          covers,
          seed: playlist.id,
          identity: coverFingerprint,
        );
        nextPlaylistSig[playlist.id] = _coverSetSig(covers);
        stepped++;
        if (stepped % 8 == 0) await Future<void>.delayed(Duration.zero);
      }
    }
    _mosaicCache = next;
    _playlistMosaicSig
      ..clear()
      ..addAll(nextPlaylistSig);

    final byGenre = <String, List<String?>>{};
    var walked = 0;
    for (final track in _tracks) {
      if (track.isBattle) continue;
      final genre = track.displayGenre;
      if (genre.isEmpty) continue;
      byGenre.putIfAbsent(genre, () => []).add(track.coverPath);
      walked++;
      if (walked % 400 == 0) await Future<void>.delayed(Duration.zero);
    }
    final genres = <String, List<String>>{};
    final nextGenreSig = <String, String>{};
    for (final entry in byGenre.entries) {
      final known = _coverSetSig(entry.value);
      final previous = _genreMosaicCache[entry.key];
      if (!known.contains('?') &&
          known == _genreMosaicSig[entry.key] &&
          previous != null) {
        genres[entry.key] = previous;
        nextGenreSig[entry.key] = known;
        continue;
      }
      genres[entry.key] = pickPlaylistMosaic(
        entry.value,
        seed: stableSeed(entry.key),
        identity: coverFingerprint,
      );
      nextGenreSig[entry.key] = _coverSetSig(entry.value);
      stepped++;
      if (stepped % 8 == 0) await Future<void>.delayed(Duration.zero);
    }
    _genreMosaicCache
      ..clear()
      ..addAll(genres);
    _genreMosaicSig
      ..clear()
      ..addAll(nextGenreSig);
  }

  Future<List<Track>> playlistTracks(int id) async {
    final playlist = playlistById(id);
    if (playlist != null) {
      final live = metaPlaylistTracks(playlist);
      if (live != null) return live;
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

class _CatalogIndex {
  const _CatalogIndex({
    required this.tracks,
    required this.artists,
    required this.producers,
    required this.albums,
    required this.playlists,
  });

  final List<_IxTrack> tracks;
  final List<_IxPerson> artists;
  final List<_IxPerson> producers;
  final List<_IxAlbum> albums;
  final List<_IxPlaylist> playlists;
}

class _IxTrack {
  const _IxTrack(this.track, this.meta, this.lyrics);

  final Track track;
  final String meta;
  final String lyrics;
}

class _IxPerson {
  const _IxPerson(this.name, this.hay, this.trackCount);

  final String name;
  final String hay;
  final int trackCount;
}

class _IxAlbum {
  const _IxAlbum(this.album, this.hay);

  final SearchAlbum album;
  final String hay;
}

class _IxPlaylist {
  const _IxPlaylist(this.playlist, this.hay);

  final Playlist playlist;
  final String hay;
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

class _JobUi extends ChangeNotifier {
  void ping() => notifyListeners();
}
