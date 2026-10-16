import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'player_service.dart';

/// Bridges [PlayerService] to Windows SMTC via audio_service / audio_service_win.
class FreedomAudioHandler extends BaseAudioHandler with SeekHandler {
  FreedomAudioHandler(this._player) {
    _player.addListener(_sync);
    _sync();
  }

  final PlayerService _player;

  void _sync() {
    final track = _player.current;
    mediaItem.add(track == null ? null : _toMediaItem(track));

    final playing = _player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: track == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.position,
        speed: 1.0,
        queueIndex: _player.queueIndex,
      ),
    );
  }

  MediaItem _toMediaItem(Track track) {
    Uri? art;
    final cover = track.coverPath;
    if (cover != null && cover.isNotEmpty && File(cover).existsSync()) {
      art = Uri.file(cover);
    }
    return MediaItem(
      id: track.trackKey,
      title: track.displayTitle,
      artist: track.displayArtist,
      album: track.displayAlbum,
      duration: _player.duration ??
          (track.durationMs != null
              ? Duration(milliseconds: track.durationMs!)
              : null),
      artUri: art,
    );
  }

  @override
  Future<void> play() => _player.resumePlayback();

  @override
  Future<void> pause() => _player.pausePlayback();

  @override
  Future<void> stop() async {
    await _player.pausePlayback();
    await _player.seek(Duration.zero);
    await super.stop();
  }

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> onTaskRemoved() async {
    // Keep playing in tray — do not stop.
  }

  void disposeHandler() {
    _player.removeListener(_sync);
  }
}

Future<FreedomAudioHandler> initAudioHandler(PlayerService player) async {
  try {
    return await AudioService.init(
      builder: () => FreedomAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.freedommusic.player',
        androidNotificationChannelName: 'Freedom Music',
        androidNotificationOngoing: true,
        artDownscaleWidth: 200,
        artDownscaleHeight: 200,
      ),
    );
  } catch (e, st) {
    debugPrint('AudioService init failed: $e\n$st');
    // Still return a handler so callers don't crash; SMTC just won't show.
    return FreedomAudioHandler(player);
  }
}
