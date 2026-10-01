import 'dart:async';

import 'package:audio_service/audio_service.dart' hide MediaButton;

import 'system_media_controls.dart';

/// Android / iOS：通过 audio_service 提供通知栏、锁屏与蓝牙耳机按键控制。
///
/// 实际播放仍由 just_audio 完成；这里的 [AudioHandler] 只做「状态展示 + 按键转发」。
class AudioServiceMediaControls implements SystemMediaControls {
  final _FlutifyAudioHandler _handler;

  AudioServiceMediaControls._(this._handler);

  static Future<AudioServiceMediaControls> init() async {
    final handler = await AudioService.init(
      builder: _FlutifyAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.flutify.music.playback',
        androidNotificationChannelName: '播放',
        androidNotificationIcon: 'mipmap/ic_launcher',
        // 暂停时允许划掉通知、让出前台服务
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    return AudioServiceMediaControls._(handler);
  }

  @override
  Stream<MediaControlEvent> get events => _handler.events.stream;

  @override
  bool get needsPeriodicTimeline => false; // 系统按 updateTime + speed 自行推算进度

  @override
  Future<void> setTrack(MediaTrackInfo? track) async {
    _handler.mediaItem.add(
      track == null
          ? null
          : MediaItem(
              id: track.id,
              title: track.title,
              artist: track.artist,
              album: track.album,
              duration: track.duration,
              artUri: track.artUrl.isEmpty ? null : Uri.tryParse(track.artUrl),
            ),
    );
    if (track == null) {
      _handler.playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
    }
  }

  @override
  Future<void> setPlayback(MediaPlaybackInfo info) async {
    _handler.playbackState.add(
      PlaybackState(
        controls: [
          if (info.canPrevious) MediaControl.skipToPrevious,
          info.playing ? MediaControl.pause : MediaControl.play,
          if (info.canNext) MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: [
          for (var i = 0; i < 1 + (info.canPrevious ? 1 : 0) + (info.canNext ? 1 : 0); i++) i,
        ],
        processingState: info.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
        playing: info.playing,
        updatePosition: info.position,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(setTrack(null));
  }
}

class _FlutifyAudioHandler extends BaseAudioHandler with SeekHandler {
  final StreamController<MediaControlEvent> events = StreamController.broadcast();

  void _button(MediaButton b) => events.add(MediaButtonEvent(b));

  @override
  Future<void> play() async => _button(MediaButton.play);

  @override
  Future<void> pause() async => _button(MediaButton.pause);

  @override
  Future<void> stop() async => _button(MediaButton.stop);

  @override
  Future<void> skipToNext() async => _button(MediaButton.next);

  @override
  Future<void> skipToPrevious() async => _button(MediaButton.previous);

  @override
  Future<void> seek(Duration position) async => events.add(MediaSeekEvent(position));
}
