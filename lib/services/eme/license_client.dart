import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Widevine license / application-certificate 反代客户端（CDM 请求体 → Spotify）。
///
/// 为什么要多入口：手机网络下部分 Spotify 域名会被掐 TLS 握手
/// （`HandshakeException: Connection terminated during handshake`），而同一服务的
/// 其它 spclient 入口可达——协议下载走的 `spclient.wg` 实测最稳，license 也在
/// `spclient.wg.spotify.com/widevine-license/v1/audio/license` 上正常应答
/// （见 `SpotifyApi/api-docs/06-播放与音视频/补充-音频流DRM与连接.md`）。
///
/// 行为：
/// - 每个请求按 [hosts] 顺序换入口尝试；网络类错误（握手被掐 / 超时 / 连接重置）
///   换下一个入口；
/// - HTTP 非 200 是业务错误（403 = 权限 / token 状态），换入口无益，直接抛；
/// - 成功过的入口记进 [lastGoodHost]，下次优先用它，避免每次都先撞一次失败的握手。
class WidevineLicenseClient {
  WidevineLicenseClient({
    required this.webToken,
    required this.clientToken,
    http.Client? client,
    this.hosts = defaultHosts,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  /// Web 播放器 access_token（Widevine 真密钥的身份凭据，sp_dc + TOTP 铸造）。
  final Future<String> Function() webToken;

  /// client-token（license / 证书都要）。
  final Future<String> Function() clientToken;

  /// spclient 入口，按顺序尝试。`spclient.wg` 是总入口，实测手机网络下最稳。
  static const List<String> defaultHosts = [
    'spclient.wg.spotify.com',
    'gae2-spclient.spotify.com',
    'gew1-spclient.spotify.com',
    'gue1-spclient.spotify.com',
  ];

  final http.Client _client;
  final List<String> hosts;
  final Duration timeout;

  /// 最近一次成功的入口；下次优先用它。
  String? lastGoodHost;

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36';

  /// license 反代：POST `/widevine-license/v1/audio/license`，返回 license 响应体。
  Future<Uint8List> postLicense(Uint8List request) async {
    try {
      final token = await webToken();
      final ct = await clientToken();
      return await _request('audio/license', (uri) {
        return _client.post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'client-token': ct,
            'User-Agent': _ua,
            'Referer': 'https://open.spotify.com/',
            'Content-Type': 'application/octet-stream',
          },
          body: request,
        );
      });
    } catch (e) {
      debugPrint('[eme] license 反代异常: $e');
      rethrow;
    }
  }

  /// Widevine application-certificate 反代（只需 client-token）。
  Future<Uint8List> fetchCert() async {
    try {
      final ct = await clientToken();
      return await _request('application-certificate', (uri) {
        return _client.get(
          uri,
          headers: {
            'client-token': ct,
            'User-Agent': _ua,
            'Referer': 'https://open.spotify.com/',
          },
        );
      });
    } catch (e) {
      debugPrint('[eme] 证书反代异常: $e');
      rethrow;
    }
  }

  /// 按入口顺序发请求；网络错误换入口，业务错误直接抛。
  Future<Uint8List> _request(
    String name,
    Future<http.Response> Function(Uri uri) send,
  ) async {
    final order = [
      ?lastGoodHost,
      for (final h in hosts)
        if (h != lastGoodHost) h,
    ];
    Object? lastError;
    for (final host in order) {
      final uri = Uri.parse('https://$host/widevine-license/v1/$name');
      try {
        final res = await send(uri).timeout(timeout);
        debugPrint(
            '[eme] license $name @ $host → HTTP ${res.statusCode} ${res.bodyBytes.length}B');
        if (res.statusCode != 200) {
          throw StateError('license $name 失败：HTTP ${res.statusCode}');
        }
        lastGoodHost = host;
        return res.bodyBytes;
      } on StateError {
        rethrow; // 业务错误：换入口无益
      } catch (e) {
        lastError = e;
        debugPrint('[eme] license $name @ $host 连接失败，换入口：$e');
      }
    }
    throw StateError('license $name 失败（所有入口均不可达）：$lastError');
  }
}
