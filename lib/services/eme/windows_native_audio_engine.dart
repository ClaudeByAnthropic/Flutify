import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/audio_engine.dart';
import '../protocol/progressive_download.dart';
import 'cenc_audio.dart';
import 'license_client.dart';
import 'windows_native_decryptor.dart';
import 'windows_cdm_process.dart';

/// Opt-in Windows experiment. Native failures disable further attempts for the
/// current app run and switch to the existing EME engine. Generation checks
/// prevent a slow license response from starting a track after stop/next.
class WindowsNativeAudioEngine implements AudioEngine {
  WindowsNativeAudioEngine({
    required AudioEngine native,
    required AudioEngine fallback,
    required NativeAudioDecryptor decryptor,
  }) : _native = native,
       _fallback = fallback,
       _decryptor = decryptor {
    for (final engine in [_native, _fallback]) {
      _subscriptions.add(
        engine.positionStream.listen((value) {
          if (identical(_active, engine)) _positions.add(value);
        }),
      );
      _subscriptions.add(
        engine.durationStream.listen((value) {
          if (identical(_active, engine)) _durations.add(value);
        }),
      );
      _subscriptions.add(
        engine.playerStateStream.listen((value) {
          if (identical(_active, engine) && !_loading) _states.add(value);
        }),
      );
      _subscriptions.add(
        engine.emeErrors.listen((error) {
          if (identical(_active, engine)) _errors.add(error);
        }),
      );
    }
  }

  final AudioEngine _native, _fallback;
  final NativeAudioDecryptor _decryptor;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  final _errors = StreamController<EmePlaybackException>.broadcast();
  AudioEngine? _active;
  NativeMemoryAudio? _audio;
  int _generation = 0;
  bool _disabled = false, _disposed = false, _loading = false, _autoplay = true;
  Duration? _pendingPosition;
  double _volume = 1;
  Future<void> _playerWork = Future.value();

