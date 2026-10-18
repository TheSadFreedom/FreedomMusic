import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _scanOnStartupKey = 'scan_on_startup';
  static const _playOnStartupKey = 'play_on_startup';
  static const _autoFillMetaKey = 'auto_fill_empty_metadata';
  static const _playerVolumeKey = 'player_volume';
  static const _playerVolumeBeforeMuteKey = 'player_volume_before_mute';
  static const _crossfadeSecondsKey = 'crossfade_seconds';
  static const _playbackQueueKey = 'playback_queue_keys';
  static const _playbackIndexKey = 'playback_index';
  static const _playbackPositionKey = 'playback_position_ms';
  static const _playbackShuffleKey = 'playback_shuffle';
  static const _playbackRepeatKey = 'playback_repeat';
  static const _artistTagsRestoredKey = 'artist_tags_restored_v1';
  static const _artistPhotoPrefix = 'artist_photo_';
  static const _artistPhotoManualPrefix = 'artist_photo_manual_';
  static const _releaseCoverPrefix = 'release_cover_';

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  bool get artistTagsRestored =>
      _prefs.getBool(_artistTagsRestoredKey) ?? false;

  Future<void> setArtistTagsRestored() async {
    await _prefs.setBool(_artistTagsRestoredKey, true);
  }

  bool get scanOnStartup => _prefs.getBool(_scanOnStartupKey) ?? false;

  Future<void> setScanOnStartup(bool value) async {
    await _prefs.setBool(_scanOnStartupKey, value);
    notifyListeners();
  }

  /// Resume the last track on launch, or start a random stream when there
  /// was no queue.
  bool get playOnStartup => _prefs.getBool(_playOnStartupKey) ?? false;

  Future<void> setPlayOnStartup(bool value) async {
    await _prefs.setBool(_playOnStartupKey, value);
    notifyListeners();
  }

  /// Fill empty album/genre/year from the internet when new tracks are scanned.
  bool get autoFillEmptyMetadata =>
      _prefs.getBool(_autoFillMetaKey) ?? true;

  Future<void> setAutoFillEmptyMetadata(bool value) async {
    await _prefs.setBool(_autoFillMetaKey, value);
    notifyListeners();
  }

  /// Last playback volume (0..1), restored on launch.
  double get playerVolume =>
      (_prefs.getDouble(_playerVolumeKey) ?? 1.0).clamp(0.0, 1.0);

  double get playerVolumeBeforeMute =>
      (_prefs.getDouble(_playerVolumeBeforeMuteKey) ?? playerVolume)
          .clamp(0.0, 1.0);

  Future<void> setPlayerVolume(double volume, {double? beforeMute}) async {
    await _prefs.setDouble(_playerVolumeKey, volume.clamp(0.0, 1.0));
    if (beforeMute != null) {
      await _prefs.setDouble(
        _playerVolumeBeforeMuteKey,
        beforeMute.clamp(0.0, 1.0),
      );
    }
  }

  /// Crossfade length in seconds (0 = off).
  int get crossfadeSeconds =>
      (_prefs.getInt(_crossfadeSecondsKey) ?? 3).clamp(0, 12);

  Future<void> setCrossfadeSeconds(int seconds) async {
    await _prefs.setInt(_crossfadeSecondsKey, seconds.clamp(0, 12));
    notifyListeners();
  }

  List<String> get playbackQueueKeys =>
      _prefs.getStringList(_playbackQueueKey) ?? const [];

  int get playbackIndex => _prefs.getInt(_playbackIndexKey) ?? 0;

  int get playbackPositionMs => _prefs.getInt(_playbackPositionKey) ?? 0;

  bool get playbackShuffle => _prefs.getBool(_playbackShuffleKey) ?? true;

  String get playbackRepeat => _prefs.getString(_playbackRepeatKey) ?? 'off';

  Future<void> savePlaybackSession({
    required List<String> queueKeys,
    required int index,
    required int positionMs,
    required bool shuffle,
    required String repeat,
  }) async {
    await _prefs.setStringList(_playbackQueueKey, queueKeys);
    await _prefs.setInt(_playbackIndexKey, index);
    await _prefs.setInt(_playbackPositionKey, positionMs);
    await _prefs.setBool(_playbackShuffleKey, shuffle);
    await _prefs.setString(_playbackRepeatKey, repeat);
  }

  Future<void> clearPlaybackSession() async {
    await _prefs.remove(_playbackQueueKey);
    await _prefs.remove(_playbackIndexKey);
    await _prefs.remove(_playbackPositionKey);
  }

  String _artistKey(String name) =>
      '$_artistPhotoPrefix${name.trim().toLowerCase()}';

  String _artistManualKey(String name) =>
      '$_artistPhotoManualPrefix${name.trim().toLowerCase()}';

  /// Custom artist photo path, if set.
  String? artistPhotoPath(String artistName) {
    final path = _prefs.getString(_artistKey(artistName));
    if (path == null || path.isEmpty) return null;
    return path;
  }

  /// True when the user picked the photo manually (skip auto-refresh).
  bool isArtistPhotoManual(String artistName) =>
      _prefs.getBool(_artistManualKey(artistName)) ?? false;

  Future<void> setArtistPhotoPath(
    String artistName,
    String? path, {
    bool? manual,
  }) async {
    final key = _artistKey(artistName);
    final manualKey = _artistManualKey(artistName);
    if (path == null || path.isEmpty) {
      await _prefs.remove(key);
      await _prefs.remove(manualKey);
    } else {
      await _prefs.setString(key, path);
      if (manual != null) {
        await _prefs.setBool(manualKey, manual);
      }
    }
    notifyListeners();
  }

  /// Track whose cover is shown for this album, EP, or single.
  String? releaseCoverTrackKey(String releaseKey) {
    final key = _prefs.getString('$_releaseCoverPrefix$releaseKey');
    if (key == null || key.isEmpty) return null;
    return key;
  }

  Future<void> setReleaseCoverTrackKey(String releaseKey, String trackKey) async {
    await _prefs.setString('$_releaseCoverPrefix$releaseKey', trackKey);
    notifyListeners();
  }

  /// Previous chart ranks: `trackKey -> 1-based rank`.
  Map<String, int> chartSnapshot(String periodKey) {
    final raw = _prefs.getStringList('chart_snap_$periodKey') ?? const [];
    final map = <String, int>{};
    for (final line in raw) {
      final i = line.lastIndexOf('|');
      if (i <= 0) continue;
      final key = line.substring(0, i);
      final rank = int.tryParse(line.substring(i + 1));
      if (rank != null) map[key] = rank;
    }
    return map;
  }

  Future<void> saveChartSnapshot(
    String periodKey,
    Map<String, int> ranks,
  ) async {
    final lines = [
      for (final e in ranks.entries) '${e.key}|${e.value}',
    ];
    await _prefs.setStringList('chart_snap_$periodKey', lines);
  }

  /// Artist key (lowercase name) -> absolute photo path.
  Map<String, String> exportArtistPhotoPaths() {
    final out = <String, String>{};
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_artistPhotoPrefix)) continue;
      final path = _prefs.getString(key);
      if (path == null || path.isEmpty) continue;
      out[key.substring(_artistPhotoPrefix.length)] = path;
    }
    return out;
  }

  Future<void> replaceArtistPhotoPaths(Map<String, String> artistToPath) async {
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith(_artistPhotoPrefix)) {
        await _prefs.remove(key);
      }
    }
    for (final e in artistToPath.entries) {
      if (e.value.isEmpty) continue;
      await _prefs.setString('$_artistPhotoPrefix${e.key}', e.value);
      // Imported photos are treated as manual so auto-refresh won't overwrite.
      await _prefs.setBool('$_artistPhotoManualPrefix${e.key}', true);
    }
    notifyListeners();
  }

  /// periodKey -> raw snapshot lines `trackKey|rank`.
  Map<String, List<String>> exportChartSnapshots() {
    final out = <String, List<String>>{};
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith('chart_snap_')) continue;
      final period = key.substring('chart_snap_'.length);
      out[period] = _prefs.getStringList(key) ?? const [];
    }
    return out;
  }

  Future<void> replaceChartSnapshots(Map<String, List<String>> snaps) async {
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith('chart_snap_')) {
        await _prefs.remove(key);
      }
    }
    for (final e in snaps.entries) {
      await _prefs.setStringList('chart_snap_${e.key}', e.value);
    }
    notifyListeners();
  }

  Map<String, bool> exportSettingsFlags() => {
        'scanOnStartup': scanOnStartup,
        'playOnStartup': playOnStartup,
        'autoFillEmptyMetadata': autoFillEmptyMetadata,
      };

  Future<void> importSettingsFlags(Map<String, dynamic> flags) async {
    final scan = flags['scanOnStartup'];
    if (scan is bool) await setScanOnStartup(scan);
    final play = flags['playOnStartup'];
    if (play is bool) await setPlayOnStartup(play);
    final fill = flags['autoFillEmptyMetadata'];
    if (fill is bool) await setAutoFillEmptyMetadata(fill);
  }
}
