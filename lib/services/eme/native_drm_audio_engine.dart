import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../audio/audio_engine.dart';
import '../protocol/progressive_download.dart';
import 'eme_player.dart';
import 'native_drm_player.dart';

/// Android 原生 DRM 音频引擎：EmePlayer 只做本地回环 HTTP 服务（**不起 WebView**），
/// 实际解密/播放交给原生 ExoPlayer（Media3 + 设备 Widevine）。
///
/// 背景：部分 Android WebView 的 EME 在 createMediaKeys 阶段永不 settle（真机实测），
/// WebView 链路不可用；原生播放器不受此限制。接口与 [EmeAudioEngine] 完全一致，
/// 由 main.dart 按平台装配（Android → 本类，桌面 → EmeAudioEngine）。
class NativeDrmAudioEngine implements AudioEngine {
  /// 本地回环 HTTP 服务宿主（清单/加密 m4a/license·证书反代），不做 WebView 播放。
  final EmePlayer _server;
  final NativeDrmPlayer _player;

  /// license 反代：把 CDM 的 license 请求体 POST 到 Spotify，返回响应。
  final Future<Uint8List> Function(Uint8List request) _licensePoster;

  /// 取 Widevine application-certificate。
  final Future<Uint8List> Function() _certFetcher;

  NativeDrmAudioEngine({
    required EmePlayer server,
    required NativeDrmPlayer player,
    required Future<Uint8List> Function(Uint8List request) licensePoster,
    required Future<Uint8List> Function() certFetcher,
  }) : _server = server,
       _player = player,
       _licensePoster = licensePoster,
       _certFetcher = certFetcher {
    _player.positionStream.listen((p) {
      _position = p;
      _positionController.add(p);
    });
    _player.durationStream.listen((d) {
      _duration = d;
      _durationController.add(d);
    });
    _player.stateStream.listen(_onState);
  }

  // ---- 状态 ----
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _stateController = StreamController<PlayerState>.broadcast();
  final _errorController = StreamController<EmePlaybackException>.broadcast();

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  ProcessingState _processing = ProcessingState.idle;
  bool _hasSource = false;

  void _onState(EmePlayerState s) {
    switch (s) {
      case EmePlayerState.playing:
        _playing = true;
        _processing = ProcessingState.ready;
      case EmePlayerState.buffering:
        _processing = ProcessingState.buffering;
      case EmePlayerState.paused:
        _playing = false;
        _processing = ProcessingState.ready;
      case EmePlayerState.ended:
        _playing = false;
        _processing = ProcessingState.completed;
      case EmePlayerState.error:
        _playing = false;
        _processing = ProcessingState.idle;
        if (_hasSource) {
          // 运行期错误（license / DRM 会话失败等，在 play 返回后才暴露）：
          // 带上 [_player.lastError] 的原因上报给 PlaybackProvider 转成用户可见提示，
          // 并把 _hasSource 复位，让上层知道要重试必须重新整载
          _hasSource = false;
          _errorController.add(
            _player.lastError ?? const EmePlaybackException('unknown'),
          );
        }
    }
    _emit();
  }

  void _emit() {
    _stateController.add(PlayerState(_playing, _processing));
  }

  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration?> get durationStream => _durationController.stream;
  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;
  @override
  Stream<EmePlaybackException> get emeErrors => _errorController.stream;

  @override
  Duration get position => _position;
  @override
  Duration? get duration => _duration;
  @override
  bool get isPlaying => _playing;
  @override
  bool get hasSource => _hasSource;

  @override
  Future<void> playEme(
    EmeTrackContent content, {
    Duration? initialPosition,
    bool autoplay = true,
  }) async {
    _processing = ProcessingState.loading;
    _emit();
    // 起本地回环服务（清单按 ExoPlayer 需要把 KEYFORMAT 改写为 Widevine UUID）
    final urls = await _server.serveHlsForNative(
      m4a: File(content.m4aPath),
      m3u8: content.m3u8,
      licensePoster: _licensePoster,
      certFetcher: _certFetcher,
    );
    await _player.play(
      hlsUrl: urls.hlsUrl,
      licenseUrl: urls.licenseUrl,
      provisionUrl: urls.provisionUrl,
    );
    _hasSource = true;
    if (initialPosition != null && initialPosition > Duration.zero) {
      await _player.seek(initialPosition);
    }
  }

  // just_audio 路径在本引擎上不可用（路由层保证不调用）
  @override
  Future<void> playFile(
    String path, {
    Duration? initialPosition,
    bool autoplay = true,
  }) => throw UnimplementedError('原生 DRM 引擎不支持本地文件');
  @override
  Future<void> playStream(
    ProgressiveAudio audio, {
    Duration? initialPosition,
    bool autoplay = true,
  }) => throw UnimplementedError('原生 DRM 引擎不支持流式下载');

  @override
  Future<void> play() async {
    await _player.resume();
    _playing = true;
    _processing = ProcessingState.ready;
    _emit();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _playing = false;
    _emit();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> stop() async {
    await _player.stop();
    _playing = false;
    _processing = ProcessingState.idle;
    _hasSource = false;
    _emit();
  }

  @override
  void dispose() {
    _player.dispose();
  }
}
