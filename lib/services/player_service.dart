import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../models/equalizer_state.dart';
import '../models/track.dart';
import '../utils/playable_path.dart';
import 'library_service.dart';
import 'settings_service.dart';

class PlayerService extends ChangeNotifier {
  PlayerService(this._library, this._settings) {
    _playPaths = PlayPathResolver(_library.paths.playCacheDir);
    _volume = _settings.playerVolume;
    _volumeBeforeMute = _settings.playerVolumeBeforeMute;
    if (_volumeBeforeMute <= 0.001) _volumeBeforeMute = 1.0;
    _shuffle = _settings.playbackShuffle;
    _repeat = _repeatFromString(_settings.playbackRepeat);
    _equalizer = _settings.equalizer;
    _playerA = Player(
      configuration: const PlayerConfiguration(title: 'Freedom Music'),
    );
    _playerB = Player(
      configuration: const PlayerConfiguration(title: 'Freedom Music'),
    );
    final gain = _mediaKitVolume(_volume);
    unawaited(_playerA.setVolume(gain));
    unawaited(_playerB.setVolume(gain));
    unawaited(_applyEqualizerFilter());
    _library.addListener(_pullQueueMetadata);
    _wirePlayer(_playerA, isActive: () => _usingA);
    _wirePlayer(_playerB, isActive: () => !_usingA);
  }

  /// Queue copies stay stale until the library notifies. Metadata fill
  /// updates the library track immediately, so mirror that into the queue.
  void _pullQueueMetadata() {
    var changed = false;
    for (var i = 0; i < _queue.length; i++) {
      final fresh = _library.trackByKey(_queue[i].trackKey);
      if (fresh == null || !_trackMetaDiffers(_queue[i], fresh)) continue;
      _queue[i] = fresh;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  bool _trackMetaDiffers(Track a, Track b) {
    return a.album != b.album ||
        a.albumArtist != b.albumArtist ||
        a.year != b.year ||
        a.trackNumber != b.trackNumber ||
        a.trackTotal != b.trackTotal ||
        a.discNumber != b.discNumber ||
        a.producer != b.producer ||
        a.genre != b.genre ||
        a.lyrics != b.lyrics ||
        a.title != b.title ||
        a.artist != b.artist ||
        a.coverPath != b.coverPath;
  }

  void _wirePlayer(Player player, {required bool Function() isActive}) {
    void onErr(Object e, StackTrace st) {
      debugPrint('media_kit stream error: $e');
    }

    player.stream.playing.listen((playing) {
      if (!isActive()) return;
      if (playing) {
        _startPositionPoll();
      } else if (!_crossfading) {
        _stopPositionPoll();
      }
      notifyListeners();
    }, onError: onErr);
    player.stream.position.listen((pos) {
      if (!isActive()) return;
      _onPositionTick(pos);
      _maybeStartCrossfade();
      _schedulePersist();
      notifyListeners();
    }, onError: onErr);
    player.stream.duration.listen((d) {
      if (!isActive()) return;
      if (d.inMilliseconds > 0) {
        _duration = d;
        notifyListeners();
      }
    }, onError: onErr);
    player.stream.completed.listen((done) {
      if (!isActive() || !done) return;
      if (_crossfading || _switchingTrack) return;
      final until = _ignoreCompleteUntil;
      if (until != null && DateTime.now().isBefore(until)) return;
      final total = _duration;
      final fresh = DateTime.now().difference(_lastPositionAt) <
          const Duration(seconds: 2);
      if (!_heardNearEnd &&
          fresh &&
          total != null &&
          total - _position > const Duration(seconds: 3)) {
        return;
      }
      unawaited(_onTrackComplete());
    }, onError: onErr);
  }

  void _onPositionTick(Duration pos) {
    _position = pos;
    _lastPositionAt = DateTime.now();
    if (pos + const Duration(milliseconds: 400) < _listenMark) {
      final back = _listenMark - pos;
      if (back > const Duration(seconds: 3)) {
        _listenMark = pos;
      }
      return;
    }
    final delta = pos - _listenMark;
    if (delta <= Duration.zero) return;
    if (delta > const Duration(milliseconds: 3200)) {
      _listenMark = pos;
      final total = _duration;
      if (total != null && total - pos <= const Duration(seconds: 4)) {
        _heardNearEnd = true;
      }
      return;
    }
    _listenMark = pos;
    _listened += delta;
    _pendingListenMs += delta.inMilliseconds;
    final total = _duration;
    if (total != null && total - pos <= const Duration(seconds: 4)) {
      _heardNearEnd = true;
    }
    if (_pendingListenMs >= 3000) _flushListenMs();
    _maybeCountPlay();
  }

  void _startPositionPoll() {
    _positionPoll?.cancel();
    _positionPoll = Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(_pollPosition());
    });
  }

