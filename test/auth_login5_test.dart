import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutify_app/providers/auth_provider.dart';
import 'package:flutify_app/services/auth/account_profile_service.dart';
import 'package:flutify_app/services/auth/auth_constants.dart';
import 'package:flutify_app/services/auth/credential_parsers.dart';
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

/// 按 Login5 / client-token / OAuth 线协议模拟服务端，验证全部登录方式：
/// 密码（Hashcash + 短信）、手机号、一次性令牌、导入凭据、StoredCredential 续期、OAuth PKCE。
void main() {
  final hashPrefix = Uint8List.fromList(List.generate(16, (i) => i * 7));
  final ctx1 = utf8.encode('ctx-round-1');
  final ctx2 = utf8.encode('ctx-round-2');
  final storedBlob = utf8.encode('stored-credential-blob');

  late StorageService storage;
  late List<Map<int, List<ProtoField>>> login5Requests;
  late List<Map<String, String>> tokenRequests;
  late List<http.Request> tokenHttpRequests;
  late List<http.Request> clientTokenRequests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.init();
    login5Requests = [];
    tokenRequests = [];
    tokenHttpRequests = [];
    clientTokenRequests = [];
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

  Uint8List challengeResponse(ProtoWriter challenge, List<int> ctx) {
    final challenges = ProtoWriter()..message(1, challenge);
    return (ProtoWriter()
          ..message(3, challenges)
          ..bytes(5, ctx))
        .toBytes();
  }

  Uint8List codeChallenge(List<int> ctx) {
    final code = ProtoWriter()
      ..int32(2, 6)
      ..string(4, '+86 ••• 1234');
    return challengeResponse(ProtoWriter()..message(2, code), ctx);
  }

  Uint8List okResponse({bool withStored = true}) {
    final ok = ProtoWriter()
      ..string(1, 'tester')
      ..string(2, 'fake-access-token')
      ..int32(4, 3600);
    if (withStored) ok.bytes(3, storedBlob);
    return (ProtoWriter()..message(1, ok)).toBytes();
  }

  /// 校验客户端给出的 hashcash suffix 确实满足难度。
  bool suffixSolves(List<int> suffix, int length) {
    final sum = sha1.convert([...hashPrefix, ...suffix]).bytes;
    var x = ByteData.sublistView(Uint8List.fromList(sum), 12, 20).getUint64(0);
    var zeros = 0;
    while (zeros < 64 && (x & 1) == 0) {
      zeros++;
      x >>= 1;
    }
    return zeros >= length;
  }

  /// 身份服务返回的 Identity$UserProfile。
  Uint8List identityProfile() {
    final image = ProtoWriter()
      ..int32(1, 300)
      ..string(3, 'https://i.scdn.co/image/avatar');
    return (ProtoWriter()
          ..message(1, ProtoWriter()..string(1, 'tester'))
          ..message(2, ProtoWriter()..string(1, 'Test User'))
          ..message(3, image))
        .toBytes();
  }

  /// 模拟服务端：
  /// - 密码：第 1 轮 hashcash → 第 2 轮短信 → 带验证码成功；
  /// - 手机号：直接短信 → 带验证码成功；一次性令牌 / 凭据：直接成功（令牌为 bad 时返回错误）。
  MockClient fakeServer() {
    return MockClient((request) async {
      final url = request.url;
      if (url.host == 'clienttoken.spotify.com') {
        clientTokenRequests.add(request);
        return http.Response.bytes(grantedClientToken(), 200);
      }
      if (url.host == 'spclient.wg.spotify.com') {
        if (url.path.startsWith('/identity/v3/user/username/')) {
          return http.Response.bytes(identityProfile(), 200);
        }
        if (url.path == '/user-profile-view/v3/profile/me') {
          return http.Response(jsonEncode({'name': 'Desktop User', 'image_url': 'https://i.scdn.co/me'}), 200);
        }
        return http.Response('', 200); // /api/logout/v1
      }
      if (url.host == 'accounts.spotify.com') {
        tokenHttpRequests.add(request);
        tokenRequests.add(Uri.splitQueryString(request.body));
        return http.Response(
          jsonEncode({'access_token': 'oauth-access', 'refresh_token': 'oauth-refresh', 'expires_in': 3600}),
          200,
        );
      }
      if (url.host == 'api.spotify.com') {
        return http.Response(
          jsonEncode({
            'id': 'oauth-user',
            'display_name': 'OAuth User',
            'images': [
              {'url': 'https://i.scdn.co/small', 'width': 64},
              {'url': 'https://i.scdn.co/large', 'width': 640},
            ],
          }),
          200,
        );
      }

      expect(request.headers['client-token'], 'fake-client-token');
      final fields = fieldsOf(request.bodyBytes);
      login5Requests.add(fields);
      final ctx = fields[2]?.first.bytesValue;

      if (fields.containsKey(100)) return http.Response.bytes(okResponse(withStored: false), 200);
      if (fields.containsKey(104)) {
        final token = fieldsOf(fields[104]!.first.bytesValue)[1]!.first.asString;
        if (token == 'bad') return http.Response.bytes((ProtoWriter()..enumValue(2, 1)).toBytes(), 200);
        return http.Response.bytes(okResponse(), 200);
      }
      if (fields.containsKey(103)) {
        return http.Response.bytes(ctx == null ? codeChallenge(ctx2) : okResponse(), 200);
      }

      if (ctx == null) {
        final hashcash = ProtoWriter()
          ..bytes(1, hashPrefix)
          ..int32(2, 6);
        return http.Response.bytes(challengeResponse(ProtoWriter()..message(1, hashcash), ctx1), 200);
      }
      if (utf8.decode(ctx) == 'ctx-round-1') return http.Response.bytes(codeChallenge(ctx2), 200);
      return http.Response.bytes(okResponse(), 200);
    });
  }

  group('Login5', () {
    test('密码 → Hashcash → 短信验证码 → 成功，并持久化凭据与资料', () async {
      final auth = SpotifyAuthService(storage, fakeServer());

      final pending = await auth.login('tester', 'secret');
      expect(pending, isNotNull);
      expect(pending!.codeLength, 6);
      expect(pending.canonicalPhoneNumber, '+86 ••• 1234');
      expect(auth.isLoggedIn, isFalse);

      // 第 2 轮请求：带第 1 轮 login_context 与一个有效的 hashcash 解
      final round2 = login5Requests[1];
      expect(round2[2]!.first.bytesValue, ctx1);
      final solutions = fieldsOf(round2[3]!.first.bytesValue)[1]!;
      expect(solutions, hasLength(1));
      final hashcashSolution = fieldsOf(fieldsOf(solutions.first.bytesValue)[1]!.first.bytesValue);
      expect(suffixSolves(hashcashSolution[1]!.first.bytesValue, 6), isTrue);

      expect(await auth.submitCode('123456'), isNull);

      // 第 3 轮请求：换成新 login_context，只携带验证码解（旧 hashcash 解作废）
      final round3 = login5Requests[2];
      expect(round3[2]!.first.bytesValue, ctx2);
      final codeSolutions = fieldsOf(round3[3]!.first.bytesValue)[1]!;
      expect(codeSolutions, hasLength(1));
      final codeSolution = fieldsOf(fieldsOf(codeSolutions.first.bytesValue)[2]!.first.bytesValue);
      expect(codeSolution[1]!.first.asString, '123456');

      expect(auth.isLoggedIn, isTrue);
      expect(storage.authMethod, AuthMethod.login5);
      expect(storage.username, 'tester');
      expect(storage.accessToken, 'fake-access-token');
      expect(base64Decode(storage.storedCredential), storedBlob);
      expect(auth.displayName, 'Test User');
      expect(auth.avatarUrl, 'https://i.scdn.co/image/avatar');
    });

    test('手机号登录：PhoneNumber(103) → 短信；重新发送会以同一凭据重开会话', () async {
      final auth = SpotifyAuthService(storage, fakeServer());

      final pending = await auth.loginWithPhone(number: '138 0000 0000', isoCountryCode: 'CN', callingCode: '86');
      expect(pending, isNotNull);
      final phone = fieldsOf(login5Requests.single[103]!.first.bytesValue);
      expect(phone[1]!.first.asString, '13800000000');
      expect(phone[2]!.first.asString, 'CN');
      expect(phone[3]!.first.asString, '86');

      expect(await auth.resendCode(), isNotNull);
      expect(login5Requests, hasLength(2));
      expect(login5Requests[1].containsKey(2), isFalse, reason: '重新发送应是全新会话，不带旧 login_context');
      expect(login5Requests[1].containsKey(103), isTrue);

      expect(await auth.submitCode('654321'), isNull);
      expect(auth.isLoggedIn, isTrue);
    });

    test('一次性令牌：从登录链接提取 token 并以 OneTimeToken(104) 登录', () async {
      final auth = SpotifyAuthService(storage, fakeServer());

      expect(await auth.loginWithOneTimeToken('https://accounts.spotify.com/login/ott/v2?token=abc123'), isNull);
      final ott = fieldsOf(login5Requests.single[104]!.first.bytesValue);
      expect(ott[1]!.first.asString, 'abc123');
      expect(auth.isLoggedIn, isTrue);

      await auth.logout();
      await expectLater(auth.loginWithOneTimeToken('bad'), throwsA(isA<Login5Failure>()));
    });

    test('导入凭据：替换设备 ID 并验证；失败时恢复原设备 ID', () async {
      await storage.setDeviceId('original-device-id-0000');
      final auth = SpotifyAuthService(storage, fakeServer());

      final credential = CredentialParsers.parseCredentialsJson(jsonEncode({
        'username': 'tester',
        'auth_type': 1,
        'auth_data': base64Encode(storedBlob),
        'device_id': 'imported-device-id-1111',
      }));
      await auth.importStoredCredential(credential);

      final stored = fieldsOf(login5Requests.single[100]!.first.bytesValue);
      expect(stored[2]!.first.bytesValue, storedBlob);
      final clientInfo = fieldsOf(login5Requests.single[1]!.first.bytesValue);
      expect(clientInfo[2]!.first.asString, 'imported-device-id-1111');
      expect(storage.deviceId, 'imported-device-id-1111');
      // 续期响应不含 stored_credential 时保存导入的凭据
      expect(base64Decode(storage.storedCredential), storedBlob);
      expect(auth.isLoggedIn, isTrue);

      // 验证失败：设备 ID 回滚
      final failing = SpotifyAuthService(
        storage,
        MockClient((request) async => request.url.host == 'clienttoken.spotify.com'
            ? http.Response.bytes(grantedClientToken(), 200)
            : http.Response.bytes((ProtoWriter()..enumValue(2, 1)).toBytes(), 200)),
      );
      final other = CredentialParsers.build(
        username: 'someone',
        blobBase64: base64Encode(storedBlob),
        deviceId: 'another-device-id-2222',
      );
      await expectLater(failing.importStoredCredential(other), throwsA(isA<Login5Failure>()));
      expect(storage.deviceId, 'imported-device-id-1111');
    });

    test('access_token 过期后用 StoredCredential 免密续期，并发调用只请求一次', () async {
      final auth = SpotifyAuthService(storage, fakeServer());
      await auth.login('tester', 'secret');
      await auth.submitCode('123456');
      await storage.setAccessToken('expired');
      await storage.setAccessTokenExpiry(0);
      login5Requests.clear();

      final tokens = await Future.wait([auth.ensureAccessToken(), auth.ensureAccessToken()]);
      expect(tokens, everyElement('fake-access-token'));
      expect(login5Requests, hasLength(1));

      final stored = fieldsOf(login5Requests.single[100]!.first.bytesValue);
      expect(stored[1]!.first.asString, 'tester');
      expect(stored[2]!.first.bytesValue, storedBlob);
      expect(base64Decode(storage.storedCredential), storedBlob);
    });
  });

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

    test('开发者应用：授权码换令牌 → 拉取 /v1/me → refresh_token 续期', () async {
      final auth = SpotifyAuthService(storage, fakeServer());
      const clientId = '0123456789abcdef0123456789abcdef';

      await auth.completeOAuth(
        config: const OAuthClientConfig.developer(clientId),
        code: 'auth-code',
        codeVerifier: 'verifier',
      );
      expect(tokenRequests.single['grant_type'], 'authorization_code');
      expect(tokenRequests.single['code_verifier'], 'verifier');
      expect(tokenRequests.single['redirect_uri'], OAuthClientConfig.developerRedirectUri);

      expect(auth.isLoggedIn, isTrue);
      expect(storage.authMethod, AuthMethod.oauth);
      expect(auth.clientHeaders, isEmpty, reason: '开发者应用不冒充官方客户端');
      expect(clientTokenRequests, isEmpty);
      expect(storage.username, 'oauth-user');
      expect(auth.displayName, 'OAuth User');
      expect(auth.avatarUrl, 'https://i.scdn.co/large');

      await storage.setAccessTokenExpiry(0);
      expect(await auth.ensureAccessToken(), 'oauth-access');
      expect(tokenRequests.last['grant_type'], 'refresh_token');
      expect(tokenRequests.last['refresh_token'], 'oauth-refresh');

      await auth.logout();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.savedOAuthClientId, clientId, reason: '登出后保留 client_id 便于再次授权');
    });

    test('授权页地址包含 PKCE 参数与固定回调', () {
      final url = OAuthPkceService.buildAuthorizeUrl(
        config: const OAuthClientConfig.developer('cid'),
        codeChallenge: 'chal',
        state: 'st',
      );
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['code_challenge'], 'chal');
      expect(url.queryParameters['redirect_uri'], OAuthClientConfig.developerRedirectUri);
      expect(url.queryParameters['scope'], contains('streaming'));
    });

    test('桌面版授权页：官方桌面 client_id、/login 回调与完整权限', () {
      final url = OAuthPkceService.buildAuthorizeUrl(
        config: const OAuthClientConfig.desktop(),
        codeChallenge: 'chal',
        state: 'st',
      );
      expect(url.queryParameters['client_id'], SpotifyAuthConstants.desktopClientId);
      expect(url.queryParameters['redirect_uri'], 'http://127.0.0.1:8898/login');
      expect(url.queryParameters['scope'], allOf(contains('user-modify'), contains('user-personalized')));
    });

    test('桌面版：以桌面身份申请 client-token，请求头一致，refresh_token 续期', () async {
      await storage.setClientId('0123456789abcdef0123456789abcdef');
      final auth = SpotifyAuthService(storage, fakeServer());

      await auth.completeOAuth(config: const OAuthClientConfig.desktop(), code: 'c', codeVerifier: 'v');
      expect(tokenRequests.single['client_id'], SpotifyAuthConstants.desktopClientId);
      expect(tokenRequests.single['redirect_uri'], 'http://127.0.0.1:8898/login');
      expect(tokenHttpRequests.single.headers['User-Agent'], SpotifyAuthConstants.desktopUserAgent);

      expect(auth.isLoggedIn, isTrue);
      expect(storage.authMethod, AuthMethod.desktop);
      expect(auth.savedOAuthClientId, '0123456789abcdef0123456789abcdef', reason: '不覆盖开发者 Client ID');

      // client-token：ClientDataRequest 中 client_id 为桌面版，平台数据为 desktop_windows(4)
      final clientData = fieldsOf(fieldsOf(clientTokenRequests.single.bodyBytes)[2]!.first.bytesValue);
      expect(clientData[1]!.first.asString, SpotifyAuthConstants.desktopVersion);
      expect(clientData[2]!.first.asString, SpotifyAuthConstants.desktopClientId);
      final platform = fieldsOf(fieldsOf(clientData[3]!.first.bytesValue)[1]!.first.bytesValue);
      expect(platform.keys, [4]);
      expect(clientTokenRequests.single.headers['User-Agent'], SpotifyAuthConstants.desktopUserAgent);
      expect(storage.clientTokenProfile, 'desktop');

      expect(auth.displayName, 'Desktop User', reason: '桌面版资料来自内部 profile-view 接口');
      expect(auth.clientHeaders['app-platform'], SpotifyAuthConstants.desktopPlatform);
      expect(auth.clientHeaders['user-agent'], SpotifyAuthConstants.desktopUserAgent);

      await storage.setAccessTokenExpiry(0);
      expect(await auth.ensureAccessToken(), 'oauth-access');
      expect(tokenRequests.last['grant_type'], 'refresh_token');
      expect(tokenRequests.last['client_id'], SpotifyAuthConstants.desktopClientId);

      // 登出后改用 Login5：以 Android 身份重新申请 client-token
      await auth.logout();
      await auth.loginWithOneTimeToken('abc');
      expect(clientTokenRequests, hasLength(2));
      final androidData = fieldsOf(fieldsOf(clientTokenRequests.last.bodyBytes)[2]!.first.bytesValue);
      expect(androidData[2]!.first.asString, SpotifyAuthConstants.androidClientId);
      expect(storage.clientTokenProfile, 'android');
    });

    test('回环服务：state 匹配时返回授权码；不匹配时报错', () async {
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

  group('解析', () {
    test('Identity\$UserProfile 取昵称与最大头像', () {
      final profile = AccountProfileService.parseIdentityProfile(identityProfile())!;
      expect(profile.displayName, 'Test User');
      expect(profile.avatarUrl, 'https://i.scdn.co/image/avatar');
    });

    test('一次性令牌提取', () {
      expect(CredentialParsers.extractOneTimeToken('https://x.spotify.com/a?ott=t1'), 't1');
      expect(CredentialParsers.extractOneTimeToken('https://x.spotify.com/a#token=t2'), 't2');
      expect(CredentialParsers.extractOneTimeToken('  rawToken  '), 'rawToken');
      expect(CredentialParsers.extractOneTimeToken('https://x.spotify.com/a?foo=1'), '');
      expect(CredentialParsers.extractOneTimeToken('two words'), '');
    });

    test('credentials.json 校验', () {
      final ok = CredentialParsers.parseCredentialsJson(
        '{"username":"u","auth_type":1,"auth_data":"${base64Url.encode(storedBlob).replaceAll('=', '')}"}',
      );
      expect(ok.blob, storedBlob, reason: '兼容 URL 安全且无填充的 Base64');
      expect(
        () => CredentialParsers.parseCredentialsJson('{"username":"u","auth_type":0,"auth_data":"YQ=="}'),
        throwsFormatException,
      );
      expect(() => CredentialParsers.parseCredentialsJson('not json'), throwsFormatException);
      expect(() => CredentialParsers.build(username: '', blobBase64: 'YQ=='), throwsFormatException);
    });
  });

  group('AuthProvider', () {
    test('验证码流转、重新发送冷却与登出', () async {
      final provider = AuthProvider(SpotifyAuthService(storage, fakeServer()));
      var sessionChanges = 0;
      provider.onSessionChanged = () => sessionChanges++;

      expect(await provider.signIn('tester', 'secret'), isFalse);
      expect(provider.status, AuthStatus.awaitingCode);
      expect(provider.canResendCode, isFalse, reason: '刚发送的验证码处于冷却期');

      expect(await provider.submitCode('123456'), isTrue);
      expect(provider.status, AuthStatus.signedIn);
      expect(sessionChanges, 1);

      await provider.signOut();
      expect(provider.status, AuthStatus.signedOut);
      expect(storage.isLoggedIn, isFalse);
      expect(sessionChanges, 2);
    });

    test('错误翻译与输入校验', () async {
      final server = MockClient((request) async => request.url.host == 'clienttoken.spotify.com'
          ? http.Response.bytes(grantedClientToken(), 200)
          : http.Response.bytes((ProtoWriter()..enumValue(2, 1)).toBytes(), 200));
      final provider = AuthProvider(SpotifyAuthService(storage, server));

      expect(await provider.signIn('tester', 'wrong'), isFalse);
      expect(provider.status, AuthStatus.signedOut);
      expect(provider.error, startsWith('账号或密码错误'));
      expect(provider.error, contains('在浏览器中登录'));

      expect(await provider.signInWithOneTimeToken('https://a.com/?x=1'), isFalse);
      expect(provider.error, contains('一次性令牌'));

      expect(await provider.importCredential(json: '{"username":"u","auth_type":0}'), isFalse);
      expect(provider.error, contains('auth_type'));

      expect(await provider.beginOAuth('not-a-client-id'), isNull);
      expect(provider.error, contains('Client ID'));

      expect(AuthProvider.describeError(const Login5UnsupportedChallenge()), contains('人机验证'));
    });
  });
}
