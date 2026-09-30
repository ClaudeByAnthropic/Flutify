// 开发工具：用 App 已保存的会话做端到端实测（纯 Dart，无需运行 App）。
//
// 用法（在 app 目录）：
//   dart run tool/live_probe.dart play [trackId]   完整曲目链路：metadata → storage-resolve → AP 密钥 → CDN 解密
//   dart run tool/live_probe.dart library          媒体库：collection/v2/paging、rootlist、metadata JSON、color-lyrics
//
// 终端只打印状态码、数量与字段结构，不打印任何令牌或账号数据；
// 完整响应写入 tool/probe_out/（已 gitignore，含账号数据，不得复制进测试或文档）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/auth/proto_codec.dart';
import 'package:flutify_app/services/protocol/track_audio_loader.dart';
import 'package:flutify_app/services/protocol/track_metadata.dart';
import 'package:http/http.dart' as http;

const _ua = 'Spotify/130100234 Win32_x86_64/0 (PC desktop)';
const _appVersion = '1.3.1.234.g59d6bf59';
const _spclient = 'https://spclient.wg.spotify.com';

late final String _token;
late final String _clientToken;
late final String _username;
final _out = Directory('tool/probe_out');

Map<String, String> _headers({String accept = 'application/json'}) => {
      'Authorization': 'Bearer $_token',
      if (_clientToken.isNotEmpty) 'client-token': _clientToken,
      'User-Agent': _ua,
      'app-platform': 'Win32_x86_64',
      'spotify-app-version': _appVersion,
      'Accept': accept,
    };

