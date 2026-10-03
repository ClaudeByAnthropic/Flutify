import 'dart:async';
import 'dart:convert';

import 'package:flutify_app/models/playback_state.dart';
import 'package:flutify_app/models/playback_context.dart';
import 'package:flutify_app/models/track.dart';
import 'package:flutify_app/providers/playback_provider.dart';
import 'package:flutify_app/services/connect/dealer_client.dart';
import 'package:flutify_app/services/connect/receiver/connect_receiver.dart';
import 'package:flutify_app/services/connect/receiver/playback_receiver_host.dart';
import 'package:flutify_app/services/connect/receiver/track_playback_state.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/services/protocol/track_audio_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_audio_player_service.dart';
import '../fakes/fake_dealer.dart';
import '../fakes/fake_track_audio_source.dart';

class _DelayedLoader extends FakeTrackAudioSource {
  final gates = <String, Completer<void>>{};
  @override
  Future<LoadedAudio> open(
    String trackIdOrUri, {
    void Function(double)? progress,
  }) async {
    final audio = await super.open(trackIdOrUri, progress: progress);
    await gates[trackIdOrUri]?.future;
    return audio;
  }
}

class _DelayedAudio extends FakeAudioPlayerService {
  Completer<void>? sourceGate;
  Object? playError;
  int sourceLoads = 0;

  @override
  Future<void> play() async {
    if (playError case final error?) throw error;
    await super.play();
  }

  @override
  Future<void> playFile(
    String path, {
    Duration? initialPosition,
    bool autoplay = true,
  }) async {
    sourceLoads++;
    await sourceGate?.future;
    await super.playFile(
      path,
      initialPosition: initialPosition,
      autoplay: autoplay,
    );
  }
}

Map<String, Object?> machine(List<String> ids, {Map<String, bool>? options}) =>
    {
      'state_machine_id': ids.join('-'),
      if (options != null) 'attributes': {'options': options},
      'tracks': [
        for (final id in ids)
          {
            'metadata': {
              'uri': 'spotify:track:$id',
              'name': id,
              'duration': 180000,
            },
          },
      ],
      'states': [
        for (var i = 0; i < ids.length; i++)
          {
            'state_id': ids[i],
            'track': i,
            'transitions': {
              if (i + 1 < ids.length) 'advance': {'state_index': i + 1},
              if (i + 1 < ids.length) 'skip_next': {'state_index': i + 1},
              if (i > 0) 'skip_prev': {'state_index': i - 1},
            },
          },
      ],
    };

