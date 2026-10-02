import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'streaming_download.dart';

/// EME 播放器：用一个**隐藏 1×1 WebView2**（空白本地页 + HLS.js，不加载任何 Spotify 前端）
/// 做 Widevine 解密 + 播放。性能开销 ≈ 一个空白页 + 一路 AAC 解码，无渲染负担。
///
/// 为什么用 HLS.js 而不是手写 MSE：Spotify 的 fMP4 有「明文 lead-in + 后段加密」结构，
/// 手写 MSE 喂法会让 Chromium 丢失逐样本加密信息（卡在加密边界 9.5s）。HLS.js 是 Web 播放器
/// 同款引擎，按 EXT-X-MAP/BYTERANGE 正确喂段并处理 EME，实测能整曲播放。
///
/// 工作原理：
/// - Dart 在 127.0.0.1 起微型 HTTP 服务（安全上下文），供：页面、HLS.js、本地化的 m3u8、
///   加密 m4a（支持 Range，供 HLS.js 按 BYTERANGE 取段）、license/证书 反代；
/// - 页面用 HLS.js 加载本地 m3u8 → EME 发 license 请求 → 经 Dart 反代到 Spotify → 装钥 → 播放；
/// - 密钥全程不出 CDM；页面零外部网络请求（全部走 127.0.0.1）。
class EmePlayer {
  HttpServer? _server;
  InAppWebViewController? _controller;
  HeadlessInAppWebView? _headless;
  final Completer<void> _pageReady = Completer<void>();

  /// 当前服务的加密音频文件与本地化清单。
  File? _audioFile;
  String? _localM3u8;

  /// 静态资源（hls.js 与证书）内容，由 [play] 注入。
  static String? hlsJsSource; // hls.min.js 内容（资产，启动时读一次）

  // ---- 播放状态流 ----
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _stateController = StreamController<EmePlayerState>.broadcast();

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<EmePlayerState> get stateStream => _stateController.stream;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration get position => _position;
  Duration get duration => _duration;

  /// license 反代（Dart 代发到 Spotify）。
  Future<Uint8List> Function(Uint8List request)? _licensePoster;
  Future<Uint8List> Function()? _certFetcher;

  String get _origin => 'http://127.0.0.1:${_server!.port}';

  /// 自定义 WebView2 环境：关闭自动播放手势限制（隐藏页没有用户手势）。
  static Future<WebViewEnvironment?>? _webViewEnvironment;

  /// 已创建的自定义环境（[ensureEnvironment] 完成后可用），供 buildHiddenView 默认使用。
  static WebViewEnvironment? cachedEnvironment;