  // Serialize source changes: a delayed decoder load/stop from the previous
  // track must finish before another track can touch the same player.
  Future<void> _withPlayer(Future<void> Function() work) {
    final result = _playerWork.then((_) => work());
    _playerWork = result.catchError((Object _) {});
    return result;
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration?> get durationStream => _durations.stream;
  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<EmePlaybackException> get emeErrors => _errors.stream;
  @override
  Duration get position => _loading
      ? _pendingPosition ?? Duration.zero
      : _active?.position ?? Duration.zero;
  @override
  Duration? get duration => _active?.duration;
  @override
  bool get isPlaying => !_loading && (_active?.isPlaying ?? false);
  @override
  bool get hasSource => !_loading && (_active?.hasSource ?? false);

  @override
  Future<void> playEme(
    EmeTrackContent content, {
    Duration? initialPosition,
    bool autoplay = true,
  }) async {
    if (_disposed) return;
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    _decryptor.cancel();
    _loading = true;
    _autoplay = autoplay;
    _pendingPosition = initialPosition;
    final previous = _active;
    final previousAudio = _audio;
    _audio = null;
    _active = null;
    if (previous != null || previousAudio != null) {
      await _withPlayer(() async {
        try {
          if (!_disposed) await previous?.stop();
        } finally {
          previousAudio?.dispose();
        }
      });
    }
    if (!current()) return;
    _positions.add(initialPosition ?? Duration.zero);
    _durations.add(null);
    _states.add(PlayerState(false, ProcessingState.loading));
    if (!_disabled) {
      NativeMemoryAudio? memory;
      try {
        memory = await _decryptor.decrypt(content);
        if (!current()) {
          memory.dispose();
          return;
        }
        await _withPlayer(() async {
          if (!current()) {
            memory!.dispose();
            return;
          }
          _audio = memory;
          _active = _native;
          await _native.setVolume(_volume);
          if (!current()) return;
          var initial = _pendingPosition;
          await _native.playStream(
            memory!,
            initialPosition: initial,
            autoplay: false,
          );
          // A seek may arrive while the decoder is still opening the source.
          while (current() && _pendingPosition != initial) {
            final target = _pendingPosition;
            if (target != null) await _native.seek(target);
            initial = target;
          }
        });
        if (!current()) return;
        _loading = false;
        _states.add(PlayerState(false, ProcessingState.ready));
        if (_autoplay) {
          unawaited(
            _native.play().catchError((Object error) {
              if (current()) {
                _errors.add(
                  EmePlaybackException(
                    'Native audio playback failed (${error.runtimeType})',
                  ),
                );
              }
            }),
          );
        }
        debugPrint(
          '[native-wv] Native audio ready (media_kit), WebView not used for this track',
        );
        return;
      } catch (error) {
        if (!current()) {
          memory?.dispose();
          return;
        }
        _disabled = true;
        _active = null;
        if (identical(_audio, memory)) _audio = null;
        await _withPlayer(() async {
          try {
            if (!_disposed) await _native.stop();
          } finally {
            memory?.dispose();
          }
        });
        if (!current()) return;
        // Only sanitized codes/types: never log opaque license or CDM payloads.
        debugPrint(
          '[native-wv] Experiment failed (${error is CdmException
              ? error.code
              : error is LicenseHttpException
              ? error.code
              : error is CencFormatException
              ? error.failure.name
              : error is FormatException
              ? 'unsupported_cenc'
              : error.runtimeType}); falling back to WebView for this app run',
        );
      }
    }
    if (!current()) return;
    try {
      await _withPlayer(() async {
        if (!current()) return;
        _active = _fallback;
        await _fallback.setVolume(_volume);
        if (!current()) return;
        var initial = _pendingPosition;
        await _fallback.playEme(
          content,
          initialPosition: initial,
          autoplay: false,
        );
        while (current() && _pendingPosition != initial) {
          final target = _pendingPosition;
          if (target != null) await _fallback.seek(target);
          initial = target;
        }
      });
      if (!current()) return;
      _loading = false;
      if (_autoplay) {
        unawaited(
          _fallback.play().catchError((Object error) {
            if (current()) {
              _errors.add(
                EmePlaybackException(
                  'Fallback playback failed (${error.runtimeType})',
                ),
              );
            }
          }),
        );
      }
      _states.add(PlayerState(_fallback.isPlaying, ProcessingState.ready));
    } catch (_) {
      if (current()) {
        _loading = false;
        _states.add(PlayerState(false, ProcessingState.idle));
      }
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    _autoplay = true;
    if (!_loading) await _active?.play();
  }

  @override
  Future<void> pause() async {
    _autoplay = false;
    if (!_loading) await _active?.pause();
  }

  @override
  Future<void> seek(Duration value) async {
    _pendingPosition = value;
    if (!_loading) await _active?.seek(value);
  }

  @override
  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 1);
    await _active?.setVolume(_volume);
  }

  @override
  Future<void> stop() async {
    final generation = ++_generation;
    _loading = false;
    _autoplay = false;
    _decryptor.cancel();
    final active = _active;
    _active = null;
    final memory = _audio;
    _audio = null;
    await _withPlayer(() async {
      try {
        if (!_disposed) await active?.stop();
      } finally {
        memory?.dispose();
      }
    });
    if (!_disposed && generation == _generation) {
      _states.add(PlayerState(false, ProcessingState.idle));
    }
  }

  @override
  Future<void> playFile(
    String path, {
    Duration? initialPosition,
    bool autoplay = true,
  }) => throw UnsupportedError('DRM engine');
  @override
  Future<void> playStream(
    ProgressiveAudio audio, {
    Duration? initialPosition,
    bool autoplay = true,
  }) => throw UnsupportedError('DRM engine');
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _decryptor.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _native.dispose();
    _fallback.dispose();
    _audio?.dispose();
    _audio = null;
    _positions.close();
    _durations.close();
    _states.close();
    _errors.close();
  }
}
