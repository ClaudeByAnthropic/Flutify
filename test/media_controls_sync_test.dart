import 'dart:async';
import 'dart:math';

import 'package:flutify_app/providers/playback_provider.dart';
import 'package:flutify_app/services/media_controls/media_controls_sync.dart';
import 'package:flutify_app/services/media_controls/system_media_controls.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player_service.dart';
import 'fakes/fake_track_audio_source.dart';
import 'fixtures/sample_catalog.dart';

class _FakeControls implements SystemMediaControls {
  final StreamController<MediaControlEvent> controller = StreamController.broadcast(sync: true);
  final List<MediaTrackInfo?> tracks = [];
  final List<MediaPlaybackInfo> playbacks = [];

  @override
  Stream<MediaControlEvent> get events => controller.stream;

  @override
  bool get needsPeriodicTimeline => true;

  @override
  Future<void> setTrack(MediaTrackInfo? track) async => tracks.add(track);

  @override
  Future<void> setPlayback(MediaPlaybackInfo info) async => playbacks.add(info);

  @override
  void dispose() => controller.close();
}

void main() {
  const a = SampleCatalog.track1;
  const b = SampleCatalog.track2;

  late FakeAudioPlayerService audio;
  late PlaybackProvider playback;
  late _FakeControls controls;
  late MediaControlsSync sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    audio = FakeAudioPlayerService();
    playback = PlaybackProvider(audio, storage, random: Random(1), audioLoader: FakeTrackAudioSource());
    controls = _FakeControls();
    sync = MediaControlsSync(playback, controls);
  });

  tearDown(() {
    sync.dispose();
    playback.dispose();
  });

  test('曲目变化才下发曲目信息；播放状态变化才下发状态', () async {
    expect(controls.tracks, isEmpty);
    await playback.playTrack(a, contextQueue: [a, b]);
    expect(controls.tracks.whereType<MediaTrackInfo>().map((t) => t.title), [a.name]);
    expect(controls.tracks.last!.artist, a.artistNames);
    expect(controls.playbacks.last.canNext, isTrue);

    audio.stateController.add(PlayerState(true, ProcessingState.ready));
    expect(controls.playbacks.last.playing, isTrue);
    final count = controls.playbacks.length;

    // 小幅进度推进不下发（系统端由周期更新处理）
    audio.positionController.add(const Duration(milliseconds: 500));
    expect(controls.playbacks.length, count);

    // 跳转立即下发
    audio.positionController.add(const Duration(seconds: 90));
    expect(controls.playbacks.length, count + 1);
    expect(controls.playbacks.last.position, const Duration(seconds: 90));
  });

  test('系统按键转给播放器', () async {
    await playback.playTrack(a, contextQueue: [a, b]);
    audio.stateController.add(PlayerState(true, ProcessingState.ready));

    // 已在播放时再收到「播放」不应切成暂停
    controls.controller.add(const MediaButtonEvent(MediaButton.play));
    await Future<void>.delayed(Duration.zero);
    expect(audio.isPlaying, isTrue);

    controls.controller.add(const MediaButtonEvent(MediaButton.next));
    await Future<void>.delayed(Duration.zero);
    expect(playback.currentTrack?.id, b.id);

    controls.controller.add(const MediaSeekEvent(Duration(seconds: 30)));
    await Future<void>.delayed(Duration.zero);
    expect(audio.seeks.last, const Duration(seconds: 30));
  });
}
