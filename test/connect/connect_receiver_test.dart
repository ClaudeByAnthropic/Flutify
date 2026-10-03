import 'dart:async';
import 'dart:convert';

import 'package:flutify_app/models/playback_state.dart';
import 'package:flutify_app/providers/playback_provider.dart';
import 'package:flutify_app/services/connect/dealer_client.dart';
import 'package:flutify_app/services/connect/receiver/connect_receiver.dart';
import 'package:flutify_app/services/connect/receiver/playback_receiver_host.dart';
import 'package:flutify_app/services/connect/receiver/track_playback_state.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_audio_player_service.dart';
import '../fakes/fake_dealer.dart';
import '../fakes/fake_track_audio_source.dart';

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
  late FakeAudioPlayerService audio;
  late FakeTrackAudioSource loader;
  Future<http.Response> Function(http.Request)? report;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    audio = FakeAudioPlayerService();
    loader = FakeTrackAudioSource();
    playback = PlaybackProvider(
      audio,
      await StorageService.init(),
      audioLoader: loader,
    );
    host = PlaybackReceiverHost(playback);
    server = FakeDealerServer();
    report = null;
    final client = MockClient((r) async {
      if (r.url.host == 'clienttoken.spotify.com') {
        return http.Response(
          jsonEncode({
            'granted_token': {'token': 'test'},
          }),
          200,
        );
      }
      if (r.method == 'POST')
        return http.Response('{"initial_seq_num":0}', 200);
      if (r.method == 'PUT' && r.url.path.endsWith('/state')) {
        return report?.call(r) ?? http.Response('', 204);
      }
      return http.Response('{}', 200);
    });
    dealer = DealerClient(
      client: client,
      headers: () async => {'Authorization': 'Bearer test'},
      connector: server.connect,
    );
    receiver = ConnectReceiver(
      host: host,
      deviceName: () => 'Test',
      client: client,
      webToken: () async => 'test',
      deviceId: 'test',
      dealer: dealer,
    );
    host.receiver = receiver;
    final registered = Completer<void>();
    receiver.onRegistered = registered.complete;
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
    server.channels.single.pushJson('hm://track-playback/v1/command', {
      'type': 'replace_state',
      'state_machine': machine(ids, options: options),
      'state_ref': {'state_index': 0, 'paused': false},
      if (seek != null) 'seek_to': seek,
    });
  }

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