Future<void> main(List<String> args) async {
  final prefs = jsonDecode(
    File('${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  _token = prefs['flutter.sp_access_token'] as String? ?? '';
  _clientToken = prefs['flutter.sp_client_token'] as String? ?? '';
  _username = prefs['flutter.sp_username'] as String? ?? '';
  final expiry = prefs['flutter.sp_access_token_expiry'] as int? ?? 0;
  final left = Duration(milliseconds: expiry - DateTime.now().millisecondsSinceEpoch);
  stdout.writeln('会话：method=${prefs['flutter.sp_auth_method']} token 剩余 ${left.inMinutes} 分钟 '
      'username=${_username.isEmpty ? '(空)' : '(已保存)'}');
  if (left.isNegative) {
    stdout.writeln('access_token 已过期，请先打开 App 让它续期');
    exit(1);
  }
  await _out.create(recursive: true);

  final mode = args.isEmpty ? 'play' : args.first;
  if (mode == 'play') await _play(args.length > 1 ? args[1] : '0VjIjW4GlUZAMYd2vXMi3b');
  if (mode == 'library') await _library();
  if (mode == 'meta') await _meta(args.length > 1 ? args[1] : '0VjIjW4GlUZAMYd2vXMi3b');
  if (mode == 'ext') await _ext(args.length > 1 ? args[1] : '0VjIjW4GlUZAMYd2vXMi3b');
  exit(0);
}

/// extended-metadata：按扩展类型请求，打印响应的字段树（只含字段号 / 长度）。
Future<void> _ext(String track) async {
  final c = http.Client();
  for (final path in ['/extended-metadata/v0/extended-metadata', '/extended-metadata/v3/extensions/batch-get']) {
    for (final kind in [5, 10]) {
      final req = ProtoWriter()
        ..message(1, ProtoWriter()..string(1, 'from_token'))
        ..message(
          2,
          ProtoWriter()
            ..string(1, 'spotify:track:$track')
            ..message(2, ProtoWriter()..varintAlways(1, kind)),
        );
      final res = await c.post(
        Uri.parse('$_spclient$path'),
        headers: {
          ..._headers(accept: 'application/protobuf'),
          'Content-Type': 'application/protobuf',
        },
        body: req.toBytes(),
      );
      stdout.writeln('$path kind=$kind HTTP ${res.statusCode} ${res.bodyBytes.length}B');
      if (res.statusCode == 200) {
        File('${_out.path}/ext_${path.split('/')[2]}_$kind.bin').writeAsBytesSync(res.bodyBytes);
        stdout.writeln(_tree(res.bodyBytes, 0));
      }
    }
  }
  c.close();
}

/// 递归打印 protobuf 字段树（嵌套消息尽力解析；只显示字段号、类型与长度）。
String _tree(List<int> bytes, int depth) {
  final sb = StringBuffer();
  try {
    ProtoReader(Uint8List.fromList(bytes)).forEach((f) {
      final pad = '  ' * (depth + 1);
      if (f.wireType == 2) {
        final b = f.bytesValue;
        final printable = b.every((x) => x >= 0x20 && x < 0x7f);
        if (printable && b.isNotEmpty && b.length < 80) {
          sb.writeln('$pad#${f.number} str(${b.length}) ${String.fromCharCodes(b).replaceAll(RegExp(r'[0-9a-zA-Z]{20,}'), '<id>')}');
        } else {
          sb.writeln('$pad#${f.number} bytes(${b.length})');
          if (depth < 6 && b.isNotEmpty) {
            final sub = _tree(b, depth + 1);
            if (!sub.contains('!parse')) sb.write(sub);
          }
        }
      } else {
        sb.writeln('$pad#${f.number} varint=${f.wireType == 0 ? f.varintValue : '?'}');
      }
    });
  } catch (_) {
    return '!parse';
  }
  return sb.toString();
}

/// 列出 metadata/4/track 顶层字段号与各版本的音频格式（不输出值）。
Future<void> _meta(String track) async {
  final c = http.Client();
  for (final q in ['', '?market=from_token']) {
    final res = await c.get(
      Uri.parse('$_spclient/metadata/4/track/${_hex(track)}$q'),
      headers: _headers(accept: 'application/x-protobuf'),
    );
    stdout.writeln('metadata$q HTTP ${res.statusCode} ${res.bodyBytes.length}B');
    if (res.statusCode != 200) continue;
    final fields = <int, int>{};
    ProtoReader(res.bodyBytes).forEach((f) => fields[f.number] = (fields[f.number] ?? 0) + 1);
    stdout.writeln('  顶层字段号×次数=$fields');
    final meta = TrackMetadata.parse(res.bodyBytes);
    stdout.writeln('  files=${meta.files.map((f) => f.format.name).toList()} '
        'alternatives=${meta.alternatives.map((a) => a.files.map((f) => f.format.name).toList()).toList()}');
  }
  c.close();
}

Future<void> _play(String track) async {
  final loader = TrackAudioLoader(
    accessToken: () async => _token,
    clientToken: () async => _clientToken,
    cacheDirectory: _out.path,
  );
  final sw = Stopwatch()..start();
  try {
    final audio = await loader.load(track);
    final head = await audio.file.openRead(0, 4).fold<List<int>>([], (a, b) => a..addAll(b));
    stdout.writeln('✅ ${sw.elapsedMilliseconds}ms 格式=${audio.source.format.name} '
        '大小=${audio.file.lengthSync()}B 文件头=${String.fromCharCodes(head)} 时长=${audio.durationMs}ms');
  } catch (e, s) {
    stdout.writeln('❌ ${sw.elapsedMilliseconds}ms $e');
    stdout.writeln(s.toString().split('\n').take(6).join('\n'));
  } finally {
    loader.dispose();
  }
}

Future<void> _library() async {
  final c = http.Client();
  // collection/v2/paging：tracks+albums 在 "collection" 集合，关注艺人在 "artist" 集合
  for (final set in ['collection', 'artist']) {
    final body = ProtoWriter()
      ..string(1, _username)
      ..string(2, set)
      ..varintAlways(4, 300);
    final res = await c.post(
      Uri.parse('$_spclient/collection/v2/paging'),
      headers: {
        ..._headers(accept: 'application/vnd.collection-v2.spotify.proto'),
        'Content-Type': 'application/vnd.collection-v2.spotify.proto',
      },
      body: body.toBytes(),
    );
    final kinds = <String, int>{};
    var next = false;
    if (res.statusCode == 200) {
      ProtoReader(res.bodyBytes).forEach((f) {
        if (f.number == 1 && f.wireType == 2) {
          f.asMessage.forEach((i) {
            if (i.number == 1 && i.wireType == 2) {
              final kind = i.asString.split(':').elementAt(1);
              kinds[kind] = (kinds[kind] ?? 0) + 1;
            }
          });
        }
        if (f.number == 2 && f.wireType == 2) next = f.bytesValue.isNotEmpty;
      });
      File('${_out.path}/collection_$set.bin').writeAsBytesSync(res.bodyBytes);
    }
    stdout.writeln('collection[$set] HTTP ${res.statusCode} 条目=$kinds 还有下一页=$next');
  }

  // rootlist（JSON）
  final root = await c.get(
    Uri.parse('$_spclient/playlist/v2/user/${Uri.encodeComponent(_username)}/rootlist'
        '?decorate=revision,attributes,length,owner&from=0&length=200'),
    headers: _headers(),
  );
  stdout.writeln('rootlist HTTP ${root.statusCode}');
  if (root.statusCode == 200) {
    File('${_out.path}/rootlist.json').writeAsBytesSync(root.bodyBytes);
    final j = jsonDecode(utf8.decode(root.bodyBytes)) as Map<String, dynamic>;
    stdout.writeln('  顶层键=${j.keys.toList()}');
    final contents = j['contents'] as Map<String, dynamic>? ?? {};
    stdout.writeln('  contents 键=${contents.keys.toList()}');
    final items = contents['items'] as List? ?? [];
    final metas = contents['metaItems'] as List? ?? [];
    stdout.writeln('  items=${items.length} metaItems=${metas.length}');
    if (metas.isNotEmpty) stdout.writeln('  metaItem 结构=${_shape(metas.first)}');
    if (items.isNotEmpty) stdout.writeln('  item 结构=${_shape(items.first)}');
  }

  // metadata JSON：专辑 / 艺人（After Hours / The Weeknd，公开实体）
  for (final (kind, hex) in [
    ('album', _hex('4yP0hdKOZPNshxUOjY0cZj')),
    ('artist', _hex('1Xyo4u8uXC1ZmMpatF05PJ')),
  ]) {
    final res = await c.get(Uri.parse('$_spclient/metadata/4/$kind/$hex?market=from_token'), headers: _headers());
    stdout.writeln('metadata/$kind HTTP ${res.statusCode}');
    if (res.statusCode == 200) {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      File('${_out.path}/metadata_$kind.json').writeAsStringSync(jsonEncode(j));
      stdout.writeln('  结构=${_shape(j)}');
    }
  }

  // color-lyrics（Blinding Lights）
  final ly = await c.get(
    Uri.parse('$_spclient/color-lyrics/v2/track/0VjIjW4GlUZAMYd2vXMi3b?format=json&vocalRemoval=false&market=from_token'),
    headers: _headers(),
  );
  stdout.writeln('color-lyrics HTTP ${ly.statusCode}');
  if (ly.statusCode == 200) {
    stdout.writeln('  结构=${_shape(jsonDecode(utf8.decode(ly.bodyBytes)))}');
  }
  c.close();
}

/// 只输出字段名与类型，不输出值。
String _shape(Object? v, [int depth = 0]) {
  if (depth > 3) return '…';
  if (v is Map) return '{${v.entries.map((e) => '${e.key}:${_shape(e.value, depth + 1)}').join(', ')}}';
  if (v is List) return v.isEmpty ? '[]' : '[${_shape(v.first, depth + 1)} ×${v.length}]';
  return v.runtimeType.toString();
}

/// base62 → 32 位十六进制 GID。
String _hex(String base62) {
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  var n = BigInt.zero;
  for (final ch in base62.split('')) {
    n = n * BigInt.from(62) + BigInt.from(alphabet.indexOf(ch));
  }
  return n.toRadixString(16).padLeft(32, '0');
}