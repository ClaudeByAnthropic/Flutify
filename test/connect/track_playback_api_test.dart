import 'dart:convert';

import 'package:flutify_app/models/audio_playback_info.dart';
import 'package:flutify_app/services/connect/receiver/track_playback_api.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'state reports real format, omits unknown quality, decodes UTF-8 titles',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final api = TrackPlaybackApi(
        deviceId: 'test',
        webToken: () async => 'test',
        client: MockClient((r) async {
          if (r.url.host == 'clienttoken.spotify.com')
            return http.Response('{"granted_token":{"token":"test"}}', 200);
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response.bytes(
            utf8.encode('{"name":"中文・日本語 🎵"}'),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final response = await api.putState(
        debugSource: 'resume',
        audio: const AudioPlaybackInfo(bitrate: 256000, format: 11),
      );
      expect(response!['name'], '中文・日本語 🎵');
      expect(bodies.last['sub_state']['bitrate'], 256000);
      expect(bodies.last['sub_state']['format'], 11);
      expect(bodies.last['sub_state'].containsKey('audio_quality'), isFalse);
      await api.putState(debugSource: 'before_track_load');
      expect(bodies.last['sub_state'].containsKey('bitrate'), isFalse);
      expect(bodies.last['sub_state'].containsKey('format'), isFalse);
    },
  );

  test(
    'receiver installation ID persists across restarts and logout',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = await StorageService.init();
      final id = first.receiverDeviceId;
      expect(id, matches(RegExp(r'^[a-f0-9]{40}$')));
      await first.clearLogin();
      expect((await StorageService.init()).receiverDeviceId, id);
      SharedPreferences.setMockInitialValues({});
      expect((await StorageService.init()).receiverDeviceId, isNot(id));
    },
  );
}