  /// 在 runApp 后尽早调用一次（WebView 创建前）。
  static Future<WebViewEnvironment?> ensureEnvironment() {
    return _webViewEnvironment ??= () async {
      if (!Platform.isWindows) return null;
      try {
        final env = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            additionalBrowserArguments:
                '--autoplay-policy=no-user-gesture-required',
          ),
        );
        cachedEnvironment = env;
        return env;
      } catch (e) {
        debugPrint('[eme] 自定义 WebView 环境创建失败，用默认环境: $e');
        return null;
      }
    }();
  }

  /// 初始化：起本地 HTTP 服务。必须在 [buildHiddenView] 挂载前 await。
  Future<void> init() => _ensureServer();

  /// 启动无头 WebView2（不进 widget 树 → 窗口缩放/布局切换不影响播放，且零渲染开销）。
  /// 在 [init] 之后调用一次。
  Future<void> start() async {
    if (_headless != null) return;
    final headless = HeadlessInAppWebView(
      webViewEnvironment: cachedEnvironment,
      initialUrlRequest: URLRequest(url: WebUri('$_origin/eme')),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'emeEvent',
          callback: _onJsEvent,
        );
      },
      // Android WebView：Widevine 需要 App 显式授予「受保护媒体 ID」，否则 requestMediaKeySystemAccess 直接失败。
      // 只放行这一项，其余（摄像头 / 麦克风等）一律拒绝。WebView2 不走这里。
      onPermissionRequest: (_, request) async {
        final drm = request.resources.contains(PermissionResourceType.PROTECTED_MEDIA_ID);
        debugPrint('[eme] 权限请求 ${request.resources.map((r) => r.toNativeValue()).join(',')} → ${drm ? '允许' : '拒绝'}');
        return PermissionResponse(
          resources: drm ? [PermissionResourceType.PROTECTED_MEDIA_ID] : const [],
          action: drm ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
        );
      },
      onLoadStop: (_, _) {
        if (!_pageReady.isCompleted) _pageReady.complete();
      },
      onReceivedError: (_, request, error) {
        if ((request.isForMainFrame ?? true) && !_pageReady.isCompleted) {
          _pageReady.completeError(StateError('EME 页加载失败：${error.description}'));
        }
      },
      onConsoleMessage: (_, msg) {
        if (msg.messageLevel == ConsoleMessageLevel.ERROR) {
          debugPrint('[eme-js] ${msg.message}');
        }
      },
    );
    _headless = headless;
    await headless.run();
  }

  Future<void> _ensureServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      final path = request.uri.path;
      try {
        if (path == '/eme') {
          request.response.headers.contentType = ContentType.html;
          request.response.write(emePageHtml);
          await request.response.close();
        } else if (path == '/hls.js') {
          request.response.headers.contentType =
              ContentType('application', 'javascript');
          request.response.write(hlsJsSource ?? '');
          await request.response.close();
        } else if (path == '/audio.m3u8') {
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(_localM3u8 ?? '#EXTM3U');
          await request.response.close();
        } else if (path == '/audio/current.m4a') {
          await _serveAudio(request);
        } else if (path == '/license' && request.method == 'POST') {
          await _relayLicense(request);
        } else if (path == '/cert') {
          await _relayCert(request);
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      } catch (_) {
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  /// 供加密 m4a，支持 Range（HLS.js 按 BYTERANGE 取段）。
  /// 流式下载中时，若要的区间还没下完就等它（边下边播）。
  Future<void> _serveAudio(HttpRequest request) async {
    final file = _audioFile;
    if (file == null) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final response = request.response;
    response.headers.contentType = ContentType('audio', 'mp4');

    // 流式下载登记（有则说明还在下，需按区间等待）
    final dl = StreamingDownloads.of(file.path);

    // 解析 Range
    int start = 0;
    int? endExclusive;
    if (rangeHeader != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (m == null) {
        response.statusCode = 416;
        await response.close();
        return;
      }
      start = int.parse(m.group(1)!);
      endExclusive = m.group(2)!.isEmpty ? null : int.parse(m.group(2)!) + 1;
    }

    // 流式中：等到要的区间下完
    if (dl != null && !dl.done) {
      final need = endExclusive ?? (dl.expectedTotal > 0 ? dl.expectedTotal : start + 1);
      try {
        await dl.waitFor(need);
      } catch (e) {
        response.statusCode = 503;
        await response.close();
        return;
      }
    }

    final total = file.lengthSync();
    final end = (endExclusive ?? total).clamp(0, total);
    final len = end - start;
    if (len <= 0) {
      response.statusCode = 416;
      await response.close();
      return;
    }
    if (rangeHeader != null) {
      response.statusCode = 206;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${end - 1}/$total');
    }
    response.headers.set(HttpHeaders.contentLengthHeader, len);
    await file.openRead(start, end).pipe(response);
  }

  /// license 反代：页面 HLS.js POST 的 CDM 请求 → Dart 代发到 Spotify → 返回响应。
  Future<void> _relayLicense(HttpRequest request) async {
    final body = await consolidatedBody(request);
    final poster = _licensePoster;
    if (poster == null) {
      request.response.statusCode = 500;
      await request.response.close();
      return;
    }
    final resp = await poster(body);
    debugPrint('[eme] license 反代：请求 ${body.length}B → 响应 ${resp.length}B');
    request.response.headers.contentType =
        ContentType('application', 'octet-stream');
    request.response.add(resp);
    await request.response.close();
  }

  Future<void> _relayCert(HttpRequest request) async {
    final fetcher = _certFetcher;
    if (fetcher == null) {
      request.response.statusCode = 500;
      await request.response.close();
      return;
    }
    final cert = await fetcher();
    request.response.headers.contentType =
        ContentType('application', 'octet-stream');
    request.response.add(cert);
    await request.response.close();
  }

  static Future<Uint8List> consolidatedBody(HttpRequest request) async {
    final builder = BytesBuilder();
    await for (final chunk in request) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// 播放一首协议下载的加密曲目。
  /// [m4a] 加密 fMP4；[m3u8] sneaktables policy=1 原始清单（含 EXT-X-KEY/MAP/BYTERANGE）；
  /// [licensePoster] Dart 代发 license 到 Spotify；[certFetcher] 取 application-certificate。
  Future<void> play({
    required File m4a,
    required String m3u8,
    required Future<Uint8List> Function(Uint8List request) licensePoster,
    required Future<Uint8List> Function() certFetcher,
  }) async {
    await _ensureServer();
    _licensePoster = licensePoster;
    _certFetcher = certFetcher;
    _audioFile = m4a;
    _localM3u8 = _localizeM3u8(m3u8);
    await _pageReady.future;
    final c = _controller;
    if (c == null) throw StateError('EME WebView 未创建（buildHiddenView 未挂载）');

    final res = await c.callAsyncJavaScript(
        functionBody: 'return await emePlayHls();');
    debugPrint('[eme] emePlayHls 结果: ${res?.value}');
    final v = res?.value;
    if (v is String && v.startsWith('ERR:')) {
      throw StateError('EME 播放启动失败：$v');
    }
  }

  /// 把 Spotify 的 HLS 清单本地化：MAP 与分段的 URL 全改指到本地 m4a（保留 BYTERANGE），
  /// EXT-X-KEY（PSSH data URI）原样保留——HLS.js 用它做 EME initData。
  String _localizeM3u8(String m3u8) {
    final local = '$_origin/audio/current.m4a';
    final out = <String>[];
    for (final line in m3u8.split('\n')) {
      if (line.startsWith('#EXT-X-MAP:')) {
        // 替换 URI="..." 为本地，保留 BYTERANGE
        out.add(line.replaceAll(RegExp(r'URI="[^"]*"'), 'URI="$local"'));
      } else if (line.startsWith('http')) {
        out.add(local);
      } else {
        out.add(line);
      }
    }
    return out.join('\n');
  }

  Future<void> pause() => _js('emePause()');
  Future<void> resume() => _js('emeResume()');
  Future<void> seek(Duration pos) =>
      _js('emeSeek(${(pos.inMilliseconds / 1000).toStringAsFixed(3)})');
  Future<void> setVolume(double v) =>
      _js('emeSetVolume(${v.clamp(0.0, 1.0)})');

  Future<void> _js(String source) async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.evaluateJavascript(source: source);
    } catch (_) {}
  }

  void _onJsEvent(List<dynamic> args) {
    final raw = args.isEmpty ? null : args.first;
    if (raw is! String) return;
    final Map<String, dynamic> ev = jsonDecode(raw);
    switch (ev['type']) {
      case 'position':
        _position = Duration(milliseconds: ((ev['position'] ?? 0) * 1000).round());
        final dur = (ev['duration'] ?? 0) * 1000;
        if (dur > 0) {
          final d = Duration(milliseconds: dur.round());
          if (d != _duration) {
            _duration = d;
            _durationController.add(d);
          }
        }
        _positionController.add(_position);
      case 'playing':
        _stateController.add(EmePlayerState.playing);
      case 'buffering':
        _stateController.add(EmePlayerState.buffering);
      case 'ended':
        _stateController.add(EmePlayerState.ended);
      case 'error':
        debugPrint('[eme] 播放错误: ${ev['msg'] ?? ev}');
        _stateController.add(EmePlayerState.error);
      case 'log':
        debugPrint('[eme-js] ${ev['msg']}');
    }
  }

  Future<void> dispose() async {
    await _server?.close();
    _server = null;
  }
}

