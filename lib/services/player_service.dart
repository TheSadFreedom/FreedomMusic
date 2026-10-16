import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../utils/playable_path.dart';
import 'library_service.dart';
import 'settings_service.dart';

class PlayerService extends ChangeNotifier {
  PlayerService(this._library, this._settings) {
    AudioPlayer.preparationTimeout = const Duration(seconds: 12);
    _playPaths = PlayPathResolver(_library.paths.playCacheDir);
    _volume = _settings.playerVolume;
    _volumeBeforeMute = _settings.playerVolumeBeforeMute;
    if (_volumeBeforeMute <= 0.001) _volumeBeforeMute = 1.0;
    _shuffle = _settings.playbackShuffle;
    _repeat = _repeatFromString(_settings.playbackRepeat);
    unawaited(_playerA.setVolume(_volume));
    unawaited(_playerB.setVolume(_volume));
    _wirePlayer(_playerA, isActive: () => _usingA);
    _wirePlayer(_playerB, isActive: () => !_usingA);
  }

  void _wirePlayer(AudioPlayer player, {required bool Function() isActive}) {
    void onErr(Object e, StackTrace st) {
      debugPrint('AudioPlayer stream error: $e');
    }

    player.onPlayerStateChanged.listen((_) {
      if (!isActive()) return;
      notifyListeners();
    }, onError: onErr);
    player.onPositionChanged.listen((pos) {
      if (!isActive()) return;
      _onPositionTick(pos);
      _maybeStartCrossfade();
      _schedulePersist();
      notifyListeners();
    }, onError: onErr);
    player.onDurationChanged.listen((d) {
      if (!isActive()) return;
      _duration = d;
      notifyListeners();
    }, onError: onErr);
    player.onPlayerComplete.listen((_) {
      if (!isActive()) return;
      if (_crossfading) return;
      // Seeking to the end often fires "complete" on Windows — ignore briefly.
      final until = _ignoreCompleteUntil;
      if (until != null && DateTime.now().isBefore(until)) return;
      unawaited(_onTrackComplete());
    }, onError: onErr);
  }

  void _onPositionTick(Duration pos) {
    final prev = _position;
    _position = pos;
    // Only credit real playback (small forward steps). Big jumps = seek.
    final delta = pos - prev;
    if (delta > Duration.zero && delta < const Duration(seconds: 2)) {
      _listened += delta;
      _pendingListenMs += delta.inMilliseconds;
      if (_pendingListenMs >= 3000) _flushListenMs();
      _maybeCountPlay();
    }
  }

  void _flushListenMs() {
    final key = current?.trackKey;
    final ms = _pendingListenMs;
    _pendingListenMs = 0;
    if (key == null || ms <= 0) return;
    unawaited(_library.addListenMs(key, ms));
  }

  void _resetListenAccounting() {
    _flushListenMs();
    _playCounted = false;
    _listened = Duration.zero;
  }

  Future<void> _onTrackComplete() async {
    if (_repeat == PlayRepeatMode.one) {
      _resetListenAccounting();
      await seek(Duration.zero);
      await _primary.resume();
      return;
    }
    await next();
  }

  final LibraryService _library;
  final SettingsService _settings;
  late final PlayPathResolver _playPaths;
  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  final Random _random = Random();

  bool _usingA = true;
  bool _crossfading = false;
  Timer? _persistTimer;

  /// SMTC/audio_service often sends Play on launch; delay native setSource
  /// until the user actually starts playback from the UI.
  bool _engineArmed = false;

  List<Track> _queue = [];
  int _index = -1;
  bool _shuffle = true;
  PlayRepeatMode _repeat = PlayRepeatMode.off;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playCounted = false;
  /// Wall-clock listening time (seeks do not add to this).
  Duration _listened = Duration.zero;
  /// Pending ms to flush into [LibraryService.addListenMs].
  int _pendingListenMs = 0;
  DateTime? _ignoreCompleteUntil;
  late double _volume;
  late double _volumeBeforeMute;

  AudioPlayer get _primary => _usingA ? _playerA : _playerB;
  AudioPlayer get _secondary => _usingA ? _playerB : _playerA;

  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  List<Track> get queue => List.unmodifiable(_queue);
  int get queueIndex => _index;

  bool get playing {
    if (_primary.state == PlayerState.playing) return true;
    if (_crossfading && _secondary.state == PlayerState.playing) return true;
    return false;
  }