  void _stopPositionPoll() {
    _positionPoll?.cancel();
    _positionPoll = null;
  }

  Future<void> _pollPosition() async {
    if (_crossfading) return;
    if (!_primary.state.playing) {
      if (!_primary.state.playing && _primary.state.buffering == false) {
        // Keep polling while paused only if we still need duration.
        if (_duration != null && _duration!.inMilliseconds > 0) {
          _stopPositionPoll();
        }
      }
      return;
    }
    try {
      final pos = _primary.state.position;
      final skew = (pos - _position).abs();
      if (skew >= const Duration(milliseconds: 80)) {
        _onPositionTick(pos);
        _maybeStartCrossfade();
        _schedulePersist();
        notifyListeners();
      }
      final d = _primary.state.duration;
      if ((_duration == null || _duration!.inMilliseconds <= 0) &&
          d.inMilliseconds > 0) {
        _duration = d;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Position poll failed: $e');
    }
  }

  /// UI volume 0–1 → quieter low end (perception / Windows gain).
  static double outputGain(double ui) {
    final v = ui.clamp(0.0, 1.0);
    if (v <= 0) return 0;
    return v * v * v;
  }

  /// media_kit volume is 0–100.
  static double _mediaKitVolume(double ui) => outputGain(ui) * 100;

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
    _listenMark = Duration.zero;
    _heardNearEnd = false;
  }

  Future<void> _onTrackComplete() async {
    if (_queue.isEmpty || _index < 0) return;
    if (_repeat == PlayRepeatMode.one) {
      await _playIndex(_index);
      return;
    }
    await next();
  }

  final LibraryService _library;
  final SettingsService _settings;
  late final PlayPathResolver _playPaths;
  late final Player _playerA;
  late final Player _playerB;
  final Random _random = Random();

  bool _usingA = true;
  bool _crossfading = false;
  bool _heardNearEnd = false;
  Timer? _persistTimer;
  bool _engineArmed = false;
  bool _primaryHasMedia = false;

  List<Track> _queue = [];
  int _queueEpoch = 0;
  int _index = -1;
  bool _shuffle = true;
  PlayRepeatMode _repeat = PlayRepeatMode.off;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playCounted = false;
  Duration _listened = Duration.zero;
  Duration _listenMark = Duration.zero;
  int _pendingListenMs = 0;
  DateTime? _ignoreCompleteUntil;
  DateTime _lastPositionAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _positionPoll;
  bool _switchingTrack = false;
  late double _volume;
  late double _volumeBeforeMute;
  late EqualizerState _equalizer;
  Timer? _eqDebounce;

  Player get _primary => _usingA ? _playerA : _playerB;
  Player get _secondary => _usingA ? _playerB : _playerA;

  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  List<Track> get queue => List.unmodifiable(_queue);

  int get queueEpoch => _queueEpoch;
  int get queueIndex => _index;

  bool get playing {
    if (_primary.state.playing) return true;
    if (_crossfading && _secondary.state.playing) return true;
    return false;
  }

  bool get shuffle => _shuffle;
  PlayRepeatMode get repeat => _repeat;
  Duration get position => _position;
  Duration? get duration => _duration;
  double get volume => _volume;
  bool get muted => _volume <= 0.001;
  int get crossfadeSeconds => _settings.crossfadeSeconds;
  EqualizerState get equalizer => _equalizer;

