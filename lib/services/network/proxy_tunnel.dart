import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'network_proxy.dart';
import 'proxy_mode.dart';

/// AP only needs byte writes/flush/close; its stream can be TCP or binary WS.
class TunnelSocket {
  final Socket? tcpSocket;
  final void Function(List<int>) add;
  final Future<void> Function() flush;
  final void Function() destroy;
  TunnelSocket({
    this.tcpSocket,
    required this.add,
    required this.flush,
    required this.destroy,
  });
  factory TunnelSocket.tcp(Socket socket) => TunnelSocket(
    tcpSocket: socket,
    add: socket.add,
    flush: socket.flush,
    destroy: socket.destroy,
  );
}

/// 经 [NetworkProxy] 建立原始 TCP 连接（接入点协议不是 HTTP，不能直接交给 HttpClient）。
///
/// 需要代理时向 HTTP 代理发 `CONNECT host:port`，收到 200 后这条连接就是到目标的透明隧道；
/// 手动代理配了用户名 / 密码时会随 CONNECT 带上 `Proxy-Authorization: Basic …`。
/// 返回的 [input] 是隧道建立后的数据（代理响应头之后的字节）；直连时就是 socket 本身。
/// socket 是单订阅流，读响应头时已经订阅过，所以调用方必须改为读 [input]。
class ProxyTunnel {
  ProxyTunnel._();

  static Future<({TunnelSocket socket, Stream<Uint8List> input})> connect(
    String host,
    int port, {
    required Duration timeout,
    NetworkProxy? proxy,
    bool useGateway = true,
  }) async {
    final net = proxy ?? NetworkProxy.instance;
    final gateway = net.gateway;
    if (useGateway && gateway.enabled) {
      // A dedicated client makes a timed-out handshake cancellable and uses
      // the same forward-proxy policy as all other requests.
      final client = HttpClient()..findProxy = net.findProxy;
      try {
        final ws = await WebSocket.connect(
          gateway.tunnel(host, port).toString(),
          headers: gateway.headers,
          customClient: client,
          compression: CompressionOptions.compressionOff,
        ).timeout(timeout);
        ws.pingInterval = const Duration(seconds: 30);
        return (
          socket: TunnelSocket(
            add: (bytes) => ws.add(Uint8List.fromList(bytes)),
            flush: () async {},
            destroy: () {
              unawaited(ws.close());
              client.close(force: true);
            },
          ),
          input: ws.map((frame) {
            if (frame is! List<int>)
              throw const ProxyTunnelException(
                'AP tunnel received a text frame',
              );
            return Uint8List.fromList(frame);
          }),
        );
      } catch (_) {
        client.close(force: true);
        rethrow;
      }
    }
    final endpoint = net.endpointFor(
      Uri(scheme: 'https', host: host, port: port),
    );
    if (endpoint == null) {
      final socket = await Socket.connect(host, port, timeout: timeout);
      return (socket: TunnelSocket.tcp(socket), input: socket);
    }

    final socket = await Socket.connect(
      endpoint.host,
      endpoint.port,
      timeout: timeout,
    );
    final target = host.contains(':') ? '[$host]:$port' : '$host:$port';
    // 认证只在配置了手动代理凭据时带上（CONNECT 头是自己拼的，用户名 / 密码任意字符都安全）
    final auth = net.mode == ProxyMode.manual && net.manualHasCredentials
        ? 'Proxy-Authorization: Basic ${base64Encode(utf8.encode('${net.manualUsername}:${net.manualPassword}'))}\r\n'
        : '';
    socket.add(
      ascii.encode('CONNECT $target HTTP/1.1\r\nHost: $target\r\n$auth\r\n'),
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
          if (bytes.length > 16 * 1024) {
            _fail(established, socket, const ProxyTunnelException('代理响应头过长'));
          }
          return;
        }
        final status = latin1.decode(bytes.sublist(0, end)).split('\r\n').first;
        if (RegExp(r'^HTTP/1\.[01] 407').hasMatch(status)) {
          // 凭据缺失或不对：单独说清楚，免得被当成「代理挂了」排查半天
          _fail(
            established,
            socket,
            ProxyTunnelException('代理认证失败（$status）：请检查用户名与密码'),
          );
          return;
        }
        if (!RegExp(r'^HTTP/1\.[01] 2\d\d').hasMatch(status)) {
          _fail(established, socket, ProxyTunnelException('代理拒绝连接：$status'));
          return;
        }
        open = true;
        established.complete();
        // 响应头后面紧跟的字节已属于目标服务器
        if (bytes.length > end + 4) {
          output.add(Uint8List.sublistView(bytes, end + 4));
        }
      },
      onError: (Object e) => established.isCompleted
          ? output.addError(e)
          : _fail(established, socket, e),
      onDone: () {
        if (!established.isCompleted) {
          _fail(established, socket, const ProxyTunnelException('代理关闭了连接'));
        }
        output.close();
      },
    );

    try {
      await established.future.timeout(timeout);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
    return (socket: TunnelSocket.tcp(socket), input: output.stream);
  }

  static void _fail(Completer<void> established, Socket socket, Object error) {
    if (!established.isCompleted) established.completeError(error);
    socket.destroy();
  }

  /// `\r\n\r\n` 的位置；没有时返回 -1。
  static int _headerEnd(Uint8List b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
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
