import 'dart:async';

import 'package:flutify_app/services/audio_player_service.dart';
import 'package:just_audio/just_audio.dart';

/// 不依赖平台通道的音频服务替身：记录调用，并允许测试手动推送播放器事件。
class FakeAudioPlayerService implements AudioPlayerService {
  final StreamController<Duration> positionController = StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> durationController = StreamController<Duration?>.broadcast(sync: true);
  final StreamController<PlayerState> stateController = StreamController<PlayerState>.broadcast(sync: true);

  final List<String> playedUrls = [];
  final List<String> playedFiles = [];
  final List<Duration> seeks = [];
  double lastVolume = 1.0;
  bool _playing = false;
  bool _hasSource = false;

  @override
  Stream<Duration> get positionStream => positionController.stream;
  @override
  Stream<Duration?> get durationStream => durationController.stream;
  @override
  Stream<PlayerState> get playerStateStream => stateController.stream;

  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => null;
  @override
  bool get isPlaying => _playing;
  @override
  bool get hasSource => _hasSource;

  @override
  Future<void> playUrl(String url) async {
    playedUrls.add(url);
    _hasSource = true;
    _playing = true;
  }

  @override
  Future<void> playFile(String path) async {
    playedFiles.add(path);
    _hasSource = true;
    _playing = true;
  }

  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;
  @override
  Future<void> stop() async => _playing = false;

  @override
  void dispose() {
    positionController.close();
    durationController.close();
    stateController.close();
  }

  /// 模拟当前曲目播放结束。
  void emitCompleted() => stateController.add(PlayerState(true, ProcessingState.completed));
}