enum EmePlayerState { playing, buffering, ended, error }

/// 空白 EME 宿主页（HLS.js 驱动；无任何 UI/Spotify 前端；零外部请求）。
/// 页面加载 HLS.js → 加载本地 m3u8 → EME 解密 → MSE 播放。
const String emePageHtml = r'''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>eme</title></head>
<body>
<script src="/hls.js"></script>
<script>
'use strict';
let hls = null, audio = null;

const send = (type, data) => {
  try { window.flutter_inappwebview.callHandler('emeEvent', JSON.stringify({type, ...(data||{})})); } catch (e) {}
};

window.emePlayHls = () => (async () => {
  try {
    if (!window.Hls) return 'ERR:Hls.js 未加载';
    if (!Hls.isSupported()) return 'ERR:HLS 不支持';
    audio = document.createElement('audio');
    document.body.appendChild(audio);
    audio.addEventListener('timeupdate', () => send('position', {position: audio.currentTime, duration: audio.duration}));
    audio.addEventListener('playing', () => send('playing', {}));
    audio.addEventListener('waiting', () => send('buffering', {}));
    audio.addEventListener('ended', () => send('ended', {}));
    audio.addEventListener('error', () => send('error', {msg: audio.error ? (audio.error.code + ':' + audio.error.message) : 'unknown'}));
    audio.addEventListener('encrypted', (ev) => send('log', {msg: 'encrypted 事件 initDataType=' + ev.initDataType}));

    hls = new Hls({
      emeEnabled: true,
      drmSystems: {
        'com.widevine.alpha': {
          licenseUrl: '/license',
          serverCertificateUrl: '/cert',
        },
      },
      // 宽限：本地服务，无需重试策略
      fragLoadingMaxRetry: 2,
      manifestLoadingMaxRetry: 2,
    });
    hls.on(Hls.Events.ERROR, (ev, data) => {
      send('log', {msg: 'HLS ERROR ' + data.type + '/' + data.details + ' fatal=' + data.fatal});
      if (data.fatal) send('error', {msg: data.details});
    });
    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      send('log', {msg: '清单已解析'});
      audio.muted = true;
      audio.play().then(() => { audio.muted = false; }).catch(() => {});
    });
    hls.loadSource('/audio.m3u8');
    hls.attachMedia(audio);
    return 'ok';
  } catch (e) {
    return 'ERR:' + String(e);
  }
})();

// 启动时探测一次 Widevine 是否可用，结果写进日志（安卓 WebView 排查用）
(async () => {
  try {
    const access = await navigator.requestMediaKeySystemAccess('com.widevine.alpha', [{
      initDataTypes: ['cenc'],
      audioCapabilities: [{contentType: 'audio/mp4; codecs="mp4a.40.2"'}],
    }]);
    send('log', {msg: 'Widevine 可用 ' + JSON.stringify(access.getConfiguration().audioCapabilities)});
  } catch (e) {
    send('log', {msg: 'Widevine 不可用: ' + e});
  }
  send('log', {msg: 'UA ' + navigator.userAgent});
})();

window.emePause = () => { if (audio) audio.pause(); };
window.emeResume = () => { if (audio) { audio.muted = false; audio.play(); } };
window.emeSeek = (sec) => { if (audio) audio.currentTime = sec; };
window.emeSetVolume = (v) => { if (audio) audio.volume = v; };
</script>
</body>
</html>
''';
