import 'dart:async';
import 'dart:typed_data';

import 'package:flutify_app/services/audio/audio_engine.dart';
import 'package:flutify_app/services/eme/cenc_audio.dart';
import 'package:flutify_app/services/eme/license_client.dart';
import 'package:flutify_app/services/eme/windows_native_audio_engine.dart';
import 'package:flutify_app/services/eme/windows_native_decryptor.dart';
import 'package:flutify_app/services/protocol/progressive_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'fakes/fake_audio_player_service.dart';

class Decryptor implements NativeAudioDecryptor {
  final pending = <Completer<NativeMemoryAudio>>[];
  @override
  Future<NativeMemoryAudio> decrypt(EmeTrackContent content) {
    final task = Completer<NativeMemoryAudio>();
    pending.add(task);
    return task.future;
  }

  @override
  void cancel() {}
}

class DelayedPlayer extends FakeAudioPlayerService {
  final loading = Completer<void>();
  final release = Completer<void>();
  var calls = 0;
  @override
  Future<void> playStream(
    ProgressiveAudio audio, {
    Duration? initialPosition,
    bool autoplay = true,
  }) async {
    if (calls++ == 0) {
      loading.complete();
      await release.future;
    }
    await super.playStream(
      audio,
      initialPosition: initialPosition,
      autoplay: autoplay,
    );
  }
}

void main() {
  const content = EmeTrackContent(
    fileIdHex: '0000000000000000000000000000000000000000',
    m4aPath: 'encrypted.m4a',
    m3u8: '#EXTM3U',
  );
  late Decryptor decryptor;
  late FakeAudioPlayerService native, fallback;
  late WindowsNativeAudioEngine engine;
  setUp(() {
    decryptor = Decryptor();
    native = FakeAudioPlayerService();
    fallback = FakeAudioPlayerService();
    engine = WindowsNativeAudioEngine(
      native: native,
      fallback: fallback,
      decryptor: decryptor,
    );
  });
  tearDown(() => engine.dispose());

  test('fallback logs specific safe codes for scheme and HTTP failures', () async {
    final logs = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = originalPrint);
    for (final error in [
      const CencFormatException(CencFormatFailure.unsupportedEncryptionScheme),
      LicenseHttpException(403, isCertificate: false),
    ]) {
      engine.dispose();
      engine = WindowsNativeAudioEngine(
        native: native,
        fallback: fallback,
        decryptor: decryptor,
      );
      final playing = engine.playEme(content, autoplay: false);
      decryptor.pending.last.completeError(error);
      await playing;
    }
    expect(logs.join('\n'), contains('unsupportedEncryptionScheme'));
    expect(logs.join('\n'), contains('license_http_403'));
    expect(fallback.playedEme, [content, content]);
  });

  test(
    'native success honors pause, seek and volume during license wait',
    () async {
      final playing = engine.playEme(content);
      await engine.pause();
      await engine.seek(const Duration(seconds: 30));
      await engine.setVolume(.25);
      decryptor.pending.single.complete(NativeMemoryAudio(Uint8List(8)));
      await playing;
      expect(native.playedFiles, ['stream']);
      expect(fallback.playedEme, isEmpty);
      expect(native.initialPositions, [const Duration(seconds: 30)]);
      expect(native.lastVolume, .25);
      expect(engine.isPlaying, isFalse);
      await engine.play();
      expect(engine.isPlaying, isTrue);
    },
  );
  test(
    'license failure falls back once and disables further native attempts',
    () async {
      final playing = engine.playEme(content, autoplay: false);
      decryptor.pending.single.completeError(StateError('license refused'));
      await playing;
      expect(fallback.playedEme, [content]);
      expect(engine.isPlaying, isFalse);
      await engine.playEme(content);
      expect(decryptor.pending.length, 1);
      expect(fallback.playedEme, [content, content]);
    },
  );
  test(
    'stop during license request never starts late audio or fallback',
    () async {
      final playing = engine.playEme(content);
      await engine.stop();
      final memory = NativeMemoryAudio(Uint8List(8));
      decryptor.pending.single.complete(memory);
      await playing;
      expect(native.playedFiles, isEmpty);
      expect(fallback.playedEme, isEmpty);
      expect(memory.length, 0);
    },
  );
  test('next track wins even if previous decrypt finishes last', () async {
    final first = engine.playEme(content);
    final second = engine.playEme(content);
    decryptor.pending[1].complete(NativeMemoryAudio(Uint8List(8)));
    await second;
    final stale = NativeMemoryAudio(Uint8List(8));
    decryptor.pending[0].complete(stale);
    await first;
    expect(native.playedFiles, ['stream']);
    expect(stale.length, 0);
    expect(fallback.playedEme, isEmpty);
  });
  test(
    'memory audio supports byte ranges and releases its session once',
    () async {
      var releases = 0;
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final audio = NativeMemoryAudio(bytes, onDispose: () => releases++);
      expect(await audio.read(1, 4).expand((chunk) => chunk).toList(), [
        2,
        3,
        4,
      ]);
      audio.dispose();
      audio.dispose();
      expect(bytes, [0, 0, 0, 0, 0]);
      expect(releases, 1);
      await expectLater(audio.read(0).drain<void>(), throwsException);
    },
  );
  test(
    'seek during decoder loading is applied when the source is ready',
    () async {
      engine.dispose();
      final delayed = DelayedPlayer();
      engine = WindowsNativeAudioEngine(
        native: delayed,
        fallback: FakeAudioPlayerService(),
        decryptor: decryptor,
      );
      final playing = engine.playEme(content);
      decryptor.pending.single.complete(NativeMemoryAudio(Uint8List(8)));
      await delayed.loading.future;
      await engine.seek(const Duration(seconds: 42));
      await engine.pause();
      delayed.release.complete();
      await playing;
      expect(delayed.seeks, [const Duration(seconds: 42)]);
      expect(engine.isPlaying, isFalse);
    },
  );
  test(
    'next track waits for a pending decoder before releasing its memory',
    () async {
      engine.dispose();
      final delayed = DelayedPlayer();
      engine = WindowsNativeAudioEngine(
        native: delayed,
        fallback: FakeAudioPlayerService(),
        decryptor: decryptor,
      );
      final first = engine.playEme(content);
      final stale = NativeMemoryAudio(Uint8List(8));
      decryptor.pending.single.complete(stale);
      await delayed.loading.future;
      final second = engine.playEme(content, autoplay: false);
      expect(stale.length, 8);
      delayed.release.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(stale.length, 0);
      final current = NativeMemoryAudio(Uint8List(12));
      decryptor.pending[1].complete(current);
      await second;
      expect(current.length, 12);
      expect(engine.isPlaying, isFalse);
      expect(delayed.calls, 2);
    },
  );
}
