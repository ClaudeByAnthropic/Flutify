import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/audio/audio_engine.dart';
import 'package:flutify_app/services/eme/eme_audio_engine.dart';
import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingPlayer extends EmePlayer {
  final events = <String>[];
  @override
  Future<void> play({
    required File m4a,
    required String m3u8,
    required Future<Uint8List> Function(Uint8List) licensePoster,
    required Future<Uint8List> Function() certFetcher,
  }) async => events.add('play');
  @override
  Future<void> setVolume(double volume) async => events.add('volume:$volume');
}

void main() {
  const content = EmeTrackContent(m4aPath: 'unused.m4a', m3u8: '#EXTM3U');

  test(
    'desktop DRM initializes on demand and restores volume before playback',
    () async {
      final ready = Completer<void>();
      final player = RecordingPlayer();
      var starts = 0;
      final engine = EmeAudioEngine(
        player: player,
        licensePoster: (bytes) async => bytes,
        certFetcher: () async => Uint8List(0),
        initialize: () {
          starts++;
          return ready.future;
        },
      );
      addTearDown(engine.dispose);
      expect(starts, 0);
      await engine.setVolume(0.25);
      player.events.clear();
      final playing = engine.playEme(content);
      expect(starts, 1);
      expect(player.events, isEmpty);
      ready.complete();
      await playing;
      expect(player.events, ['volume:0.25', 'play']);
      await engine.playEme(content);
      expect(starts, 1);
    },
  );

  test(
    'failed initialization exposes the error and retries on next playback',
    () async {
      final player = RecordingPlayer();
      var starts = 0;
      final engine = EmeAudioEngine(
        player: player,
        licensePoster: (bytes) async => bytes,
        certFetcher: () async => Uint8List(0),
        initialize: () async {
          if (++starts == 1) throw StateError('WebView unavailable');
        },
      );
      addTearDown(engine.dispose);
      await expectLater(engine.playEme(content), throwsStateError);
      expect(player.events, isEmpty);
      await engine.playEme(content);
      expect(starts, 2);
      expect(player.events.last, 'play');
    },
  );
}