  Future<void> restoreSession() async {
    final keys = _settings.playbackQueueKeys;
    if (keys.isEmpty) return;

    final byKey = <String, Track>{
      for (final t in _library.tracks) t.trackKey: t,
    };
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

    _queue = restored;
    _queueEpoch++;
    _index = index;
    final posMs = _settings.playbackPositionMs;
    _position = posMs > 0 ? Duration(milliseconds: posMs) : Duration.zero;
    _duration = null;
    _primaryHasMedia = false;
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

  Future<Media> _mediaFor(String path) async {
    final resolved = await _playPaths.resolve(path);
    if (Platform.isWindows) {
      return Media(Uri.file(resolved, windows: true).toString());
    }
    return Media(resolved);
  }

  Future<void> _setPlayerAf(Player player, String filter) async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('af', filter);
    }
  }

  Future<void> _applyEqualizerFilter() async {
    final filter = _equalizer.toAudioFilter();
    await _setPlayerAf(_playerA, filter);
    await _setPlayerAf(_playerB, filter);
  }

  void _scheduleEqualizerApply() {
    _eqDebounce?.cancel();
    _eqDebounce = Timer(const Duration(milliseconds: 50), () {
      unawaited(_applyEqualizerFilter());
    });
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    _equalizer = _equalizer.copyWith(enabled: enabled);
    await _settings.setEqualizer(_equalizer);
    await _applyEqualizerFilter();
    notifyListeners();
  }

  Future<void> setEqualizerLevel(double level) async {
    final next = level.clamp(EqualizerState.minDb, EqualizerState.maxDb);
    _equalizer = _equalizer.copyWith(
      level: next,
      presetId: EqualizerPresets.matchPresetId(_equalizer.bands, next),
      enabled: true,
    );
    await _settings.setEqualizer(_equalizer);
    _scheduleEqualizerApply();
    notifyListeners();
  }

  Future<void> setEqualizerBand(int index, double gain) async {
    if (index < 0 || index >= EqualizerState.bandCount) return;
    final bands = List<double>.from(_equalizer.bands);
    bands[index] = gain.clamp(EqualizerState.minDb, EqualizerState.maxDb);
    _equalizer = _equalizer.copyWith(
      bands: bands,
      presetId: EqualizerPresets.matchPresetId(bands, _equalizer.level),
      enabled: true,
    );
    await _settings.setEqualizer(_equalizer);
    _scheduleEqualizerApply();
    notifyListeners();
  }

  Future<void> applyEqualizerPreset(String presetId) async {
    if (presetId == EqualizerPresets.customId) return;
    final preset = EqualizerPresets.byId(presetId);
    if (preset == null) return;
    _equalizer = EqualizerState(
      enabled: true,
      level: 0,
      bands: List<double>.from(preset.bands),
      presetId: preset.id,
    );
    await _settings.setEqualizer(_equalizer);
    await _applyEqualizerFilter();
    notifyListeners();
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

  Future<void> startOnLaunch() async {
    _armEngine();
    if (current == null) {
      await playRandomAll();
      return;
    }
    final pos = _position;
    await _playIndex(_index, autoplay: true);
    if (pos > Duration.zero) {
      await seek(pos);
    }
  }

  Future<void> playRandomAll() async {
    _armEngine();
    final tracks = _withExistingFiles(_library.catalogTracks);
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
    if (!_engineArmed) return;
    if (current == null) {
      await playRandomAll();
      return;
    }
    if (!_primaryHasMedia) {
      final pos = _position;
      await _playIndex(_index, autoplay: true);
      if (pos > Duration.zero) {
        await seek(pos);
      }
      return;
    }
    await _primary.play();
    notifyListeners();
  }

  Future<void> pausePlayback() async {
    await _cancelCrossfade();
    await _primary.pause();
    await persistSession();
    notifyListeners();
  }

  Future<void> stopAndClear() async {
    await _cancelCrossfade();
    _stopPositionPoll();
    _flushListenMs();
    try {
      await _primary.stop();
      await _secondary.stop();
    } catch (_) {}
    _queue = [];
    _queueEpoch++;
    _index = -1;
    _position = Duration.zero;
    _duration = null;
    _primaryHasMedia = false;
    _playCounted = false;
    _listened = Duration.zero;
    _listenMark = Duration.zero;
    await _settings.clearPlaybackSession();
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
    if (_shuffle && _queue.isNotEmpty && _index >= 0) {
      _reshuffleQueueKeepingCurrent();
    }
    _schedulePersist();
    notifyListeners();
  }

  void _reshuffleQueueKeepingCurrent() {
    if (_index < 0 || _index >= _queue.length) return;
    final current = _queue[_index];
    final others = <Track>[
      ..._queue.sublist(0, _index),
      ..._queue.sublist(_index + 1),
    ]..shuffle(_random);
    _queue = [current, ...others];
    _queueEpoch++;
    _index = 0;
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
        _primaryHasMedia = false;
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
    _ignoreCompleteUntil =
        DateTime.now().add(const Duration(milliseconds: 800));
    final total = _duration;
    _heardNearEnd = total != null &&
        total > position &&
        total - position <= const Duration(seconds: 4);
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
    final gain = _mediaKitVolume(_volume);
    if (!_crossfading) {
      await _primary.setVolume(gain);
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

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;

    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    _queueEpoch++;

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

  void syncTrack(Track updated, {String? oldTrackKey, bool notify = true}) {
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
    if (notify) notifyListeners();
  }

  void syncTracks(Iterable<({Track track, String oldKey})> edits) {
    for (final edit in edits) {
      syncTrack(edit.track, oldTrackKey: edit.oldKey, notify: false);
    }
    notifyListeners();
  }

  Future<void> removeTrackFromQueue(String trackKey) async {
    final wasCurrent = current?.trackKey == trackKey;
    final nextAfter = _index < _queue.length - 1 ? _index : _index - 1;
    _queue = [for (final t in _queue) if (t.trackKey != trackKey) t];
    _queueEpoch++;
    if (_queue.isEmpty) {
      _index = -1;
      await _cancelCrossfade();
      await _primary.stop();
      _primaryHasMedia = false;
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
    _queueEpoch++;
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
    _switchingTrack = true;
    _index = index;
    _resetListenAccounting();
    _position = Duration.zero;
    _duration = null;
    notifyListeners();

    try {
      await _secondary.stop();
      await _primary.stop();
      await _applyEqualizerFilter();
      await _primary.setVolume(_mediaKitVolume(_volume));
      await _primary.open(await _mediaFor(path), play: autoplay);
      _primaryHasMedia = true;
      _startPositionPoll();
      unawaited(_pollPosition());
      if (!autoplay) {
        await _primary.pause();
        _stopPositionPoll();
      }
    } catch (e) {
      debugPrint('Failed to play $path: $e');
      _primaryHasMedia = false;
      if (autoplay && index + 1 < _queue.length) {
        _switchingTrack = false;
        await _playIndex(index + 1, autoplay: true);
        return;
      }
    } finally {
      _switchingTrack = false;
    }
    _maybeFetchLyrics(track);
    _schedulePersist();
    notifyListeners();
  }

  void _maybeFetchLyrics(Track track) {
    unawaited(_library.ensureRemoteLyrics(track).then((updated) {
      if (updated != null) syncTrack(updated);
    }));
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
    var nextIndex = _index + 1;
    if (nextIndex >= _queue.length) {
      if (_repeat != PlayRepeatMode.all || _queue.length < 2) return;
      nextIndex = 0;
    }
    unawaited(_runCrossfade(nextIndex, remaining));
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
      await _applyEqualizerFilter();
      await incoming.setVolume(0);
      await incoming.open(await _mediaFor(path), play: true);

      final gain = _mediaKitVolume(_volume);
      final steps = max(8, fadeMs ~/ 40);
      final stepMs = max(1, fadeMs ~/ steps);
      for (var i = 1; i <= steps; i++) {
        if (!_crossfading) return;
        final t = i / steps;
        await outgoing.setVolume(gain * (1 - t));
        await incoming.setVolume(gain * t);
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
      if (!_crossfading) return;

      await outgoing.stop();
      await outgoing.setVolume(gain);
      _usingA = !_usingA;
      _primaryHasMedia = true;
      _index = nextIndex;
      _resetListenAccounting();
      _position = Duration.zero;
      _duration = null;
      _startPositionPoll();
      unawaited(_pollPosition());
      _maybeFetchLyrics(_queue[nextIndex]);
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
      final gain = _mediaKitVolume(_volume);
      await _secondary.setVolume(gain);
      await _primary.setVolume(gain);
    } catch (_) {}
  }

  void _maybeCountPlay() {
    if (_playCounted || current == null) return;
    final total = _duration;
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
    _library.removeListener(_pullQueueMetadata);
    _flushListenMs();
    _stopPositionPoll();
    _persistTimer?.cancel();
    _eqDebounce?.cancel();
    unawaited(persistSession());
    unawaited(_playerA.dispose());
    unawaited(_playerB.dispose());
    super.dispose();
  }
}

enum PlayRepeatMode { off, all, one }