  bool get shuffle => _shuffle;
  PlayRepeatMode get repeat => _repeat;
  Duration get position => _position;
  Duration? get duration => _duration;
  double get volume => _volume;
  bool get muted => _volume <= 0.001;
  int get crossfadeSeconds => _settings.crossfadeSeconds;

  /// Restore last queue + position after the library is loaded (paused).
  Future<void> restoreSession() async {
    final keys = _settings.playbackQueueKeys;
    if (keys.isEmpty) return;

    final byKey = <String, Track>{
      for (final t in _library.tracks) t.trackKey: t,
    };
    // Drop tracks whose files vanished — calling audioplayers with a missing
    // Cyrillic path crashes the Windows event channel (invalid UTF-8).
    final restored = <Track>[
      for (final k in keys)
        if (byKey[k] != null && _fileExists(byKey[k]!.primaryPath)) byKey[k]!,
    ];
    if (restored.isEmpty) {
      await _settings.clearPlaybackSession();
      return;
    }

    var index = _settings.playbackIndex;
    if (index < 0 || index >= restored.length) index = 0;
    if (!_fileExists(restored[index].primaryPath)) {
      index = 0;
    }
    _shuffle = _settings.playbackShuffle;
    _repeat = _repeatFromString(_settings.playbackRepeat);

    // Restore queue in memory only — do not call audioplayers yet.
    // setSource on Windows posts events from a background thread and can
    // kill the process during startup (FormatException / Lost connection).
    _queue = restored;
    _index = index;
    final posMs = _settings.playbackPositionMs;
    _position = posMs > 0 ? Duration(milliseconds: posMs) : Duration.zero;
    _duration = null;
    _resetListenAccounting();
    notifyListeners();
  }

  static bool _fileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<Source> _sourceFor(String path) async {
    final resolved = await _playPaths.resolve(path);
    // file:// URL is more reliable for MF than a raw Win32 path.
    if (Platform.isWindows) {
      return UrlSource(Uri.file(resolved, windows: true).toString());
    }
    return DeviceFileSource(resolved);
  }

