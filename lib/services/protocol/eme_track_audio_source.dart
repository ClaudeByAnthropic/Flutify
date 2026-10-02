import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../audio/audio_engine.dart';
import '../eme/segmented_download.dart';
import '../eme/streaming_download.dart';
import 'audio_cache_store.dart';
import 'spotify_id.dart';
import 'storage_resolver.dart';
import 'track_audio_loader.dart';
import 'track_metadata.dart';
import 'track_playback_media.dart';

/// 流式下载句柄：[readyForPlayback] 在可起播字节数就绪时完成。
class _StreamingDownloadHandle {
  final Completer<void> _ready = Completer<void>();
  Future<void> get readyForPlayback => _ready.future;
}

/// EME（Widevine）曲目音频来源：track-playback 取 MP4 → sneaktables 取 HLS 清单 →
/// storage-resolve 下载加密 m4a → 交给 EME 引擎（WebView2）解密播放。
///
/// 与 [TrackAudioLoader]（OGG/AP 链路）互补：那条路密钥被拒的 DRM 曲目走这里。
/// 产物（加密 m4a + 清单）缓存在 [cacheDirectory]/eme_audio，同一 file_id 复用。
class EmeTrackAudioSource implements TrackAudioSource, AudioCacheStore {
  final Future<String> Function() accessToken;
  final Future<String> Function()? clientToken;
  final String cacheDirectory;
  final http.Client _client;

  /// Web 登录态（sp_dc）是否就绪；为 null 时不检查。
  /// EME 链路的 Widevine 真密钥依赖 Web token（sp_dc 铸造），缺 sp_dc 时
  /// 下载完整首也只会在 license 步骤失败，因此在下载前提前拦截。
  final bool Function()? webSessionReady;

  int _maxCacheBytes = 512 * 1024 * 1024;

  /// 进行中的加载（按曲目合并）。
  final Map<String, Future<LoadedAudio>> _inFlight = {};

