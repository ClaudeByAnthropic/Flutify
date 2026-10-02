import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'network_proxy.dart';

/// 经 [NetworkProxy] 建立原始 TCP 连接（接入点协议不是 HTTP，不能直接交给 HttpClient）。
///
/// 需要代理时向 HTTP 代理发 `CONNECT host:port`，收到 200 后这条连接就是到目标的透明隧道。
/// 返回的 [input] 是隧道建立后的数据（代理响应头之后的字节）；直连时就是 socket 本身。
/// socket 是单订阅流，读响应头时已经订阅过，所以调用方必须改为读 [input]。
class ProxyTunnel {
  ProxyTunnel._();

  static Future<({Socket socket, Stream<Uint8List> input})> connect(
    String host,
    int port, {
    required Duration timeout,
    NetworkProxy? proxy,
  }) async {
    final endpoint = (proxy ?? NetworkProxy.instance).endpointFor(
      Uri(scheme: 'https', host: host, port: port),
    );
    if (endpoint == null) {
      final socket = await Socket.connect(host, port, timeout: timeout);
      return (socket: socket, input: socket);
    }

    final socket = await Socket.connect(
      endpoint.host,
      endpoint.port,
      timeout: timeout,
    );
    final target = host.contains(':') ? '[$host]:$port' : '$host:$port';
    socket.add(
      ascii.encode('CONNECT $target HTTP/1.1\r\nHost: $target\r\n\r\n'),
    );

    final output = StreamController<Uint8List>();
    final established = Completer<void>();
    final header = BytesBuilder(copy: false);
    var open = false;

    socket.listen(
      (data) {
        if (open) {
          output.add(data);
          return;
        }
        header.add(data);
        final bytes = header.toBytes();
        final end = _headerEnd(bytes);
        if (end < 0) {
          if (bytes.length > 16 * 1024)
            _fail(established, socket, const ProxyTunnelException('代理响应头过长'));
          return;
        }
        final status = latin1.decode(bytes.sublist(0, end)).split('\r\n').first;
        if (!RegExp(r'^HTTP/1\.[01] 2\d\d').hasMatch(status)) {
          _fail(established, socket, ProxyTunnelException('代理拒绝连接：$status'));
          return;
        }
        open = true;
        established.complete();
        // 响应头后面紧跟的字节已属于目标服务器
        if (bytes.length > end + 4)
          output.add(Uint8List.sublistView(bytes, end + 4));
      },
      onError: (Object e) => established.isCompleted
          ? output.addError(e)
          : _fail(established, socket, e),
      onDone: () {
        if (!established.isCompleted)
          _fail(established, socket, const ProxyTunnelException('代理关闭了连接'));
        output.close();
      },
    );

    try {
      await established.future.timeout(timeout);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
    return (socket: socket, input: output.stream);
  }

  static void _fail(Completer<void> established, Socket socket, Object error) {
    if (!established.isCompleted) established.completeError(error);
    socket.destroy();
  }

  /// `\r\n\r\n` 的位置；没有时返回 -1。
  static int _headerEnd(Uint8List b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10)
        return i;
    }
    return -1;
  }
}

class ProxyTunnelException implements Exception {
  final String message;
  const ProxyTunnelException(this.message);

  @override
  String toString() => message;
}