  Future<void> persistSession() async {
    _persistTimer?.cancel();
    if (_queue.isEmpty || _index < 0) {
      await _settings.clearPlaybackSession();
      return;
    }
    await _settings.savePlaybackSession(
      queueKeys: [for (final t in _queue) t.trackKey],
      index: _index,
      positionMs: _position.inMilliseconds,
      shuffle: _shuffle,
      repeat: _repeat.name,
    );
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), () {
      unawaited(persistSession());
    });
  }

  List<Track> _withExistingFiles(Iterable<Track> tracks) {
    return [
      for (final t in tracks)
        if (_fileExists(t.primaryPath)) t,
    ];
  }

  void _armEngine() {
    _engineArmed = true;
  }

  Future<void> playRandomAll() async {
    _armEngine();
    final tracks = _withExistingFiles(_library.tracks);
    if (tracks.isEmpty) return;
    tracks.shuffle(_random);
    await _setQueue(tracks, startIndex: 0, autoplay: true);
  }

  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    _armEngine();
    final list = _withExistingFiles(tracks);
    if (list.isEmpty) return;
    var index = startIndex.clamp(0, list.length - 1);
    if (shuffle) {
      final startKey = tracks.isNotEmpty
          ? tracks[startIndex.clamp(0, tracks.length - 1)].trackKey
          : list.first.trackKey;
      list.shuffle(_random);
      index = list.indexWhere((t) => t.trackKey == startKey);
      if (index < 0) index = 0;
    }
    _shuffle = shuffle;
    await _setQueue(list, startIndex: index, autoplay: true);
  }

  Future<void> resumePlayback() async {
    // Ignore SMTC "play" storms before the user presses play in the app.
    if (!_engineArmed) return;
    if (current == null) {
      await playRandomAll();
      return;
    }
    // After cold restore the native player has no source yet.
    if (_primary.source == null) {
      final pos = _position;
      await _playIndex(_index, autoplay: true);
      if (pos > Duration.zero) {
        await seek(pos);
      }
      return;
    }
    await _primary.resume();
    notifyListeners();
  }

  Future<void> pausePlayback() async {
    await _cancelCrossfade();
    await _primary.pause();
    await persistSession();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    _armEngine();
    if (current == null) {
      await playRandomAll();
      return;
    }
    if (playing) {
      await pausePlayback();
    } else {
      await resumePlayback();
    }
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _schedulePersist();
    notifyListeners();
  }

  void cycleRepeat() {
    _repeat = switch (_repeat) {
      PlayRepeatMode.off => PlayRepeatMode.all,
      PlayRepeatMode.all => PlayRepeatMode.one,
      PlayRepeatMode.one => PlayRepeatMode.off,
    };
    _schedulePersist();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    if (muted) {
      await setVolume(_volumeBeforeMute <= 0.001 ? 1.0 : _volumeBeforeMute);
    } else {
      _volumeBeforeMute = _volume;
      await setVolume(0);
    }
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    await _cancelCrossfade();
    final nextIndex = _index + 1;
    if (nextIndex >= _queue.length) {
      if (_repeat == PlayRepeatMode.off && !_shuffle) {
        await _primary.stop();
        notifyListeners();
        return;
      }
      if (_shuffle) {
        final tracks = List<Track>.from(_queue)..shuffle(_random);
        await _setQueue(tracks, startIndex: 0, autoplay: true);
        return;
      }
      await _playIndex(0);
      return;
    }
    await _playIndex(nextIndex);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    await _cancelCrossfade();
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    final prev = (_index - 1).clamp(0, _queue.length - 1);
    await _playIndex(prev);
  }

  Future<void> seek(Duration position) async {
    await _cancelCrossfade();
    // Suppress false EOF from Media Foundation when scrubbing to the end.
    _ignoreCompleteUntil =
        DateTime.now().add(const Duration(milliseconds: 800));
    await _primary.seek(position);
    _position = position;
    _schedulePersist();
    notifyListeners();
  }

  Future<void> seekBy(Duration delta) async {
    if (current == null) return;
    final maxMs = (_duration ?? Duration.zero).inMilliseconds;
    if (maxMs <= 0 && delta.isNegative) {
      await seek(Duration.zero);
      return;
    }
    final nextMs = (_position + delta).inMilliseconds.clamp(0, maxMs);
    await seek(Duration(milliseconds: nextMs));
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    if (_volume > 0.001) _volumeBeforeMute = _volume;
    if (!_crossfading) {
      await _primary.setVolume(_volume);
    }
    await _settings.setPlayerVolume(
      _volume,
      beforeMute: _volumeBeforeMute,
    );
    notifyListeners();
  }

  Future<void> playQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _cancelCrossfade();
    await _playIndex(index);
  }

  /// Reorder queue (drag & drop). [newIndex] is already adjusted
  /// (as from [ReorderableListView.onReorderItem]).
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;

    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);

    if (_index == oldIndex) {
      _index = newIndex;
    } else {
      var i = _index;
      if (oldIndex < i) i -= 1;
      if (newIndex <= i) i += 1;
      _index = i;
    }
    _schedulePersist();
    notifyListeners();
  }

  /// Keep queue in sync after metadata edits (path / key may change).
  void syncTrack(Track updated, {String? oldTrackKey}) {
    for (var i = 0; i < _queue.length; i++) {
      final t = _queue[i];
      final sameKey =
          t.trackKey == updated.trackKey || t.trackKey == oldTrackKey;
      final samePath = t.primaryPath != null &&
          updated.filePaths.contains(t.primaryPath);
      if (sameKey || samePath) {
        _queue[i] = updated;
      }
    }
    notifyListeners();
  }

  /// Drop a track from the queue (e.g. moved to trash / deleted).
  Future<void> removeTrackFromQueue(String trackKey) async {
    final wasCurrent = current?.trackKey == trackKey;
    final nextAfter = _index < _queue.length - 1 ? _index : _index - 1;
    _queue = [for (final t in _queue) if (t.trackKey != trackKey) t];
    if (_queue.isEmpty) {
      _index = -1;
      await _cancelCrossfade();
      await _primary.stop();
      await persistSession();
      notifyListeners();
      return;
    }
    if (wasCurrent) {
      final idx = nextAfter.clamp(0, _queue.length - 1);
      await _playIndex(idx, autoplay: playing);
    } else {
      if (_index >= _queue.length) _index = _queue.length - 1;
      _schedulePersist();
      notifyListeners();
    }
  }

  Future<void> _setQueue(
    List<Track> tracks, {
    required int startIndex,
    required bool autoplay,
  }) async {
    _queue = tracks;
    await _playIndex(startIndex, autoplay: autoplay);
  }

  Future<void> _playIndex(int index, {bool autoplay = true}) async {
    if (index < 0 || index >= _queue.length) return;
    final track = _queue[index];
    final path = track.primaryPath;
    if (path == null || !_fileExists(path)) {
      debugPrint('Missing audio file, skip: $path');
      _index = index;
      notifyListeners();
      if (!autoplay) return;
      for (var j = index + 1; j < _queue.length; j++) {
        if (_fileExists(_queue[j].primaryPath)) {
          await _playIndex(j, autoplay: true);
          return;
        }
      }
      return;
    }

    await _cancelCrossfade();
    _index = index;
    _resetListenAccounting();
    _position = Duration.zero;
    _duration = null;
    notifyListeners();

    try {
      await _secondary.stop();
      await _primary.stop();
      await _primary.setVolume(_volume);
      await _primary.play(await _sourceFor(path));
      if (!autoplay) {
        await _primary.pause();
      }
    } catch (e) {
      debugPrint('Failed to play $path: $e');
      // Only skip ahead while actively playing — never walk the whole queue
      // during session restore (that left a blank window for minutes).
      if (autoplay && index + 1 < _queue.length) {
        await _playIndex(index + 1, autoplay: true);
      }
    }
    _schedulePersist();
    notifyListeners();
  }

  void _maybeStartCrossfade() {
    final fadeSec = _settings.crossfadeSeconds;
    if (fadeSec <= 0 || _crossfading || _repeat == PlayRepeatMode.one) {
      return;
    }
    if (!playing) return;
    final total = _duration;
    if (total == null || total.inMilliseconds <= fadeSec * 1000 + 500) {
      return;
    }
    final remaining = total - _position;
    final fade = Duration(seconds: fadeSec);
    if (remaining > fade || remaining.inMilliseconds < 80) return;
    if (_index + 1 >= _queue.length) return;
    unawaited(_runCrossfade(_index + 1, remaining));
  }

  Future<void> _runCrossfade(int nextIndex, Duration remaining) async {
    if (_crossfading) return;
    final path = _queue[nextIndex].primaryPath;
    if (path == null || !_fileExists(path)) return;

    _crossfading = true;
    final fadeMs = remaining.inMilliseconds.clamp(
      200,
      _settings.crossfadeSeconds * 1000,
    );
    final outgoing = _primary;
    final incoming = _secondary;

    try {
      await incoming.stop();
      await incoming.setVolume(0);
      await incoming.play(await _sourceFor(path));

      final steps = max(8, fadeMs ~/ 40);
      final stepMs = max(1, fadeMs ~/ steps);
      for (var i = 1; i <= steps; i++) {
        if (!_crossfading) return;
        final t = i / steps;
        await outgoing.setVolume(_volume * (1 - t));
        await incoming.setVolume(_volume * t);
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
      if (!_crossfading) return;

      await outgoing.stop();
      await outgoing.setVolume(_volume);
      _usingA = !_usingA;
      _index = nextIndex;
      _resetListenAccounting();
      _position = Duration.zero;
      _duration = null;
      _schedulePersist();
    } catch (e) {
      debugPrint('Crossfade failed: $e');
      _crossfading = false;
      await _playIndex(nextIndex);
      return;
    }
    _crossfading = false;
    notifyListeners();
  }

  Future<void> _cancelCrossfade() async {
    if (!_crossfading) return;
    _crossfading = false;
    try {
      await _secondary.stop();
      await _secondary.setVolume(_volume);
      await _primary.setVolume(_volume);
    } catch (_) {}
  }

  void _maybeCountPlay() {
    if (_playCounted || current == null) return;
    final total = _duration;
    // Use accumulated playback only — scrubbing the bar must not count.
    final enoughByTime = _listened.inSeconds >= 30;
    final enoughByRatio = total != null &&
        total.inMilliseconds > 0 &&
        _listened.inMilliseconds >= total.inMilliseconds * 0.5;
    if (enoughByTime || enoughByRatio) {
      _playCounted = true;
      unawaited(_library.recordPlay(current!.trackKey));
    }
  }

  static PlayRepeatMode _repeatFromString(String raw) {
    return switch (raw) {
      'all' => PlayRepeatMode.all,
      'one' => PlayRepeatMode.one,
      _ => PlayRepeatMode.off,
    };
  }

  @override
  void dispose() {
    _flushListenMs();
    _persistTimer?.cancel();
    unawaited(persistSession());
    unawaited(_playerA.dispose());
    unawaited(_playerB.dispose());
    super.dispose();
  }
}

enum PlayRepeatMode { off, all, one }
