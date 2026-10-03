import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/providers/auth_provider.dart';
import 'package:flutify_app/services/auth/auth_constants.dart';
import 'package:flutify_app/services/auth/oauth_client_config.dart';
import 'package:flutify_app/services/auth/oauth_loopback_server.dart';
import 'package:flutify_app/services/auth/oauth_pkce_service.dart';
import 'package:flutify_app/services/auth/proto_codec.dart';
import 'package:flutify_app/services/auth/spotify_auth_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Cancellation needs a real listener, but must not contend with the running app.
class _EphemeralOAuthLoopback extends OAuthLoopbackServer {
  @override
  Future<Future<String>> start({
    required String expectedState,
    String path = '/callback',
    int port = OAuthClientConfig.redirectPort,
    Duration timeout = const Duration(minutes: 5),
  }) => super.start(expectedState: expectedState, path: path, port: 0, timeout: timeout);
}

/// 按 client-token / OAuth 线协议模拟服务端，验证唯一的登录方式「在浏览器中登录」（桌面版 OAuth PKCE）：
/// 授权码换令牌、桌面身份 client-token、资料拉取、续期、吊销、回环回调，以及旧版本会话的清理。
void main() {
  late StorageService storage;
  late List<Map<String, String>> tokenRequests;
  late List<http.Request> tokenHttpRequests;
  late List<http.Request> clientTokenRequests;

  /// 为 true 时令牌端点对 refresh_token 续期返回 invalid_grant（模拟凭据被吊销）。
  late bool revokeRefresh;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.init();
    tokenRequests = [];
    tokenHttpRequests = [];
    clientTokenRequests = [];
    revokeRefresh = false;
  });

  /// 把消息按字段号分组，便于断言。
  Map<int, List<ProtoField>> fieldsOf(List<int> bytes) {
    final map = <int, List<ProtoField>>{};
    ProtoReader(Uint8List.fromList(bytes)).forEach((f) => map.putIfAbsent(f.number, () => []).add(f));
    return map;
  }

  Uint8List grantedClientToken() {
    final granted = ProtoWriter()
      ..string(1, 'fake-client-token')
      ..int32(2, 1209600);
    return (ProtoWriter()..message(2, granted)).toBytes();
  }

  MockClient fakeServer() {
    return MockClient((request) async {
      final url = request.url;
      if (url.host == 'clienttoken.spotify.com') {
        clientTokenRequests.add(request);
        return http.Response.bytes(grantedClientToken(), 200);
      }
      if (url.host == 'spclient.wg.spotify.com') {
        // 真实服务端行为：profile/me 是用户名为 "me" 的另一个账号，只有按本人用户名请求才是本人资料
        if (url.path == '/user-profile-view/v3/profile/me') {
          return http.Response(jsonEncode({'name': 'Someone Else', 'image_url': 'https://i.scdn.co/other'}), 200);
        }
        if (url.path == '/user-profile-view/v3/profile/desktop-user') {
          return http.Response(jsonEncode({'name': 'Desktop User', 'image_url': 'https://i.scdn.co/me'}), 200);
        }
        return http.Response('', 200); // /api/logout/v1
      }
      if (url.host == 'accounts.spotify.com') {
        tokenHttpRequests.add(request);
        tokenRequests.add(Uri.splitQueryString(request.body));
        if (revokeRefresh && tokenRequests.last['grant_type'] == 'refresh_token') {
          return http.Response(
            jsonEncode({'error': 'invalid_grant', 'error_description': 'Refresh token revoked'}),
            400,
          );
        }
        return http.Response(
          jsonEncode({'access_token': 'oauth-access', 'refresh_token': 'oauth-refresh', 'expires_in': 3600}),
          200,
        );
      }
      return http.Response('not found', 404);
    });
  }

  SpotifyAuthService desktopAuth() => SpotifyAuthService(storage, fakeServer(), null, (_, _) async => 'desktop-user');

  group('OAuth PKCE', () {
    test('code_challenge 符合 RFC 7636 附录 B 测试向量', () {
      expect(
        OAuthPkceService.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
      final pair = OAuthPkceService.generatePkce();
      expect(pair.verifier.length, 64);
      expect(pair.challenge, OAuthPkceService.challengeFor(pair.verifier));
    });

    test('授权页：官方桌面 client_id、PKCE 参数、/login 回调与完整权限', () {
      final url = OAuthPkceService.buildAuthorizeUrl(
        config: const OAuthClientConfig.desktop(),
        codeChallenge: 'chal',
        state: 'st',
      );
      expect(url.queryParameters['client_id'], SpotifyAuthConstants.desktopClientId);
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['code_challenge'], 'chal');
      expect(url.queryParameters['redirect_uri'], 'http://127.0.0.1:8898/login');
      expect(url.queryParameters['scope'], allOf(contains('streaming'), contains('user-modify')));
    });

    test('授权码换令牌 → 桌面身份 client-token → 按用户名拉资料 → refresh_token 续期', () async {
      final resolverTokens = <String>[];
      final auth = SpotifyAuthService(storage, fakeServer(), null, (token, _) async {
        resolverTokens.add(token);
        return 'desktop-user';
      });

      await auth.completeOAuth(code: 'auth-code', codeVerifier: 'verifier');
      expect(tokenRequests.single['grant_type'], 'authorization_code');
      expect(tokenRequests.single['code_verifier'], 'verifier');
      expect(tokenRequests.single['client_id'], SpotifyAuthConstants.desktopClientId);
      expect(tokenRequests.single['redirect_uri'], 'http://127.0.0.1:8898/login');
      expect(tokenHttpRequests.single.headers['User-Agent'], SpotifyAuthConstants.desktopUserAgent);

      // 令牌响应不含用户名：用令牌向 AP 查询 canonical username（媒体库按它寻址）
      expect(resolverTokens, ['oauth-access']);
      expect(auth.username, 'desktop-user');
      expect(auth.isLoggedIn, isTrue);

      // client-token：ClientDataRequest 中 client_id 为桌面版，平台数据为 desktop_windows(4)
      final clientData = fieldsOf(fieldsOf(clientTokenRequests.single.bodyBytes)[2]!.first.bytesValue);
      expect(clientData[1]!.first.asString, SpotifyAuthConstants.desktopVersion);
      expect(clientData[2]!.first.asString, SpotifyAuthConstants.desktopClientId);
      final platform = fieldsOf(fieldsOf(clientData[3]!.first.bytesValue)[1]!.first.bytesValue);
      expect(platform.keys, [4]);
      expect(clientTokenRequests.single.headers['User-Agent'], SpotifyAuthConstants.desktopUserAgent);
      expect(storage.clientTokenProfile, 'desktop');

      expect(auth.displayName, 'Desktop User', reason: '资料来自内部 profile-view/{用户名}，不能用 profile/me');
      expect(auth.avatarUrl, 'https://i.scdn.co/me');
      expect(auth.clientHeaders['app-platform'], SpotifyAuthConstants.desktopPlatform);
      expect(auth.clientHeaders['user-agent'], SpotifyAuthConstants.desktopUserAgent);

      await storage.setAccessTokenExpiry(0);
      final tokens = await Future.wait([auth.ensureAccessToken(), auth.ensureAccessToken()]);
      expect(tokens, everyElement('oauth-access'));
      expect(tokenRequests.where((r) => r['grant_type'] == 'refresh_token'), hasLength(1), reason: '并发续期只请求一次');
      expect(tokenRequests.last['refresh_token'], 'oauth-refresh');
      expect(tokenRequests.last['client_id'], SpotifyAuthConstants.desktopClientId);

      await auth.logout();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.clientHeaders, isEmpty);
    });

    test('refresh_token 被吊销时标记登录过期，不再重复请求令牌端点，登出后清除', () async {
      final auth = desktopAuth();
      await auth.completeOAuth(code: 'c', codeVerifier: 'v');

      revokeRefresh = true;
      await storage.setAccessTokenExpiry(0);
      await expectLater(auth.ensureAccessToken(), throwsA(isA<OAuthException>()));
      expect(auth.sessionExpired.value, isTrue);
      await expectLater(auth.ensureAccessToken(), throwsA(isA<OAuthException>()));
      expect(tokenRequests.where((r) => r['grant_type'] == 'refresh_token'), hasLength(1), reason: '已知失效后不再打令牌端点');

      await auth.logout();
      expect(auth.sessionExpired.value, isFalse);
      expect(auth.isLoggedIn, isFalse);
    });

    test('回环服务：state 匹配时返回授权码；不匹配或用户拒绝时报错', () async {
      final server = OAuthLoopbackServer();
      final client = HttpClient();
      Future<void> hit(String query) async {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:18898/callback?$query'));
        await (await req.close()).drain<void>();
      }

      final code = await server.start(expectedState: 'good', port: 18898);
      await hit('code=abc&state=good');
      expect(await code, 'abc');

      final mismatch = await server.start(expectedState: 'good', port: 18898);
      final expectation = expectLater(mismatch, throwsA(isA<OAuthException>()));
      await hit('code=abc&state=evil');
      await expectation;

      final denied = await server.start(expectedState: 'good', port: 18898);
      final deniedExpectation = expectLater(
        denied,
        throwsA(predicate((e) => e is OAuthException && e.message.contains('取消'))),
      );
      await hit('error=access_denied&state=good');
      await deniedExpectation;
      client.close();
    });
  });

  group('旧版本会话', () {
    test('Login5 / 开发者应用登录的会话视为未登录，并清除残留凭据', () async {
      SharedPreferences.setMockInitialValues({
        'sp_auth_method': 'login5',
        'sp_access_token': 'old-access',
        'sp_refresh_token': 'old-refresh',
        'sp_stored_credential': 'blob',
        'sp_client_id': '0123456789abcdef0123456789abcdef',
      });
      final legacy = await StorageService.init();
      expect(legacy.isLoggedIn, isFalse);
      expect(legacy.accessToken, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('sp_stored_credential'), isFalse);
      expect(prefs.containsKey('sp_client_id'), isFalse);
    });

    test('桌面版会话原样保留', () async {
      SharedPreferences.setMockInitialValues({
        'sp_auth_method': 'desktop',
        'sp_access_token': 'desktop-access',
        'sp_refresh_token': 'desktop-refresh',
        'sp_client_id': '0123456789abcdef0123456789abcdef',
      });
      final restored = await StorageService.init();
      expect(restored.isLoggedIn, isTrue);
      expect(restored.refreshToken, 'desktop-refresh');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('sp_client_id'), isFalse, reason: '开发者 Client ID 已无用处');
    });
  });

  group('AuthProvider', () {
    test('旧版桌面会话缺用户名：启动时补齐用户名、改正昵称并重新加载媒体库', () async {
      // 旧版本登录后只按 profile/me 存了别人的昵称，用户名为空
      await storage.markDesktopSession();
      await storage.setAccessToken('oauth-access');
      await storage.setAccessTokenExpiry(DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);
      await storage.setRefreshToken('oauth-refresh');
      await storage.setDisplayName('Someone Else');
      expect(storage.isLoggedIn, isTrue);

      final provider = AuthProvider(desktopAuth());
      final reloaded = Completer<void>();
      provider.onSessionChanged = reloaded.complete;
      await reloaded.future.timeout(const Duration(seconds: 5));

      expect(provider.username, 'desktop-user');
      expect(provider.displayName, 'Desktop User');
    });

    test('浏览器授权：进入等待态 → 取消回到未登录；登出回调会话变化', () async {
      final provider = AuthProvider(SpotifyAuthService(
        storage, fakeServer(), _EphemeralOAuthLoopback(), (_, _) async => 'desktop-user',
      ));
      addTearDown(provider.dispose);
      addTearDown(provider.cancelOAuth);
      var sessionChanges = 0;
      provider.onSessionChanged = () => sessionChanges++;

      final url = await provider.beginOAuth();
      expect(url, isNotNull, reason: provider.error);
      expect(provider.status, AuthStatus.authorizing);
      expect(provider.authorizeUrl, url);
      expect(await provider.beginOAuth(), isNull, reason: '等待中不重复发起');

      await provider.cancelOAuth();
      expect(provider.status, AuthStatus.signedOut);
      expect(provider.error, isNull, reason: '主动取消不显示错误');

      await provider.signOut();
      expect(sessionChanges, 1);
    });

    test('错误翻译', () {
      expect(AuthProvider.describeError(const SocketException('x')), contains('网络'));
      expect(AuthProvider.describeError(const OAuthException('登录已过期，请重新登录', 'invalid_grant')), contains('过期'));
    });
  });
}