  EmeTrackAudioSource({
    required this.accessToken,
    this.clientToken,
    required this.cacheDirectory,
    this.webSessionReady,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<Map<String, String>> _headers() async {
    final token = await accessToken();
    final h = <String, String>{
      'Authorization': 'Bearer $token',
      // 桌面端身份（track-playback / sneaktables 用这个）
      'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
      'app-platform': 'Win32_x86_64',
      'spotify-app-version': '1.3.1.234.g59d6bf59',
    };
    if (clientToken != null) h['client-token'] = await clientToken!();
    return h;
  }

  Directory get _dir => Directory('$cacheDirectory${Platform.pathSeparator}eme_audio');

  File _cacheFile(String fileIdHex) =>
      File('${_dir.path}${Platform.pathSeparator}$fileIdHex.m4a');

  @override
  Future<LoadedAudio> open(String trackIdOrUri, {void Function(double progress)? progress}) =>
      load(trackIdOrUri, progress: progress);

  @override
  Future<LoadedAudio> load(String trackIdOrUri, {void Function(double progress)? progress}) {
    final id = SpotifyId.fromUri(trackIdOrUri);
    final key = 'eme:${id.toBase62()}';
    return _inFlight.putIfAbsent(key, () async {
      try {
        return await _load(id, progress);
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  Future<LoadedAudio> _load(SpotifyId id, void Function(double progress)? progress) async {
    debugPrint('[eme-src] 开始加载 ${id.toBase62()}');
    // 缺 sp_dc 时铸不出 Web token，license 必失败；在下载前直接报「需要 Web 登录」
    if (webSessionReady?.call() == false) {
      throw const TrackPlaybackException(
        TrackPlaybackFailure.webSignInRequired,
        '全曲播放需要先完成 Web 登录',
      );
    }
    // 1) track-playback 取 MP4 文件清单
    progress?.call(0.05);
    final TrackPlaybackMedia media;
    try {
      media = await fetchTrackPlaybackMedia(id.toBase62(), headers: _headers, client: _client);
      debugPrint('[eme-src] track-playback OK，MP4 文件 ${media.mp4Files.length} 个');
    } catch (e) {
      debugPrint('[eme-src] track-playback 失败: $e');
      throw TrackPlaybackException(TrackPlaybackFailure.network, '获取曲目播放信息失败', e);
    }
    final file = media.selectForFree();
    if (file == null) {
      throw const TrackPlaybackException(
          TrackPlaybackFailure.unavailable, '这首歌没有可用的 DRM 音频文件');
    }
    debugPrint('[eme-src] 选定 file_id=${file.fileIdHex.substring(0, 16)}… br=${file.bitrate}');

    // 2) sneaktables 取 HLS 清单，同时 storage-resolve 取 CDN 地址（两者互不依赖，并行省一个往返）
    progress?.call(0.15);
    final dest = _cacheFile(file.fileIdHex);
    final doneMarker = File('${dest.path}.done');
    final complete = dest.existsSync() && doneMarker.existsSync() && dest.lengthSync() > 0;
    final cdnUrls = complete
        ? null
        : resolveAudioStorage(fileIdHex: file.fileIdHex, headers: _headers, client: _client)
            .then((r) => r.cdnUrls);
    cdnUrls?.ignore(); // 清单失败时没人等它，避免未处理异常
    final String m3u8;
    try {
      m3u8 = await fetchHlsManifest(file.fileIdHex, headers: _headers, client: _client);
      debugPrint('[eme-src] HLS 清单 OK（${m3u8.length} 字符）');
    } catch (e) {
      debugPrint('[eme-src] HLS 清单失败: $e');
      throw TrackPlaybackException(TrackPlaybackFailure.network, '获取播放清单失败', e);
    }

    // 3) 下载加密 m4a：完整缓存命中直接用；否则后台下载、init 段就绪即返回（流式起播）
    if (cdnUrls != null) {
      progress?.call(0.25);
      // 后台下载；init 段 + 首段就绪即返回，剩余边下边播
      final dl = _startStreamingDownload(cdnUrls, dest, doneMarker, progress);
      await dl.readyForPlayback; // 等到可起播的字节数
      debugPrint('[eme-src] init 段就绪，流式起播（后台继续下载）');
    } else {
      debugPrint('[eme-src] 缓存命中 ${dest.path}');
    }
    progress?.call(1.0);

    return LoadedAudio(
      file: dest,
      source: TrackAudioFile(fileId: _hexToBytes(file.fileIdHex), format: AudioFileFormat.aac48),
      durationMs: media.durationMs > 0 ? media.durationMs : null,
      trackId: id.toBase62(),
      emeContent: EmeTrackContent(m4aPath: dest.path, m3u8: m3u8),
    );
  }

  /// 启动流式下载：后台顺序写入 [dest]，init 段 + 首段就绪后 [readyForPlayback] 完成。
  /// 进度登记到 [StreamingDownloads]，供 EME 播放器的本地服务按区间等待。
  _StreamingDownloadHandle _startStreamingDownload(
      Future<List<String>> cdnUrls, File dest, File doneMarker, void Function(double)? progress) {
    final handle = _StreamingDownloadHandle();
    final registration = StreamingDownloads.begin(dest.path);
    () async {
      try {
        final urls = await cdnUrls;
        debugPrint('[eme-src] storage-resolve 得 ${urls.length} 个 CDN');
        if (urls.isEmpty) throw StateError('无可用 CDN');
        // 多连接分段：按偏移顺序分配，从头连续可用的字节增长最快；报告语义与顺序下载一致
        await SegmentedDownload(
          client: _client,
          urls: urls,
          dest: dest,
          headers: const {'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)'},
          // 首段小一点：起播只需 init 段 + 首个媒体段
          segmentBytes: _kMinBytesToPlay,
          onContiguous: (got, total) {
            registration.expectedTotal = total;
            registration.report(got);
            if (!handle._ready.isCompleted && got >= _kMinBytesToPlay) {
              handle._ready.complete();
            }
            if (total > 0) progress?.call(0.25 + 0.75 * got / total);
          },
        ).run();
        // 完成：写 .done 标记
        await doneMarker.writeAsString('${dest.lengthSync()}');
        registration.finish();
        debugPrint('[eme-src] 下载完成 ${dest.lengthSync()}B');
      } catch (e) {
        debugPrint('[eme-src] 流式下载失败: $e');
        registration.finish(e);
        if (!handle._ready.isCompleted) {
          handle._ready.completeError(
              TrackPlaybackException(TrackPlaybackFailure.network, '音频下载失败，请检查网络后重试', e));
        }
      } finally {
        StreamingDownloads.end(dest.path);
      }
    }();
    return handle;
  }

  /// 起播所需的最少字节（init 段 1338B + 首个媒体段）。HLS.js 按 BYTERANGE 顺序取段，
  /// 这个量足够它解出 init 并开始第一段的解密播放。
  static const int _kMinBytesToPlay = 256 * 1024;

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  @override
  Future<void> prefetch(String trackIdOrUri) async {
    try {
      await load(trackIdOrUri);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // AudioCacheStore（设置页「存储」分组）
  // ---------------------------------------------------------------------------

  @override
  int get maxCacheBytes => _maxCacheBytes;

  @override
  set maxCacheBytes(int value) {
    _maxCacheBytes = value;
    _trim();
  }

  List<File> _files() {
    final dir = _dir;
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('.part'))
        .toList();
  }

  @override
  Future<int> sizeBytes() async {
    try {
      var total = 0;
      await for (final e in _dir.list()) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<int> clear() async {
    var freed = 0;
    try {
      for (final f in _files()) {
        try {
          freed += f.lengthSync();
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }

  /// 超上限时按「最久未用」淘汰。
  void _trim() {
    try {
      final files = _files();
      var total = files.fold<int>(0, (s, f) => s + f.lengthSync());
      if (total <= _maxCacheBytes) return;
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files) {
        if (total <= _maxCacheBytes) break;
        try {
          total -= f.lengthSync();
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