void main() {
  late PlaybackProvider playback;
  late PlaybackReceiverHost host;
  late ConnectReceiver receiver;
  late DealerClient dealer;
  late FakeDealerServer server;
  late _DelayedAudio audio;
  late _DelayedLoader loader;
  Future<http.Response> Function(http.Request)? report;
  Future<http.Response> Function(http.Request)? registration;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    audio = _DelayedAudio();
    loader = _DelayedLoader();
    playback = PlaybackProvider(
      audio,
      await StorageService.init(),
      audioLoader: loader,
    );
    host = PlaybackReceiverHost(
      playback,
      handoverRetryDelay: const Duration(milliseconds: 5),
    );
    server = FakeDealerServer();
    report = null;
    registration = null;
    final client = MockClient((r) async {
      if (r.url.host == 'clienttoken.spotify.com') {
        return http.Response(
          jsonEncode({
            'granted_token': {'token': 'test'},
          }),
          200,
        );
      }
      if (r.method == 'POST') {
        return registration?.call(r) ??
            http.Response('{"initial_seq_num":0}', 200);
      }
      if (r.method == 'PUT' && r.url.path.endsWith('/state')) {
        return report?.call(r) ?? http.Response('', 204);
      }
      return http.Response('{}', 200);
    });
    dealer = DealerClient(
      client: client,
      headers: () async => {'Authorization': 'Bearer test'},
      connector: server.connect,
      initialBackoff: const Duration(milliseconds: 5),
      maxBackoff: const Duration(milliseconds: 10),
    );
    receiver = ConnectReceiver(
      host: host,
      deviceName: () => 'Test',
      client: client,
      webToken: () async => 'test',
      deviceId: 'test',
      dealer: dealer,
      registerRetryDelay: const Duration(milliseconds: 5),
    );
    host.receiver = receiver;
    final registered = Completer<void>();
    receiver.onRegistered = () {
      if (!registered.isCompleted) registered.complete();
    };
    await receiver.start();
    await registered.future;
  });

  tearDown(() async {
    await receiver.stop();
    host.dispose();
    playback.dispose();
    await dealer.dispose();
  });

  void replace(List<String> ids, {Map<String, bool>? options, int? seek}) {
    server.channels.last.pushJson('hm://track-playback/v1/command', {
      'type': 'replace_state',
      'state_machine': machine(ids, options: options),
      'state_ref': {'state_index': 0, 'paused': false},
      if (seek != null) 'seek_to': seek,
    });
  }

  test('late load cannot overwrite the latest track or queue', () async {
    loader.gates['a'] = Completer<void>();
    replace(['a', 'b']);
    await until(() => loader.loaded.contains('a'));
    replace(['x', 'y']);
    await until(
      () => playback.currentTrack?.id == 'x' && !playback.isBuffering,
    );
    loader.gates['a']!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(playback.currentTrack?.id, 'x');
    expect(playback.upNext.map((e) => e.track.id), ['y']);
    expect(audio.playedFiles, [contains('x')]);
  });

  test(
    'initial receiver playback retains the selected playlist beyond its two-track window',
    () async {
      const context = PlaybackContext.playlist(
        'Full playlist',
        uri: 'spotify:playlist:test',
      );
      final tracks = [
        for (final id in ['a', 'b', 'c', 'd'])
          SpotifyTrack(id: id, uri: 'spotify:track:$id', name: id),
      ];
      playback.prepareReceiverQueue(context, tracks, tracks[1]);
      replace(['b', 'c'], options: {'shuffling_context': false});
      await until(
        () => playback.currentTrack?.id == 'b' && !playback.isBuffering,
      );
      expect(playback.upNext.map((e) => e.track.id), ['c', 'd']);
      expect(playback.playbackContext.name, 'Full playlist');
      expect(loader.loaded, ['b']);
      replace(['c', 'd']);
      await until(
        () => playback.currentTrack?.id == 'c' && !playback.isBuffering,
      );
      expect(playback.upNext.map((e) => e.track.id), ['d']);
      expect(playback.playbackContext.name, 'Full playlist');
      await playback.previousTrack();
      expect(playback.currentTrack?.id, 'b');
    },
  );

  test(
    'same current track accepts a new full context without reloading audio',
    () async {
      replace(['a', 'b']);
      await until(
        () => playback.currentTrack?.id == 'a' && !playback.isBuffering,
      );
      final tracks = [
        for (final id in ['a', 'c', 'd'])
          SpotifyTrack(id: id, uri: 'spotify:track:$id', name: id),
      ];
      playback.prepareReceiverQueue(
        const PlaybackContext.playlist('Other'),
        tracks,
        tracks.first,
      );
      replace(['a', 'c']);
      await until(() => playback.upNext.length == 2);
      expect(playback.upNext.map((e) => e.track.id), ['c', 'd']);
      expect(playback.playbackContext.name, 'Other');
      expect(loader.loaded, ['a']);
    },
  );

  for (final shuffled in [false, true]) {
    test(
      'receiver ${shuffled ? 'shuffle' : 'changed order'} does not append an invented playlist tail',
      () async {
        final tracks = [
          for (final id in ['a', 'b', 'c', 'd'])
            SpotifyTrack(id: id, uri: 'spotify:track:$id', name: id),
        ];
        final old = playback.prepareReceiverQueue(
          const PlaybackContext.playlist('Old'),
          tracks,
          tracks[1],
        );
        playback.prepareReceiverQueue(
          const PlaybackContext.playlist('New'),
          tracks,
          tracks.first,
        );
        playback.cancelReceiverQueue(old);
        replace(
          ['a', shuffled ? 'b' : 'c'],
          options: {'shuffling_context': shuffled},
        );
        await until(
          () => playback.currentTrack?.id == 'a' && !playback.isBuffering,
        );
        expect(playback.upNext.map((e) => e.track.id), [shuffled ? 'b' : 'c']);
        expect(playback.playbackContext.name, 'New');
      },
    );
  }

  test(
    'transfer away cancels loading; resume retains the requested seek position',
    () async {
      loader.gates['a'] = Completer<void>();
      replace(['a', 'b']);
      await until(() => loader.loaded.contains('a'));
      await host.sync(positionMs: 42000, paused: true);
      loader.gates['a']!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(audio.playedFiles, isEmpty);
      expect(audio.isPlaying, isFalse);
      await host.sync(positionMs: null, paused: false);
      expect(audio.initialPositions.single, const Duration(seconds: 42));
      expect(audio.isPlaying, isTrue);
    },
  );

  test('stop immediately after load prevents audio from starting', () async {
    final m = TpStateMachine.fromJson(machine(['a', 'b']))!;
    final loading = host.load(m, [0, 1], positionMs: 0, paused: false);
    await host.stop();
    await loading;
    expect(audio.playedFiles, isEmpty);
    expect(audio.isPlaying, isFalse);
    expect(playback.isBuffering, isFalse);
  });

  test(
    'pause while the audio engine loads a source prevents late autoplay',
    () async {
      audio.sourceGate = Completer<void>();
      final m = TpStateMachine.fromJson(machine(['a', 'b']))!;
      final loading = host.load(m, [0, 1], positionMs: 10000, paused: false);
      await until(() => audio.sourceLoads == 1);
      await host.sync(positionMs: 42000, paused: true);
      audio.sourceGate!.complete();
      await loading;
      expect(audio.isPlaying, isFalse);
      expect(playback.isBuffering, isFalse);
      await host.sync(positionMs: null, paused: false);
      expect(audio.initialPositions.last, const Duration(seconds: 42));
      expect(audio.isPlaying, isTrue);
    },
  );

  test(
    'seek while the audio engine loads is applied before playback starts',
    () async {
      audio.sourceGate = Completer<void>();
      final m = TpStateMachine.fromJson(machine(['a', 'b']))!;
      final loading = host.load(m, [0, 1], positionMs: 10000, paused: false);
      await until(() => audio.sourceLoads == 1);
      await host.sync(positionMs: 42000, paused: false);
      audio.sourceGate!.complete();
      await loading;
      expect(audio.seeks.single, const Duration(seconds: 42));
      expect(playback.position, const Duration(seconds: 42));
      expect(audio.isPlaying, isTrue);
    },
  );

  test(
    'asynchronous audio start failure is reported and can be retried',
    () async {
      audio.playError = StateError('audio device unavailable');
      final m = TpStateMachine.fromJson(machine(['a']))!;
      await host.load(m, [0], positionMs: 10000, paused: false);
      await until(() => playback.playbackError != null);
      expect(playback.isBuffering, isFalse);
      expect(audio.isPlaying, isFalse);
      audio.playError = null;
      await host.sync(positionMs: null, paused: false);
      expect(playback.playbackError, isNull);
      expect(audio.isPlaying, isTrue);
    },
  );

  test(
    'paused replacement cancels old load without leaving the new track buffering',
    () async {
      loader.gates['a'] = Completer<void>();
      replace(['a', 'b']);
      await until(() => loader.loaded.contains('a'));
      final m = TpStateMachine.fromJson(machine(['x', 'y']))!;
      await host.load(m, [0, 1], positionMs: 10000, paused: true);
      loader.gates['a']!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(playback.currentTrack?.id, 'x');
      expect(playback.isBuffering, isFalse);
      expect(audio.isPlaying, isFalse);
      await host.sync(positionMs: null, paused: false);
      expect(audio.playedFiles, [contains('x')]);
      expect(audio.initialPositions.single, const Duration(seconds: 10));
    },
  );

  test(
    'failed receiver registration retries on the same reconnected dealer',
    () async {
      var calls = 0;
      var registered = 0;
      receiver.onRegistered = () => registered++;
      registration = (_) async => ++calls < 3
          ? http.Response('temporary', 503)
          : http.Response('{"initial_seq_num":7}', 200);
      server.channels.last.drop();
      await until(() => registered == 1);
      expect(calls, 3);
      expect(server.channels.length, 2);
    },
  );

  test(
    'local handover retries temporary failure and stops after success',
    () async {
      var attempts = 0;
      host.handOver = (_) async => ++attempts >= 2;
      final m = TpStateMachine.fromJson(machine(['a']))!;
      await host.load(m, [0], positionMs: 0, paused: false);
      audio.stateController.add(PlayerState(true, ProcessingState.ready));
      await until(() => attempts == 2);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      playback.setVolume(0.5);
      expect(attempts, 2);
    },
  );

  test(
    'handover retries are bounded and registration can recover the same track',
    () async {
      var attempts = 0;
      host.handOver = (_) async {
        attempts++;
        return false;
      };
      final m = TpStateMachine.fromJson(machine(['a']))!;
      await host.load(m, [0], positionMs: 0, paused: false);
      audio.stateController.add(PlayerState(true, ProcessingState.ready));
      await until(() => attempts == 3);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(attempts, 3);
      host.handOver = (_) async {
        attempts++;
        return true;
      };
      host.onReceiverRegistered();
      await until(() => attempts == 4);
    },
  );

  test(
    'stopping during registration ignores late success and schedules no retry',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      var registered = 0;
      receiver.onRegistered = () => registered++;
      registration = (_) {
        calls++;
        return response.future;
      };
      server.channels.last.drop();
      await until(() => calls == 1);
      await receiver.stop();
      response.complete(http.Response('{"initial_seq_num":7}', 200));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(registered, 0);
      expect(calls, 1);
    },
  );

  test(
    'expanded state report reaches local queue without reloading current track',
    () async {
      report = (_) async => http.Response(
        jsonEncode({
          'state_machine': machine(['a', 'b', 'c', 'd']),
          'updated_state_ref': {'state_index': 0},
        }),
        200,
      );
      replace(['a', 'b']);
      await until(() => playback.upNext.length == 3);
      expect(loader.loaded, ['a']);
      await playback.nextTrack();
      expect(playback.currentTrack?.id, 'b');
      expect(playback.canSkipNext, isTrue);
    },
  );

  test(
    'same-track replacement updates queue and absent options preserve repeat',
    () async {
      replace(['a', 'b'], options: {'repeating_context': true});
      await until(
        () => playback.currentTrack?.id == 'a' && !playback.isBuffering,
      );
      replace(['a', 'b', 'c']);
      await until(() => playback.upNext.length == 2);
      expect(loader.loaded, ['a']);
      expect(playback.repeatMode, SpotifyRepeatMode.context);
      replace(
        ['a', 'c'],
        options: {'repeating_context': false, 'repeating_track': false},
      );
      await until(() => playback.repeatMode == SpotifyRepeatMode.off);
      expect(playback.upNext.single.track.id, 'c');
    },
  );

  test('response from an older command cannot replace a newer queue', () async {
    final response = Completer<http.Response>();
    var calls = 0;
    report = (_) async {
      if (++calls == 1) return response.future;
      return http.Response('', 204);
    };
    replace(['a', 'b']);
    await until(() => calls == 1 && playback.currentTrack?.id == 'a');
    replace(['x', 'y']);
    await until(() => playback.currentTrack?.id == 'x');
    response.complete(
      http.Response(
        jsonEncode({
          'state_machine': machine(['a', 'b', 'c']),
          'updated_state_ref': {'state_index': 0},
        }),
        200,
      ),
    );
    await until(() => calls > 1);
    expect(playback.currentTrack?.id, 'x');
    expect(playback.upNext.single.track.id, 'y');
  });

  test('single-track repeat still exposes the manual next transition', () {
    final json = machine(['a', 'b']);
    final states = json['states'] as List;
    (states[0]['transitions'] as Map)['advance'] = {'state_index': 0};
    expect(TpStateMachine.fromJson(json)!.advanceChain(0), [0, 1]);
  });

  test('missing advance still follows a valid manual next transition', () {
    final json = machine(['a', 'b', 'c']);
    final states = json['states'] as List;
    (states[0]['transitions'] as Map).remove('advance');
    expect(TpStateMachine.fromJson(json)!.advanceChain(0), [0, 1, 2]);
  });

  test('leaving the receiver queue reports a cleared state', () async {
    final reports = <Map<String, dynamic>>[];
    report = (request) async {
      reports.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('', 204);
    };
    replace(['a', 'b']);
    await until(
      () => playback.currentTrack?.id == 'a' && !playback.isBuffering,
    );
    receiver.onLocalTrackChanged('spotify:track:outside', durationMs: 180000);
    await until(() => reports.any((r) => r['debug_source'] == 'state_clear'));
    expect(receiver.isActive, isFalse);
    expect(reports.last['state_ref'], isNull);
  });
}
