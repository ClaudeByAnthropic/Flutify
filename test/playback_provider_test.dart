import 'dart:math';

import 'package:flutify_app/core/constants/mock_spotify_data.dart';
import 'package:flutify_app/models/playback_context.dart';
import 'package:flutify_app/models/playback_state.dart';
import 'package:flutify_app/providers/playback_provider.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player_service.dart';

void main() {
  late FakeAudioPlayerService audio;
  late PlaybackProvider playback;

  const a = MockSpotifyData.trackBlindingLights;
  const b = MockSpotifyData.trackCruelSummer;
  const c = MockSpotifyData.trackBirdsOfAFeather;
  const x = MockSpotifyData.trackLevitating;
  const ctx = PlaybackContext.playlist('Test', uri: 'spotify:playlist:test');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    audio = FakeAudioPlayerService();
    playback = PlaybackProvider(audio, storage, random: Random(42));
  });

  tearDown(() => playback.dispose());

  test('position updates do not trigger ChangeNotifier rebuilds', () {
    var notifications = 0;
    var positionUpdates = 0;
    playback.addListener(() => notifications++);
    playback.positionNotifier.addListener(() => positionUpdates++);

    for (var i = 1; i <= 20; i++) {
      audio.positionController.add(Duration(milliseconds: i * 200));
    }

    expect(notifications, 0);
    expect(positionUpdates, 20);
    expect(playback.position, const Duration(milliseconds: 4000));
  });

  test('user queue plays before the rest of the context', () async {
    await playback.playTrack(a, contextQueue: [a, b, c], context: ctx);
    playback.addToQueue(x);

    expect(playback.userQueue.map((e) => e.track.id), [x.id]);
    expect(playback.upNext.map((e) => e.track.id), [b.id, c.id]);

    await playback.nextTrack();
    expect(playback.currentTrack?.id, x.id);
    expect(playback.userQueue, isEmpty);

    await playback.nextTrack();
    expect(playback.currentTrack?.id, b.id);
  });

  test('previous restarts the track when more than 3 seconds in', () async {
    await playback.playTrack(b, contextQueue: [a, b, c], context: ctx);
    audio.positionController.add(const Duration(seconds: 10));

    await playback.previousTrack();
    expect(playback.currentTrack?.id, b.id);
    expect(audio.seeks.last, Duration.zero);

    audio.positionController.add(const Duration(seconds: 1));
    await playback.previousTrack();
    expect(playback.currentTrack?.id, a.id);
  });

  test('shuffle keeps the current track and queues every other track once', () async {
    await playback.playTrack(b, contextQueue: [a, b, c, x], context: ctx);
    playback.toggleShuffle();

    expect(playback.currentTrack?.id, b.id);
    final upNextIds = playback.upNext.map((e) => e.track.id).toSet();
    expect(upNextIds, {a.id, c.id, x.id});

    playback.toggleShuffle();
    expect(playback.upNext.map((e) => e.track.id), [c.id, x.id]);
  });

  test('repeat context wraps around, repeat off stops at the end', () async {
    await playback.playTrack(c, contextQueue: [a, b, c], context: ctx);

    await playback.nextTrack();
    expect(playback.currentTrack?.id, c.id, reason: 'repeat off: stays on last track');

    playback.cycleRepeatMode();
    expect(playback.repeatMode, SpotifyRepeatMode.context);
    await playback.nextTrack();
    expect(playback.currentTrack?.id, a.id);
  });

  test('duplicate completed events only advance once', () async {
    await playback.playTrack(a, contextQueue: [a, b, c], context: ctx);
    audio.emitCompleted();
    audio.emitCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(playback.currentTrack?.id, b.id);
  });

  test('up next can be reordered and trimmed without touching the context', () async {
    await playback.playTrack(a, contextQueue: [a, b, c, x], context: ctx);

    playback.reorderUpNext(2, 0);
    expect(playback.upNext.map((e) => e.track.id), [x.id, b.id, c.id]);

    playback.removeFromUpNext(1);
    expect(playback.upNext.map((e) => e.track.id), [x.id, c.id]);

    await playback.playFromUpNext(1);
    expect(playback.currentTrack?.id, c.id);
    expect(playback.upNext, isEmpty);
  });

  test('isPlayingContext reflects the active context uri', () async {
    await playback.playTrack(a, contextQueue: [a, b], context: ctx);
    audio.stateController.add(PlayerState(true, ProcessingState.ready));

    expect(playback.isPlayingContext(ctx.uri), isTrue);
    expect(playback.isPlayingContext('spotify:album:other'), isFalse);
  });
}
