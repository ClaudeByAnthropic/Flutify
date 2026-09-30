import 'dart:async';
import 'package:just_audio/just_audio.dart';

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

  /// 是否已加载过音源（首次点击播放时需要先 setUrl）。
  bool get hasSource => _player.audioSource != null;

  Future<void> playUrl(String url) async {
    if (url.isEmpty) return;
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {
      // 连续切歌时 just_audio 会以 "Loading interrupted" 中断上一次加载，属预期行为。
    }
  }

  /// 播放本地文件（协议链路下载解密后的完整曲目）。
  Future<void> playFile(String path) async {
    if (path.isEmpty) return;
    try {
      await _player.setFilePath(path);
      await _player.play();
    } catch (_) {
      // 同 playUrl：切歌中断属预期行为。
    }
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
