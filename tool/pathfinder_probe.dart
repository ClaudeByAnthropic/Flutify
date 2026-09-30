// 开发工具：用 App 已保存的桌面版会话探测 Pathfinder / spclient 接口，记录入参是否被接受与响应结构。
//
// 用法（在 app 目录）：dart run tool/pathfinder_probe.dart [操作名 ...]
// 响应完整写入 tool/probe_out/<操作名>.json（已 gitignore，含账号数据）；终端只打印状态码与字段结构，
// 不打印任何令牌。
import 'dart:convert';
import 'dart:io';

const _ua = 'Spotify/130100234 Win32_x86_64/0 (PC desktop)';
const _appVersion = '1.3.1.234.g59d6bf59';

// 探测用样本实体
const _album = 'spotify:album:4yP0hdKOZPNshxUOjY0cZj'; // After Hours
const _artist = 'spotify:artist:1Xyo4u8uXC1ZmMpatF05PJ'; // The Weeknd
const _playlistId = '37i9dQZF1DXcBWIGoYBM5M'; // Today's Top Hits

final Map<String, _Op> _ops = {
  'home': _Op('76243c78b0e20ecdbe41b794dec8cbe73f75e585b0a7201b8d2e84578412847a', {
    'homeEndUserIntegration': 'INTEGRATION_DESKTOP',
    'timeZone': 'Asia/Shanghai',
    'sp_t': '',
    'facet': '',
    'sectionItemsLimit': 10,
    'includeEpisodeContentRatingsV2': false,
  }),
  'browseAll': _Op('dbd8b55e09a58afc52eab438bc228ba28fd72ac2f2148c6c26354980e4579001', {
    'pagePagination': {'offset': 0, 'limit': 10},
    'sectionPagination': {'offset': 0, 'limit': 99},
    'browseEndUserIntegration': 'INTEGRATION_DESKTOP',
  }),
  'getAlbum': _Op('6a74b456cd1735c9193d9e8ec8cc5184cad7ce13572210315229db3975964361', {
    'uri': _album,
    'locale': '',
    'offset': 0,
    'limit': 50,
  }),
  'queryArtistOverview': _Op('7bdc7185c219898c7a2b659cfff2f8ce066dd2d9a97f8b7c4bde92ccfec28310', {
    'uri': _artist,
    'locale': '',
    'preReleaseV2': false,
  }),
  'queryArtistDiscographyAll': _Op('5e07d323febb57b4a56a42abbf781490e58764aa45feb6e3dc0591564fc56599', {
    'uri': _artist,
    'offset': 0,
    'limit': 20,
    'order': 'DATE_DESC',
  }),
  'searchDesktop': _Op('db61238974d27839a136c9dc02bfdbe3fab7635f21cf85976ebff9a1ee281345', {
    'searchTerm': 'weeknd',
    'offset': 0,
    'limit': 10,
    'numberOfTopResults': 5,
    'includeAudiobooks': false,
    'includeArtistHasConcertsField': false,
    'includePreReleases': false,
    'includeLocalConcertsField': false,
    'includeAuthors': false,
  }),
};

