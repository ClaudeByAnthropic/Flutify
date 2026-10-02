import 'dart:async';
import 'dart:io';

import 'oauth_client_config.dart';
import 'oauth_pkce_service.dart';

/// 本机回环 HTTP 服务：接收浏览器授权后重定向到 `http://127.0.0.1:<port><path>` 的请求，取出授权码。
///
/// 只接受一次与 [expectedState] 匹配的回调；收到后回一张"可以返回 App"的页面并自动关闭。
class OAuthLoopbackServer {
  HttpServer? _server;
  Completer<String>? _completer;

  /// 启动监听并返回等待授权码的 Future。端口被占用时抛 [OAuthException]。
  Future<Future<String>> start({
    required String expectedState,
    String path = '/callback',
    int port = OAuthClientConfig.redirectPort,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    await close();
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      throw OAuthException('本机端口 $port 被占用，无法接收授权回调');
    }
    final completer = _completer = Completer<String>();
    _server!.listen((request) => _handle(request, path, expectedState, completer));

    return completer.future.timeout(timeout, onTimeout: () {
      throw const OAuthException('等待授权超时，请重试');
    }).whenComplete(close);
  }

  Future<void> _handle(HttpRequest request, String path, String expectedState, Completer<String> completer) async {
    // 服务收到回调后即关闭，不能让客户端复用该连接
    request.response.persistentConnection = false;
    if (request.uri.path != path) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final params = request.uri.queryParameters;
    final error = params['error'];
    final code = params['code'];
    final ok = error == null && code != null && params['state'] == expectedState;

    request.response.headers.contentType = ContentType.html;
    request.response.write(_page(ok));
    await request.response.close();

    if (completer.isCompleted) return;
    if (ok) {
      completer.complete(code);
    } else if (error != null) {
      completer.completeError(OAuthException.fromError(error));
    } else {
      completer.completeError(const OAuthException('授权回调校验失败（state 不匹配），请重试'));
    }
  }

  /// 取消等待并关闭端口。
  Future<void> close() async {
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const OAuthException('已取消授权'));
    }
    _completer = null;
    await _server?.close(force: true);
    _server = null;
  }

  static String _page(bool ok) {
    final title = ok ? '授权完成' : '授权未完成';
    final body = ok ? '你可以关闭此页面，返回 Flutify。' : '请返回 Flutify 重试。';
    final color = ok ? '#1ED760' : '#FF6B6B';
    // 尽力自动关闭：浏览器只允许脚本关闭「由脚本打开」的标签页，
    // 外部程序（url_launcher）打开的标签多数情况下会被拦，所以保留手动关闭提示。
    final script = ok
        ? "<script>setTimeout(function(){window.open('','_self');window.close();},600)</script>"
        : '';
    return '''<!doctype html><html lang="zh"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Flutify · $title</title>
<body style="margin:0;height:100vh;display:grid;place-items:center;background:#121318;color:#E4E1E9;
font-family:-apple-system,'Segoe UI','PingFang SC',sans-serif">
<div style="text-align:center"><div style="width:56px;height:56px;margin:0 auto 20px;border-radius:50%;
background:$color"></div><h1 style="font-size:24px;margin:0 0 8px">$title</h1>
<p style="margin:0;color:#A5A4B2">$body</p></div>$script</body></html>''';
  }
}
