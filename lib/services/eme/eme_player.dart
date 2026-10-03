import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../audio/audio_engine.dart';
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

  /// 最近一次错误的详情（license 换取失败原因 / HLS.js fatal details 等）。
  /// [play] 时清空；上层（EmeAudioEngine）收到 error 状态事件时读取并上报。
  EmePlaybackException? lastError;

  /// 启动探测判定 Widevine / CDM 不可用（页面加载时探测一次）。
  /// 后续播放错误据此归类为「设备缺 Widevine」（重试无意义）。
  bool _widevineUnavailable = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration get position => _position;
  Duration get duration => _duration;

  /// license 反代（Dart 代发到 Spotify）。
  Future<Uint8List> Function(Uint8List request)? _licensePoster;
  Future<Uint8List> Function()? _certFetcher;

  /// provision 反代用的共享 HTTP client（遵守全局 HttpOverrides / NetworkProxy）。
  /// 背景：部分设备 Widevine CDM 需 provisioning，但 CDM 自带的 Google
  /// provisioning 地址在用户网络被掐（静默重试、永不返回）——原生播放器的
  /// provision 请求改发到本地回环，由这里经 App 代理策略外发。
  final http.Client _httpClient = http.Client();

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
        } else if (path == '/provision' && request.method == 'POST') {
          await _relayProvision(request);
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
  /// 失败不再是静默的 HTTP 500：真实原因写进响应体（HLS.js 错误数据可带回），
  /// 同时直接记入 [lastError] 并发 error 状态，不等 JS 侧的事件接力。
  Future<void> _relayLicense(HttpRequest request) async {
    final body = await consolidatedBody(request);
    final poster = _licensePoster;
    if (poster == null) {
      await _failRelay(request, 'license', StateError('licensePoster 未注入'));
      return;
    }
    try {
      final resp = await poster(body);
      debugPrint('[eme] license 反代：请求 ${body.length}B → 响应 ${resp.length}B');
      request.response.headers.contentType =
          ContentType('application', 'octet-stream');
      request.response.add(resp);
      await request.response.close();
    } catch (e) {
      await _failRelay(request, 'license', e);
    }
  }

  Future<void> _relayCert(HttpRequest request) async {
    final fetcher = _certFetcher;
    if (fetcher == null) {
      await _failRelay(request, '证书', StateError('certFetcher 未注入'));
      return;
    }
    try {
      final cert = await fetcher();
      request.response.headers.contentType =
          ContentType('application', 'octet-stream');
      request.response.add(cert);
      await request.response.close();
    } catch (e) {
      await _failRelay(request, '证书', e);
    }
  }

  /// provision 反代：原生播放器把 CDM 的 provision 请求体 POST 到本地回环，
  /// 这里经 App 代理策略外发到 CDM 给定的目标地址，响应字节与状态码原样回传。
  /// [target] 为 CDM 报的原始 provisioning URL（v1/v2 signedRequest 都走这里）。
  Future<void> _relayProvision(HttpRequest request) async {
    final target = request.uri.queryParameters['target'];
    if (target == null || target.isEmpty || !target.startsWith('https://')) {
      debugPrint('[eme] provision 反代：拒绝非法 target=$target');
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }
    final body = await consolidatedBody(request);
    try {
      final resp = await _httpClient
          .post(Uri.parse(target),
              headers: {'Content-Type': 'application/octet-stream'}, body: body)
          .timeout(const Duration(seconds: 15));
      var line =
          '[eme] provision 反代：请求 ${body.length}B → HTTP ${resp.statusCode} ${resp.bodyBytes.length}B';
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        // 失败原因写在响应体（Google provisioning 报错是文本），带前 200 字符进日志
        line =
            '$line | ${utf8.decode(resp.bodyBytes.take(200).toList(), allowMalformed: true)}';
      }
      debugPrint(line);
      request.response.statusCode = resp.statusCode;
      request.response.headers.contentType =
          ContentType('application', 'octet-stream');
      request.response.add(resp.bodyBytes);
      await request.response.close();
    } catch (e) {
      await _failRelay(request, 'provision', e);
    }
  }

  /// 反代失败：原因写进 500 响应体（页面侧随 HLS 错误带回），并推进错误通道。
  /// 之所以走 [lastError] + stateStream（与 JS 侧 HLS/audio 错误汇合），
  /// 是因为上层只在 error 状态时读错误详情，一条通道即可覆盖两类来源。
  Future<void> _failRelay(HttpRequest request, String name, Object error) async {
    debugPrint('[eme] $name 反代失败: $error');
    // 只记第一条：随后 hls.js 还会发 fatal 错误事件，别让泛化 details 覆盖真实原因
    lastError ??= EmePlaybackException(
      '$name 反代失败：$error',
      webSignInSuggested: name == 'license' && _looksLikeAuthFailure('$error'),
      cause: error,
    );
    _stateController.add(EmePlayerState.error);
    try {
      request.response.statusCode = 500;
      request.response.headers.contentType =
          ContentType('text', 'plain', charset: 'utf-8');
      request.response.write('$error');
      await request.response.close();
    } catch (_) {}
  }

  /// 401/403 视为 Web 登录态（sp_dc）失效：引导重新 Web 登录。
  static bool _looksLikeAuthFailure(String message) =>
      message.contains('401') || message.contains('403');

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
    lastError = null;
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
  /// [widevineKeyFormat] 为真时把 KEYFORMAT 改写成 Widevine UUID 形式：ExoPlayer 只按
  /// UUID 认 KEYFORMAT；只影响喂给原生播放器的这份清单，WebView/hls.js 路径不受影响。
  String _localizeM3u8(String m3u8, {bool widevineKeyFormat = false}) {
    final local = '$_origin/audio/current.m4a';
    final out = <String>[];
    for (final line in m3u8.split('\n')) {
      if (line.startsWith('#EXT-X-MAP:')) {
        // 替换 URI="..." 为本地，保留 BYTERANGE
        out.add(line.replaceAll(RegExp(r'URI="[^"]*"'), 'URI="$local"'));
      } else if (line.startsWith('#EXT-X-KEY:') && widevineKeyFormat) {
        out.add(_withWidevineKeyFormat(line));
      } else if (line.startsWith('http')) {
        out.add(local);
      } else {
        out.add(line);
      }
    }
    return out.join('\n');
  }

  /// Widevine 的 KEYFORMAT UUID（ExoPlayer 按它把 EXT-X-KEY 的 data URI 解析成 PSSH）。
  static const _widevineKeyFormatUuid =
      'urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed';

  /// 把 EXT-X-KEY 行的 KEYFORMAT 改写/补为 Widevine UUID；已是该值则原样返回。
  static String _withWidevineKeyFormat(String line) {
    if (line.contains('KEYFORMAT="$_widevineKeyFormatUuid"')) return line;
    if (line.contains('KEYFORMAT="')) {
      return line.replaceAll(
          RegExp(r'KEYFORMAT="[^"]*"'), 'KEYFORMAT="$_widevineKeyFormatUuid"');
    }
    return '$line,KEYFORMAT="$_widevineKeyFormatUuid"';
  }

  /// Android 原生 DRM 引擎的宿主入口：只起本地回环服务（**不开 WebView**），
  /// 清单按 ExoPlayer 要求把 KEYFORMAT 改写为 Widevine UUID，返回喂给原生播放器的 URL。
  /// 下载后的加密 m4a、license/证书反代、流式区间等待全部复用本类既有实现。
  Future<({String hlsUrl, String licenseUrl, String provisionUrl})>
      serveHlsForNative({
    required File m4a,
    required String m3u8,
    required Future<Uint8List> Function(Uint8List request) licensePoster,
    required Future<Uint8List> Function() certFetcher,
  }) async {
    await _ensureServer();
    _licensePoster = licensePoster;
    _certFetcher = certFetcher;
    _audioFile = m4a;
    _localM3u8 = _localizeM3u8(m3u8, widevineKeyFormat: true);
    return (
      hlsUrl: '$_origin/audio.m3u8',
      licenseUrl: '$_origin/license',
      provisionUrl: '$_origin/provision',
    );
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
      // 页面脚本 ready 前 evaluate 会撞 ReferenceError（如启动音量下发时
      // emeSetVolume 尚未定义）；等页载完再打。加载失败时 _pageReady 以 error
      // 完成，这里 catch 后丢弃，不会死锁。
      await _pageReady.future;
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
        final msg = (ev['msg'] ?? 'unknown').toString();
        debugPrint('[eme] 播放错误: $msg');
        // 反代失败已写过更具体的原因（license / 证书），保留第一条
        lastError ??= _classifyError(msg);
        _stateController.add(EmePlayerState.error);
      case 'widevineUnavailable':
        _widevineUnavailable = true;
        debugPrint('[eme] Widevine 不可用（后续播放错误按缺 Widevine 归类）: ${ev['msg']}');
      case 'log':
        debugPrint('[eme-js] ${ev['msg']}');
    }
  }

  /// 按 HLS.js details / 错误文本归类：明确 Widevine/CDM 缺失时打标记，
  /// 401/403 标记为「需重新 Web 登录」，其余按普通运行期失败处理。
  EmePlaybackException _classifyError(String msg) {
    final noWidevine =
        _widevineUnavailable || msg.toLowerCase().contains('keysystemnoaccess');
    return EmePlaybackException(
      msg,
      isWidevineMissing: noWidevine,
      webSignInSuggested: !noWidevine && _looksLikeAuthFailure(msg),
    );
  }

  Future<void> dispose() async {
    await _server?.close();
    _server = null;
    _httpClient.close();
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
// 页面级：createMediaKeys 曾挂起则置真，之后所有 hls 实例不再带 serverCertificateUrl
//（部分 Android WebView 的 EME 带证书请求时 createMediaKeys 永不 settle；不带也能播）
let certDegraded = false;

const send = (type, data) => {
  try { window.flutter_inappwebview.callHandler('emeEvent', JSON.stringify({type, ...(data||{})})); } catch (e) {}
};

// ---- EME 原生 API 时间戳 hook（非侵入 monkey-patch：只记录，不改时序、不吞错、返回原 Promise） ----
// 用于定位「无 encrypted、无 /license、无报错」卡死：hls.js / 页面里任何人走
// createMediaKeys → setServerCertificate → createSession → generateRequest 都会被记下。
// Promise 类步骤用 settle 标记，5s 未 settle 报「疑似挂起」。
try {
  const tapPromise = (p, tag, t0, timeout) => {
    timeout = timeout || 5000;
    let settled = false;
    p.then(() => { settled = true; send('log', {msg: '[hook] ' + tag + ' resolve ' + (performance.now() - t0).toFixed(0) + 'ms'}); },
           (e) => { settled = true; send('log', {msg: '[hook] ' + tag + ' reject: ' + e}); });
    setTimeout(() => {
      if (settled) return;
      send('log', {msg: '[hook] ' + tag + ' ' + (timeout / 1000) + 's 未 settle（疑似挂起）'});
      // createMediaKeys 挂起是可恢复场景：除日志外发 stall 信号，
      // Dart 侧记一条，页面内广播给 emePlayHls 触发「无 serverCertificate」降级重建
      if (tag === 'createMediaKeys') {
        send('emeStall', {stage: tag});
        try { window.dispatchEvent(new CustomEvent('emeStall', {detail: {stage: tag}})); } catch (e) {}
      }
    }, timeout);
    return p;
  };
  if (window.MediaKeySystemAccess) {
    const _cmk = MediaKeySystemAccess.prototype.createMediaKeys;
    MediaKeySystemAccess.prototype.createMediaKeys = function (...args) {
      send('log', {msg: '[hook] createMediaKeys 调用'});
      return tapPromise(_cmk.apply(this, args), 'createMediaKeys', performance.now(), 6000);
    };
  }
  if (window.MediaKeys) {
    const _ssc = MediaKeys.prototype.setServerCertificate;
    MediaKeys.prototype.setServerCertificate = function (...args) {
      const cert = args[0];
      send('log', {msg: '[hook] setServerCertificate 调用 cert=' + (cert && cert.byteLength || 0) + 'B'});
      return tapPromise(_ssc.apply(this, args), 'setServerCertificate', performance.now());
    };
    const _cs = MediaKeys.prototype.createSession;
    MediaKeys.prototype.createSession = function (...args) {
      send('log', {msg: '[hook] createSession 调用'});
      const s = _cs.apply(this, args);
      s.addEventListener('message', (ev) => send('log',
        {msg: '[hook] session message type=' + ev.messageType + ' body=' + (ev.message ? ev.message.byteLength : 0) + 'B'}));
      s.addEventListener('keystatuseschange', () => send('log', {msg: '[hook] session keystatuseschange'}));
      return s;
    };
  }
  if (window.MediaKeySession) {
    const _gr = MediaKeySession.prototype.generateRequest;
    MediaKeySession.prototype.generateRequest = function (initDataType, initData) {
      send('log', {msg: '[hook] generateRequest 调用 initDataType=' + initDataType + ' initData=' + (initData && initData.byteLength || 0) + 'B'});
      return tapPromise(_gr.apply(this, arguments), 'generateRequest', performance.now());
    };
  }
  send('log', {msg: '[hook] EME API hook 已安装'});
} catch (e) {
  send('log', {msg: '[hook] EME API hook 安装失败: ' + e});
}

window.emePlayHls = () => (async () => {
  try {
    if (!window.Hls) return 'ERR:Hls.js 未加载';
    if (!Hls.isSupported()) return 'ERR:HLS 不支持';
    // 换歌 / 失败重试：销毁上一首的 hls 与 audio，避免残留状态串台
    if (hls) { try { hls.destroy(); } catch (e) {} hls = null; }
    if (audio) { try { audio.pause(); audio.remove(); } catch (e) {} audio = null; }
    audio = document.createElement('audio');
    document.body.appendChild(audio);
    audio.addEventListener('timeupdate', () => send('position', {position: audio.currentTime, duration: audio.duration}));
    audio.addEventListener('playing', () => send('playing', {}));
    audio.addEventListener('waiting', () => send('buffering', {}));
    audio.addEventListener('ended', () => send('ended', {}));
    audio.addEventListener('error', () => send('error', {msg: audio.error ? (audio.error.code + ':' + audio.error.message) : 'unknown'}));
    audio.addEventListener('encrypted', (ev) => send('log', {msg: 'encrypted 事件 initDataType=' + ev.initDataType + ' initData=' + (ev.initData ? ev.initData.byteLength : 0) + 'B'}));
    // 诊断：媒体元素状态迁移（定位「不出声也不报错」卡在 readyState 哪一级）
    ['play','pause','waiting','stalled','canplay','loadeddata','loadedmetadata','durationchange']
      .forEach((n) => audio.addEventListener(n, () => send('log',
        {msg: 'audio 事件 ' + n + ' t=' + (audio.currentTime || 0).toFixed(2) + ' readyState=' + audio.readyState})));

    // hls 实例构建（降级重建时复用）：certDegraded 为真则不带 serverCertificateUrl，
    // 让 EMEController 跳过 setServerCertificate（已验证桌面 Chrome 无证书也能播）。
    const buildHls = () => {
      if (hls) { try { hls.destroy(); } catch (e) {} hls = null; }
      const widevine = certDegraded
        ? { licenseUrl: '/license' }                                    // 降级：不碰 setServerCertificate
        : { licenseUrl: '/license', serverCertificateUrl: '/cert' };
      hls = new Hls({
        emeEnabled: true,
        drmSystems: {
          'com.widevine.alpha': widevine,
        },
        // 宽限：本地服务，无需重试策略
        fragLoadingMaxRetry: 2,
        manifestLoadingMaxRetry: 2,
      });
      // 诊断：hls 管线关键事件逐个埋点；bundle 是 hls.js 1.5.13，不暴露
      // KEY_SYSTEM_* 公共事件（只有 ErrorDetails 常量），按存在性守卫自动跳过
      let firstFragLogged = false, firstBufferedLogged = false;
      const evt = (name, fn) => {
        if (Hls.Events && Hls.Events[name]) { hls.on(Hls.Events[name], fn); return true; }
        send('log', {msg: 'hls.js 无 ' + name + ' 事件（当前版本不暴露，跳过）'});
        return false;
      };
      evt('MEDIA_ATTACHED', () => send('log', {msg: 'MSE attach 完成'}));
      evt('BUFFER_CREATED', (e, d) => send('log', {msg: 'MSE SourceBuffer 已建: ' + Object.keys(d.tracks || {}).join('+')}));
      evt('LEVEL_LOADED', (e, d) => send('log', {
        msg: 'LEVEL_LOADED 分段数='
          + (d.details && d.details.fragments ? d.details.fragments.length : '?')
          + ' 时长=' + (d.details ? d.details.totalduration.toFixed(1) : '?') + 's'}));
      evt('FRAG_LOADED', (e, d) => {
        if (!firstFragLogged) {
          firstFragLogged = true;
          send('log', {msg: '首个 FRAG_LOADED sn=' + (d.frag ? d.frag.sn : '?') + ' bytes=' + (d.payload ? d.payload.byteLength : '?')});
        }
      });
      evt('FRAG_BUFFERED', (e, d) => {
        if (!firstBufferedLogged) {
          firstBufferedLogged = true;
          send('log', {msg: '首个 FRAG_BUFFERED（分段已进 MSE）sn=' + (d.frag ? d.frag.sn : '?')});
        }
      });
      evt('BUFFER_APPENDED', (e, d) => send('log', {msg: 'BUFFER_APPENDED type=' + d.type}));
      evt('KEY_SYSTEM_ACCESS', (e, d) => send('log', {msg: 'KEY_SYSTEM_ACCESS'}));
      hls.on(Hls.Events.ERROR, (ev, data) => {
        // 反代把 license / 证书失败原因写在 500 响应体里；HLS.js 错误数据带响应时就一并带回 Dart
        let extra = '';
        try {
          const r = data.response;
          if (r && r.code) extra += ' http=' + r.code;
          const d = r && r.data;
          if (d) {
            const text = typeof d === 'string' ? d : new TextDecoder().decode(d.slice(0, 256));
            if (text) extra += ' ' + text;
          }
        } catch (e) {}
        send('log', {msg: 'HLS ERROR ' + data.type + '/' + data.details + ' fatal=' + data.fatal + extra});
        if (data.fatal) send('error', {msg: data.details + extra});
      });
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        send('log', {msg: '清单已解析'});
        audio.muted = true;
        audio.play().then(() => { audio.muted = false; }).catch(() => {});
      });
      hls.loadSource('/audio.m3u8');
      hls.attachMedia(audio);
      send('log', {msg: certDegraded ? 'hls 已启动（降级：无 serverCertificate）' : 'hls 已启动'});
    };

    // createMediaKeys 挂起（hook 6s 未 settle 广播 'emeStall'）→ 原地销毁 hls 重建为无证书配置。
    // 只降级一次（stallHandled）；降配实例仍挂起则 send('error') 交回 Dart 现有错误通道。
    let stallHandled = certDegraded; // 已降级的页面本次直接算「已降级」，再挂立即报错
    const onEmeStall = (ev) => {
      if (!ev.detail || ev.detail.stage !== 'createMediaKeys') return;
      if (stallHandled) {
        // 降配实例仍挂起：不可恢复，只报一次并摘除监听
        window.removeEventListener('emeStall', onEmeStall);
        send('error', {msg: 'createMediaKeys 仍挂起（已按无 serverCertificate 降级重建，本机 WebView EME 不可用）'});
        return;
      }
      stallHandled = true;
      certDegraded = true;
      send('log', {msg: 'createMediaKeys 挂起 → 原地重建 hls（去掉 serverCertificateUrl）'});
      buildHls(); // 监听保留：继续观察降配实例是否也挂起
    };
    window.addEventListener('emeStall', onEmeStall);
    buildHls();
    return 'ok';
  } catch (e) {
    return 'ERR:' + String(e);
  }
})();

// 启动时探测一次 Widevine 是否可用：结果写进日志，不可用时上报给 Dart
//（该设备随后的播放错误按「缺 Widevine」归类，提示重试无意义）
(async () => {
  try {
    const access = await navigator.requestMediaKeySystemAccess('com.widevine.alpha', [{
      initDataTypes: ['cenc'],
      audioCapabilities: [{contentType: 'audio/mp4; codecs="mp4a.40.2"'}],
    }]);
    send('log', {msg: 'Widevine 可用 ' + JSON.stringify(access.getConfiguration().audioCapabilities)});
  } catch (e) {
    send('log', {msg: 'Widevine 不可用: ' + e});
    send('widevineUnavailable', {msg: String(e)});
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
