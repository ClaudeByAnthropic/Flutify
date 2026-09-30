// 原始 AP 握手探针：逐步打印每个阶段的字节，用于定位协议偏差。
// dart run tool/ap_raw.dart [--variant mine|noprefix|minimal]
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutify_app/services/auth/proto_codec.dart';
import 'package:flutify_app/services/protocol/ap_crypto.dart' as ap_crypto;

Future<void> main(List<String> args) async {
  final variant = args.isNotEmpty ? args.first : 'mine';

  // 解析接入点
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse('https://apresolve.spotify.com/?type=accesspoint'));
  final resp = await req.close();
  final body = await resp.transform(SystemEncoding().decoder).join();
  final entries = RegExp(r'"([^"]+)"')
      .allMatches(RegExp(r'"accesspoint"\s*:\s*\[([^\]]*)\]').firstMatch(body)!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
  final (host, port) = (entries.first.split(':')[0], int.parse(entries.first.split(':')[1]));
  print('AP: $host:$port  variant=$variant');

  final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));

  // 构造 ClientHello
  final dh = ap_crypto.DhLocalKeys.random();
  final rnd = Random.secure();
  final nonce = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));

  final buildInfo = ProtoWriter()
    ..varintAlways(10, 0) // product = PRODUCT_CLIENT
    ..varintAlways(20, 0) // product_flags = PRODUCT_FLAG_NONE
    ..varintAlways(30, 0x27) // platform
    ..int64(40, 124200290); // version
  final dhHello = ProtoWriter()
    ..bytes(10, dh.publicKey)
    ..varintAlways(20, 1);
  final loginCryptoHello = ProtoWriter()..message(10, dhHello);
  final hello = ProtoWriter()
    ..message(10, buildInfo)
    ..varintAlways(30, 0)
    ..message(50, loginCryptoHello)
    ..bytes(60, nonce)
    ..bytes(70, Uint8List.fromList([0x1e]));
  final helloBytes = hello.toBytes();

  List<int> frame;
  switch (variant) {
    case 'nothing':
      frame = [];
      break;
    case 'garbage':
      frame = List.generate(153, (i) => (i * 7) & 0xff);
      break;
    case 'noprefix':
      frame = [...u32(4 + helloBytes.length), ...helloBytes];
      break;
    case 'minimal':
      // 去掉 product_flags 与 padding，gc 最小长度
      final dhHello2 = ProtoWriter()
        ..bytes(10, _stripLeadingZeros(dh.publicKey))
        ..varintAlways(20, 1);
      final hello2 = ProtoWriter()
        ..message(10, buildInfo)
        ..varintAlways(30, 0)
        ..message(50, ProtoWriter()..message(10, dhHello2))
        ..bytes(60, nonce);
      final bytes2 = hello2.toBytes();
      frame = [0x00, 0x04, ...u32(6 + bytes2.length), ...bytes2];
      break;
    default:
      frame = [0x00, 0x04, ...u32(6 + helloBytes.length), ...helloBytes];
  }
  print('hello frame: ${frame.length}B  head=${frame.take(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

  final sw = Stopwatch()..start();
  socket.add(frame);
  await socket.flush();

  final received = BytesBuilder();
  socket.listen(
    (data) {
      received.add(data);
      print('  [+${sw.elapsedMilliseconds}ms] recv ${data.length}B '
          '${data.take(24).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    },
    onDone: () => print('  [+${sw.elapsedMilliseconds}ms] server CLOSED '
        '(total recv ${received.length}B)'),
    onError: (e) => print('  [+${sw.elapsedMilliseconds}ms] error $e'),
  );

  await Future.delayed(const Duration(seconds: 8));
  socket.destroy();
  client.close(force: true);
}

List<int> u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

Uint8List _stripLeadingZeros(Uint8List data) {
  var i = 0;
  while (i < data.length - 1 && data[i] == 0) {
    i++;
  }
  return Uint8List.sublistView(data, i);
}
