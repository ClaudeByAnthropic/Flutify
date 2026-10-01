import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'oauth_client_config.dart';

/// 标准 OAuth2 授权码 + PKCE（accounts.spotify.com）。
///
/// 用户在系统浏览器里的 Spotify 官方登录页完成登录（人机验证、两步验证、Passkey 均由官方页面处理），
/// App 不接触密码，只用授权码换取 access_token / refresh_token。
/// client_id、回调地址与权限范围由 [OAuthClientConfig] 决定（桌面版或开发者应用）。
class OAuthPkceService {
  static const String authorizeEndpoint = 'https://accounts.spotify.com/authorize';
  static const String tokenEndpoint = 'https://accounts.spotify.com/api/token';

  final http.Client _client;

  /// 令牌请求的 User-Agent；为空时使用 http 默认 UA（开发者应用场景）。
  final String? userAgent;

  OAuthPkceService(this._client, {this.userAgent});

  /// 生成 PKCE 参数：verifier 为 64 位非保留字符，challenge = base64url(SHA256(verifier)) 去掉填充。
  static PkcePair generatePkce([Random? random]) {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = random ?? Random.secure();
    final verifier = List.generate(64, (_) => charset[rnd.nextInt(charset.length)]).join();
    return PkcePair(verifier: verifier, challenge: challengeFor(verifier));
  }

  static String challengeFor(String verifier) =>
      base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

  /// 随机 state，用于校验回调确实来自本次授权。
  static String generateState([Random? random]) {
    final rnd = random ?? Random.secure();
    return base64Url.encode(List.generate(18, (_) => rnd.nextInt(256))).replaceAll('=', '');
  }

  static Uri buildAuthorizeUrl({
    required OAuthClientConfig config,
    required String codeChallenge,
    required String state,
  }) {
    return Uri.parse(authorizeEndpoint).replace(queryParameters: {
      'client_id': config.clientId,
      'response_type': 'code',
      'redirect_uri': config.redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': codeChallenge,
      'state': state,
      'scope': config.scopes.join(' '),
    });
  }

  /// 用授权码换取令牌。
  Future<OAuthTokens> exchangeCode({
    required OAuthClientConfig config,
    required String code,
    required String codeVerifier,
  }) {
    return _postToken({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': config.redirectUri,
      'client_id': config.clientId,
      'code_verifier': codeVerifier,
    });
  }

  /// 用 refresh_token 续期；服务端可能轮换 refresh_token，未返回时沿用旧值。
  Future<OAuthTokens> refresh({required OAuthClientConfig config, required String refreshToken}) async {
    final tokens = await _postToken({
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': config.clientId,
    });
    return tokens.refreshToken.isEmpty ? tokens.withRefreshToken(refreshToken) : tokens;
  }

  Future<OAuthTokens> _postToken(Map<String, String> form) async {
    final res = await _client.post(
      Uri.parse(tokenEndpoint),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': ?userAgent,
      },
      body: form,
    );
    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw OAuthException('令牌端点返回了无法解析的响应（HTTP ${res.statusCode}）');
    }
    if (res.statusCode != 200) {
      throw OAuthException.fromError(
        json['error']?.toString() ?? 'http_${res.statusCode}',
        json['error_description']?.toString(),
      );
    }
    return OAuthTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
      scope: json['scope'] as String? ?? '',
    );
  }
}

class PkcePair {
  final String verifier;
  final String challenge;
  const PkcePair({required this.verifier, required this.challenge});
}

class OAuthTokens {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String scope;

  const OAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.scope,
  });

  OAuthTokens withRefreshToken(String value) =>
      OAuthTokens(accessToken: accessToken, refreshToken: value, expiresIn: expiresIn, scope: scope);
}

/// OAuth 流程错误（用户拒绝、client_id 无效、回调地址未登记等）。
class OAuthException implements Exception {
  final String message;

  /// 令牌端点返回的 OAuth 错误码（如 `invalid_grant`）；本地错误为 null。
  final String? code;

  const OAuthException(this.message, [this.code]);

  /// refresh_token 已被服务端吊销（在别处退出登录、改密码、令牌轮换后旧值作废），只能重新登录。
  bool get isRevoked => code == 'invalid_grant';

  factory OAuthException.fromError(String error, [String? description]) {
    final text = switch (error) {
      'access_denied' => '你在授权页取消了授权',
      'invalid_client' => 'client_id 无效，请检查开发者后台中的 Client ID',
      'invalid_grant' => '授权已失效，请重新登录',
      'invalid_request' when (description ?? '').contains('redirect') =>
        '回调地址不匹配，请在开发者后台登记 ${OAuthClientConfig.developerRedirectUri}',
      _ => description?.isNotEmpty == true ? '授权失败：$description' : '授权失败（$error）',
    };
    return OAuthException(text, error);
  }

  @override
  String toString() => message;
}
