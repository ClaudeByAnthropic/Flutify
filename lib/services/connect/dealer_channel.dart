import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// dealer 长连接的最小传输抽象：只收发文本帧，便于测试时替换成内存实现。
abstract class DealerChannel {
  /// 收到的文本帧；连接关闭时流结束，出错时流报错。
  Stream<String> get messages;

  void send(String text);

  Future<void> close();
}

/// 建立 dealer 连接：[uri] 已带 `access_token`，[headers] 只含 `User-Agent` 这类握手头。
typedef DealerConnector = Future<DealerChannel> Function(Uri uri, Map<String, String> headers);

/// 默认实现：dart:io WebSocket。
class WebSocketDealerChannel implements DealerChannel {
  final WebSocket _socket;

  WebSocketDealerChannel._(this._socket);

  static Future<DealerChannel> connect(Uri uri, Map<String, String> headers) async {
    final socket = await WebSocket.connect(uri.toString(), headers: headers);
    return WebSocketDealerChannel._(socket);
  }

  /// dealer 只发文本帧；万一收到二进制帧按 UTF-8 解成文本，交给上层 JSON 解析去判断。
  @override
  Stream<String> get messages => _socket.map((data) => data is String ? data : utf8.decode(data as List<int>));

  @override
  void send(String text) => _socket.add(text);

  @override
  Future<void> close() => _socket.close();
}
