import 'dart:async';
import 'package:just_audio/just_audio.dart';

import 'protocol/track_playback_exception.dart';

/// just_audio 的薄封装。上层只依赖这里暴露的流与方法，
/// 便于在测试中用 Fake 实现替换（不直接暴露 AudioPlayer 实例）。
class AudioPlayerService {
  final AudioPlayer _player;

  AudioPlayerService([AudioPlayer? player]) : _player = player ?? AudioPlayer();

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;

  /// 是否已加载过音源。
  bool get hasSource => _player.audioSource != null;

  /// 播放本地音频文件（协议链路下载、解密后的完整曲目）。
  ///
  /// 连续切歌时 just_audio 会以「加载被中断」结束上一次调用，属预期行为，静默返回；
  /// 其余加载失败（文件损坏 / 解码器不支持）抛 [TrackPlaybackException]（unavailable），
  /// 由 PlaybackProvider 提示并跳到下一首。
  Future<void> playFile(String path) async {
    if (path.isEmpty) return;
    try {
      await _player.setFilePath(path);
    } on PlayerInterruptedException {
      return;
    } catch (e) {
      throw TrackPlaybackException(TrackPlaybackFailure.unavailable, '音频文件无法解码，已跳过', e);
    }
    // just_audio 的 play() 要到播放结束 / 暂停才完成，不能 await，否则会阻塞后续切歌逻辑
    unawaited(_player.play().catchError((Object _) {}));
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));
  Future<void> stop() => _player.stop();

  void dispose() {
    _player.dispose();
  }
}