Future<void> main(List<String> args) async {
  final prefs = jsonDecode(
    File('${Platform.environment['APPDATA']}\\com.flutify.music\\flutify_app\\shared_preferences.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final token = prefs['flutter.sp_access_token'] as String;
  final clientToken = prefs['flutter.sp_client_token'] as String? ?? '';
  final expiry = prefs['flutter.sp_access_token_expiry'] as int? ?? 0;
  if (expiry < DateTime.now().millisecondsSinceEpoch) {
    stdout.writeln('access_token 已过期，请先打开 App 让它续期');
    exit(1);
  }

  final headers = {
    'authorization': 'Bearer $token',
    'client-token': clientToken,
    'user-agent': _ua,
    'app-platform': 'Win32_x86_64',
    'spotify-app-version': _appVersion,
    'accept': 'application/json',
  };
  final out = Directory('tool/probe_out')..createSync(recursive: true);
  final client = HttpClient();

  // 用歌单探测结果中的曲目 URI 批量补全曲目信息
  final playlistDump = File('${out.path}/playlist.json');
  if (playlistDump.existsSync()) {
    final items = (jsonDecode(playlistDump.readAsStringSync())['contents']['items'] as List).take(3);
    _ops['decorateContextTracks'] = _Op('383de00240775c39a6afe0b1055dc562b2a3930894201f9762f3fc32a74971c7', {
      'uris': [for (final i in items) i['uri']],
    });
  }

  final names = args.isEmpty ? [..._ops.keys, 'playlist'] : args;
  for (final name in names) {
    if (name == 'playlist') {
      await _get(client, 'playlist',
          Uri.parse('https://spclient.wg.spotify.com/playlist/v2/playlist/$_playlistId?decorate=attributes,length,owner'),
          headers, out);
      continue;
    }
    final op = _ops[name];
    if (op == null) continue;
    // 先试 v2（POST JSON），失败再试 v1（GET 查询参数）
    final body = jsonEncode({
      'variables': op.variables,
      'operationName': name,
      'extensions': {
        'persistedQuery': {'version': 1, 'sha256Hash': op.hash},
      },
    });
    final ok = await _post(client, '$name.v2', Uri.parse('https://api-partner.spotify.com/pathfinder/v2/query'), body,
        headers, out);
    if (!ok) {
      await _get(
        client,
        '$name.v1',
        Uri.parse('https://api-partner.spotify.com/pathfinder/v1/query').replace(queryParameters: {
          'operationName': name,
          'variables': jsonEncode(op.variables),
          'extensions': jsonEncode({
            'persistedQuery': {'version': 1, 'sha256Hash': op.hash},
          }),
        }),
        headers,
        out,
      );
    }
  }
  client.close();
}

Future<bool> _post(HttpClient c, String label, Uri uri, String body, Map<String, String> h, Directory out) async {
  final req = await c.postUrl(uri);
  h.forEach(req.headers.set);
  req.headers.contentType = ContentType.json;
  req.write(body);
  return _report(label, await req.close(), out);
}

Future<bool> _get(HttpClient c, String label, Uri uri, Map<String, String> h, Directory out) async {
  final req = await c.getUrl(uri);
  h.forEach(req.headers.set);
  return _report(label, await req.close(), out);
}

Future<bool> _report(String label, HttpClientResponse res, Directory out) async {
  final text = await res.transform(utf8.decoder).join();
  File('${out.path}/$label.json').writeAsStringSync(text);
  dynamic json;
  try {
    json = jsonDecode(text);
  } catch (_) {}
  final hasErrors = json is Map && json['errors'] != null;
  stdout.writeln('[$label] HTTP ${res.statusCode}${hasErrors ? '  errors: ${_short(jsonEncode(json['errors']))}' : ''}');
  if (json != null) stdout.writeln(_shape(json, 0, 4));
  return res.statusCode == 200 && !hasErrors;
}

String _short(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;

/// 打印 JSON 结构（键名与类型），数组只展开第一个元素。
String _shape(dynamic v, int depth, int maxDepth) {
  final pad = '  ' * (depth + 1);
  if (v is Map) {
    if (depth >= maxDepth) return '{…${v.length} keys}';
    return v.entries.map((e) => '\n$pad${e.key}: ${_shape(e.value, depth + 1, maxDepth)}').join();
  }
  if (v is List) {
    if (v.isEmpty) return '[]';
    return '[${v.length}] ${_shape(v.first, depth + 1, maxDepth)}';
  }
  if (v is String) return 'str(${v.length > 40 ? '${v.substring(0, 40)}…' : v})';
  return v.runtimeType.toString();
}

class _Op {
  final String hash;
  final Map<String, Object?> variables;
  const _Op(this.hash, this.variables);
}
