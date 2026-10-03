import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../protocol/progressive_download.dart';

/// 一首 DRM 曲目的可播放内容（协议下载的加密 fMP4 + 本地化 HLS 清单 + 密钥反代）。
///
/// 由 EME 引擎（WebView2 + Widevine）播放，just_audio 无法解这种文件。
class EmeTrackContent {
  /// 加密 fMP4 的本地路径。
  final String m4aPath;

  /// sneaktables policy=1 原始 HLS 清单（含 EXT-X-KEY/MAP/BYTERANGE）。
  final String m3u8;

  const EmeTrackContent({required this.m4aPath, required this.m3u8});
}

/// EME 播放的运行期错误（license 换取失败 / HLS.js 致命错误 / Widevine 不可用等）。
///
/// 与加载失败不同，这类错误在音源就位后才暴露，经 [AudioEngine.emeErrors]
/// 冒泡给 PlaybackProvider，转成用户可见的提示（不再静默停在 0:00）。
class EmePlaybackException implements Exception {
  /// 错误细节（HLS.js details / license 失败原因），主要用于排查与归类。
  final String message;

  /// 设备缺 Widevine / CDM：解密无从谈起，重试无意义。
  final bool isWidevineMissing;

  /// sp_dc（Web 登录态）疑似失效（license / token 铸造被拒 401/403）：建议重新 Web 登录。
  final bool webSignInSuggested;

  /// 原始错误，仅用于日志排查。
  final Object? cause;

  const EmePlaybackException(
    this.message, {
    this.isWidevineMissing = false,
    this.webSignInSuggested = false,
    this.cause,
  });

  @override
  String toString() => message;
}

/// 统一音频引擎抽象：PlaybackProvider 只依赖它，不关心底层是 just_audio 还是 EME。
///
/// 流与方法对齐 just_audio 的语义（PlayerState / ProcessingState 复用 just_audio 的类型），
/// 便于测试用 Fake 实现、也便于在两种引擎间切换。
abstract class AudioEngine {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<PlayerState> get playerStateStream;

  /// EME 运行期错误流（license 换取失败 / HLS 致命错误 / Widevine 不可用）。
  /// 仅 EME 引擎产生事件；本地（just_audio）引擎保持空流。
  Stream<EmePlaybackException> get emeErrors;

  Duration get position;
  Duration? get duration;
  bool get isPlaying;

  /// 是否已加载音源。
  bool get hasSource;

  /// 播放本地已解密音频文件（OGG/MP3 等）。
  Future<void> playFile(String path, {Duration? initialPosition, bool autoplay = true});

  /// 边下边播（仍在下载的曲目）。
  Future<void> playStream(ProgressiveAudio audio, {Duration? initialPosition, bool autoplay = true});

  /// 播放 DRM 曲目（EME / Widevine）。默认不支持（仅 EME 引擎实现）。
  Future<void> playEme(EmeTrackContent content, {Duration? initialPosition, bool autoplay = true}) {
    throw UnimplementedError('该引擎不支持 EME 播放');
  }

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> stop();

  void dispose();
}
