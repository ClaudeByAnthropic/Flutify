import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lrclib_candidate.dart';

/// 一次 LRCLIB 请求的结果。[networkError] 表示因断网 / 超时 / 限流 / 服务端错误没拿到结果，
/// 这种情况调用方不应把「没有歌词」当作定论缓存下来。
class LrclibResponse {
  final List<LrclibCandidate> candidates;
  final bool networkError;

  const LrclibResponse(this.candidates, {this.networkError = false});
}

/// LRCLIB（https://lrclib.net）公开歌词库，无需鉴权。
///
/// - `GET /api/get`：曲名 + 歌手 + 专辑 + 时长精确匹配，对不上返回 404（正常情况）；
/// - `GET /api/search`：按曲名 / 歌手或全文 `q` 搜索，返回数组。
///
/// 404 = 没有这条；429 / 5xx / 断网 / 超时最多再试两次（间隔递增），仍失败记为 [LrclibResponse.networkError]。
class LrclibClient {
  static const String baseUrl = 'https://lrclib.net/api';
  static const Duration timeout = Duration(seconds: 12);

  final http.Client _client;

  /// 重试前的等待；测试注入零延迟。
  final Future<void> Function(Duration) _sleep;

  LrclibClient(this._client, {Future<void> Function(Duration)? sleep}) : _sleep = sleep ?? Future.delayed;

  Future<LrclibResponse> get({required String track, required String artist, String album = '', int durationSec = 0}) =>
      _request('/get', {
        'track_name': track,
        'artist_name': artist,
        if (album.isNotEmpty) 'album_name': album,
        if (durationSec > 0) 'duration': '$durationSec',
      });

  Future<LrclibResponse> search({String? track, String? artist, String? q}) => _request('/search', {
    'track_name': ?track,
    if (artist != null && artist.isNotEmpty) 'artist_name': artist,
    'q': ?q,
  });

  Future<LrclibResponse> _request(String path, Map<String, String> query) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    for (var attempt = 0; ; attempt++) {
      int code;
      try {
        final res = await _client
            .get(uri, headers: const {'User-Agent': 'Flutify (lyrics fallback)', 'Accept': 'application/json'})
            .timeout(timeout);
        code = res.statusCode;
        if (code == 200) {
          try {
            return LrclibResponse(LrclibCandidate.listFrom(jsonDecode(utf8.decode(res.bodyBytes))));
          } on FormatException {
            return const LrclibResponse([]);
          }
        }
      } catch (_) {
        code = 0; // 断网 / 超时 / TLS 等
      }
      if (code == 404) return const LrclibResponse([]);
      final transient = code == 0 || code == 429 || code >= 500;
      if (!transient) return const LrclibResponse([]);
      if (attempt >= 2) return const LrclibResponse([], networkError: true);
      await _sleep(Duration(milliseconds: 600 * (attempt + 1)));
    }
  }
}
