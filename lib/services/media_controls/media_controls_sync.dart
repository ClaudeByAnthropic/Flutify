import 'dart:async';

import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import 'system_media_controls.dart';

/// 把本机播放状态同步给系统媒体控制，并把系统按键转给 [PlaybackProvider]。
///
/// 规则：
/// - 曲目、播放 / 暂停、缓冲、能否切歌只在变化时下发（PlaybackProvider 的通知很频繁，这里做差异比较）；
/// - 进度：拖动（与按时间推算的位置相差超过 2 秒）时立即下发；系统不会自行推算进度的平台（Windows）
///   播放中每 [timelineInterval] 再下发一次；
/// - 系统的「播放 / 暂停」按当前状态决定是否切换，避免重复按键把状态切反。
class MediaControlsSync {
  final PlaybackProvider playback;
  final SystemMediaControls controls;

  static const Duration timelineInterval = Duration(seconds: 5);

  StreamSubscription<MediaControlEvent>? _events;
  String? _trackId;
  MediaPlaybackInfo? _lastPlayback;
  DateTime _lastPlaybackAt = DateTime.now();

  MediaControlsSync(this.playback, this.controls) {
    playback.addListener(_sync);
    playback.positionNotifier.addListener(_onPosition);
    _events = controls.events.listen(_onEvent);
    _sync();
  }

  void _sync() {
    final track = playback.currentTrack;
    if (track?.id != _trackId) {
      _trackId = track?.id;
      unawaited(controls.setTrack(track == null ? null : _info(track)));
      _lastPlayback = null;
    }
    if (track == null) return;
    final next = _playbackInfo();
    final last = _lastPlayback;
    if (last == null ||
        last.playing != next.playing ||
        last.buffering != next.buffering ||
        last.canNext != next.canNext ||
        last.canPrevious != next.canPrevious) {
      _push(next);
    }
  }

  void _onPosition() {
    final last = _lastPlayback;
    if (last == null || playback.currentTrack == null) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastPlaybackAt);
    final expected = last.playing ? last.position + elapsed : last.position;
    final jumped = (playback.position - expected).abs() > const Duration(seconds: 2);
    final periodic = controls.needsPeriodicTimeline && last.playing && elapsed >= timelineInterval;
    if (jumped || periodic) _push(_playbackInfo());
  }

  void _push(MediaPlaybackInfo info) {
    _lastPlayback = info;
    _lastPlaybackAt = DateTime.now();
    unawaited(controls.setPlayback(info));
  }

  MediaPlaybackInfo _playbackInfo() => MediaPlaybackInfo(
    playing: playback.isPlaying,
    buffering: playback.isBuffering,
    position: playback.position,
    canNext: playback.userQueue.isNotEmpty || playback.upNext.isNotEmpty,
    // 「上一首」在开头时回到上一首、否则回到本曲开头，始终可用
    canPrevious: true,
  );

  static MediaTrackInfo _info(SpotifyTrack track) => MediaTrackInfo(
    id: track.id,
    title: track.name,
    artist: track.artistNames,
    album: track.album?.name ?? '',
    artUrl: track.coverUrl,
    duration: Duration(milliseconds: track.durationMs),
  );

  void _onEvent(MediaControlEvent event) {
    switch (event) {
      case MediaButtonEvent(button: MediaButton.play):
        if (!playback.isPlaying) unawaited(playback.togglePlayPause());
      case MediaButtonEvent(button: MediaButton.pause || MediaButton.stop):
        if (playback.isPlaying) unawaited(playback.togglePlayPause());
      case MediaButtonEvent(button: MediaButton.toggle):
        unawaited(playback.togglePlayPause());
      case MediaButtonEvent(button: MediaButton.next):
        unawaited(playback.nextTrack());
      case MediaButtonEvent(button: MediaButton.previous):
        unawaited(playback.previousTrack());
      case MediaSeekEvent(:final position):
        unawaited(playback.seekTo(position));
    }
  }

  void dispose() {
    playback.removeListener(_sync);
    playback.positionNotifier.removeListener(_onPosition);
    _events?.cancel();
    controls.dispose();
  }
}
