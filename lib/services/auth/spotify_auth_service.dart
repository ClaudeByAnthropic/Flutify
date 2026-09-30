import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/constants/spotify_endpoints.dart';
import '../storage_service.dart';
import 'account_profile_service.dart';
import 'auth_constants.dart';
import 'client_profile.dart';
import 'client_token_service.dart';
import 'credential_parsers.dart';
import 'login5_service.dart';
import 'oauth_client_config.dart';
import 'oauth_loopback_server.dart';
import 'oauth_pkce_service.dart';

/// Spotify 身份鉴权总控。
///
/// 三条登录链路（对应 SpotifyApi 文档 01-认证与账号 / 桌面端 05-登录与凭据）：
/// - **桌面版 OAuth**（默认，风控风险最低）：与官方桌面版相同，在系统浏览器的 accounts.spotify.com
///   完成登录 → 本机回环接收授权码 → PKCE 换取令牌；App 不接触密码，人机验证 / 两步验证由官方页面处理；
///   会话以 Windows 桌面端身份申请 client-token；过期后用 refresh_token 续期。
/// - **Login5**（Android 身份）：密码、手机号短信、一次性令牌、导入可复用凭据；
///   自动处理 client-token、Hashcash 与短信验证码挑战；过期后用 StoredCredential 免密续期。
/// - **开发者应用 OAuth**：用户自己的 client_id，只能访问公开 Web API。
///
/// 说明：以官方客户端身份登录违反 Spotify 服务条款，存在账号风控风险，建议用小号测试。
class SpotifyAuthService {
  /// 令牌提前续期的余量：剩余有效期不足该值即视为过期。
  static const int _refreshMarginMs = 60 * 1000;

  final StorageService _storage;
  final http.Client _client;
  final ClientTokenService _clientTokenService;
  final Login5Service _login5;
  final OAuthPkceService _oauth;
  final OAuthPkceService _desktopOAuth;
  final AccountProfileService _profiles;
  final OAuthLoopbackServer _loopback;

  /// 等待验证码的登录会话（密码 / 手机号登录触发短信挑战后保留）。
  Login5Session? _pendingSession;

  /// 正在进行中的续期请求：并发调用复用同一个 Future，避免重复打令牌端点。
  Future<String>? _refreshInFlight;
  Future<String>? _clientTokenInFlight;

  SpotifyAuthService._(this._storage, this._client, this._loopback)
      : _clientTokenService = ClientTokenService(_client),
        _login5 = Login5Service(_client),
        _oauth = OAuthPkceService(_client),
        _desktopOAuth = OAuthPkceService(_client, userAgent: SpotifyClientProfile.desktop.userAgent),
        _profiles = AccountProfileService(_client);

  factory SpotifyAuthService(StorageService storage, [http.Client? client, OAuthLoopbackServer? loopback]) =>
      SpotifyAuthService._(storage, client ?? http.Client(), loopback ?? OAuthLoopbackServer());

  bool get isLoggedIn => _storage.isLoggedIn;
  AuthMethod get method => _storage.authMethod;
  String get username => _storage.username;
  String get displayName => _storage.displayName.isNotEmpty ? _storage.displayName : _storage.username;
  String get avatarUrl => _storage.avatarUrl;
  bool get hasPendingCode => _pendingSession != null;

  /// 上次使用的 OAuth client_id（登出后保留，便于再次授权）。
  String get savedOAuthClientId => _storage.clientId;

  /// 当前会话的客户端身份；开发者应用 OAuth 不冒充官方客户端，返回 null。
  SpotifyClientProfile? get clientProfile => switch (_storage.authMethod) {
        AuthMethod.login5 => SpotifyClientProfile.android,
        AuthMethod.desktop => SpotifyClientProfile.desktop,
        AuthMethod.oauth => null,
      };

  /// 业务请求应附带的客户端头（User-Agent / app-platform / spotify-app-version），与令牌所属客户端一致。
  Map<String, String> get clientHeaders {
    final profile = clientProfile;
    if (!isLoggedIn || profile == null) return const {};
    return {'user-agent': profile.userAgent, ...profile.headers};
  }

  /// access_token 到期时间；未登录返回 null。
  DateTime? get accessTokenExpiry {
    final ms = _storage.accessTokenExpiry;
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 设备 ID：首次调用时生成并持久化（StoredCredential 与其绑定，不可随意更换）。
  Future<String> _deviceId() async {
    var id = _storage.deviceId;
    if (id.isEmpty) {
      id = SpotifyAuthConstants.generateDeviceId();
      await _storage.setDeviceId(id);
    }
    return id;
  }

  static bool _isFresh(int expiryMs) => expiryMs > DateTime.now().millisecondsSinceEpoch + _refreshMarginMs;

  // ---------------------------------------------------------------------------
  // client-token
  // ---------------------------------------------------------------------------

  /// 获取 [profile]（缺省为当前会话身份）的有效 client-token；过期、缺失或身份不一致则重新申请。
  Future<String> ensureClientToken([SpotifyClientProfile? profile]) {
    final target = profile ?? clientProfile ?? SpotifyClientProfile.android;
    if (_storage.clientToken.isNotEmpty &&
        _storage.clientTokenProfile == target.name &&
        _isFresh(_storage.clientTokenExpiry)) {
      return Future.value(_storage.clientToken);
    }
    return _clientTokenInFlight ??= _requestClientToken(target).whenComplete(() {
      _clientTokenInFlight = null;
    });
  }

  Future<String> _requestClientToken(SpotifyClientProfile profile) async {
    final granted = await _clientTokenService.request(await _deviceId(), profile);
    await _storage.setClientToken(granted.token);
    await _storage.setClientTokenExpiry(granted.expiryEpochMs(DateTime.now()));
    await _storage.setClientTokenProfile(profile.name);
    return granted.token;
  }

  /// Login5 各方式均以 Android 身份发起。
  Future<String> _androidClientToken() => ensureClientToken(SpotifyClientProfile.android);

  // ---------------------------------------------------------------------------
  // Login5 交互式登录
  //
  // 返回 null 表示登录成功（凭据已持久化、App 已切到真实数据）；
  // 返回 [PendingCodeChallenge] 表示短信已下发，需调用 [submitCode] 续接。
  // 失败抛 [Login5Failure] / [Login5UnsupportedChallenge] 或网络异常。
  // ---------------------------------------------------------------------------

  /// 账号密码登录。
  Future<PendingCodeChallenge?> login(String username, String password) async {
    _pendingSession = null;
    final result = await _login5.loginWithPassword(
      clientToken: await _androidClientToken(),
      deviceId: await _deviceId(),
      username: username.trim(),
      password: password,
    );
    return _handle(result);
  }

  /// 手机号登录（必然触发短信验证码）。
  Future<PendingCodeChallenge?> loginWithPhone({
    required String number,
    required String isoCountryCode,
    required String callingCode,
  }) async {
    _pendingSession = null;
    final result = await _login5.loginWithPhoneNumber(
      clientToken: await _androidClientToken(),
      deviceId: await _deviceId(),
      number: number.replaceAll(RegExp(r'[^0-9]'), ''),
      isoCountryCode: isoCountryCode,
      callingCode: callingCode,
    );
    return _handle(result);
  }

  /// 一次性令牌登录；[input] 可以是登录链接或令牌本身。
  Future<PendingCodeChallenge?> loginWithOneTimeToken(String input) async {
    final token = CredentialParsers.extractOneTimeToken(input);
    if (token.isEmpty) throw StateError('没有在内容中找到一次性令牌');
    _pendingSession = null;
    final result = await _login5.loginWithOneTimeToken(
      clientToken: await _androidClientToken(),
      deviceId: await _deviceId(),
      token: token,
    );
    return _handle(result);
  }

  /// 提交短信验证码续接登录；验证码错误时服务端可能再次下发挑战，同样返回 [PendingCodeChallenge]。
  Future<PendingCodeChallenge?> submitCode(String code) async {
    final session = _pendingSession;
    if (session == null) throw StateError('没有待验证的登录会话');
    return _handle(await _login5.continueWithCode(session, code));
  }

  /// 用同一凭据重新发起登录，让服务端重新发送短信验证码。
  Future<PendingCodeChallenge?> resendCode() async {
    final session = _pendingSession;
    if (session == null) throw StateError('没有待验证的登录会话');
    return _handle(await _login5.restart(session));
  }

  /// 放弃等待验证码。
  void cancelPendingCode() => _pendingSession = null;

  Future<PendingCodeChallenge?> _handle(Login5Result result) async {
    switch (result) {
      case Login5Success(:final ok):
        _pendingSession = null;
        await _persistLogin5(ok);
        await _loadProfile();
        return null;
      case Login5CodeRequired():
        _pendingSession = result.session;
        return PendingCodeChallenge(
          codeLength: result.codeLength,
          canonicalPhoneNumber: result.canonicalPhoneNumber,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // 导入可复用凭据（桌面版 / librespot 保存的 StoredCredential）
  // ---------------------------------------------------------------------------

  /// 导入凭据并立即用 Login5 验证；验证失败时恢复原设备 ID 并抛出异常。
  Future<void> importStoredCredential(ImportedCredential credential) async {
    final previousDeviceId = _storage.deviceId;
    final switchingDevice = credential.deviceId != null && credential.deviceId != previousDeviceId;
    if (switchingDevice) {
      // client-token 与设备绑定，换设备 ID 后需重新申请
      await _storage.setDeviceId(credential.deviceId!);
      await _storage.setClientToken('');
      await _storage.setClientTokenExpiry(0);
    }

    try {
      final result = await _login5.loginWithStoredCredential(
        clientToken: await _androidClientToken(),
        deviceId: await _deviceId(),
        username: credential.username,
        data: credential.blob,
      );
      if (result is! Login5Success) throw StateError('该凭据需要额外验证，无法直接导入');
      await _persistLogin5(result.ok, fallbackUsername: credential.username, fallbackCredential: credential.blob);
      await _loadProfile();
    } catch (_) {
      if (switchingDevice) {
        await _storage.setDeviceId(previousDeviceId);
        await _storage.setClientToken('');
        await _storage.setClientTokenExpiry(0);
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // OAuth PKCE（浏览器授权）
  // ---------------------------------------------------------------------------

  /// 桌面版授权（默认登录方式）：无需任何配置，在系统浏览器中登录官方账号页。
  Future<PendingOAuth> beginDesktopOAuth() => _beginOAuth(const OAuthClientConfig.desktop());

  /// 开发者应用授权：使用用户自己的 Client ID。
  Future<PendingOAuth> beginOAuth(String clientId) {
    final id = clientId.trim();
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(id)) {
      return Future.error(const OAuthException('Client ID 应为 32 位十六进制字符串'));
    }
    return _beginOAuth(OAuthClientConfig.developer(id));
  }

  /// 启动本机回环监听并返回授权页地址。
  ///
  /// UI 负责用浏览器打开 [PendingOAuth.authorizeUrl]；[PendingOAuth.completion] 在令牌换取成功后完成。
  Future<PendingOAuth> _beginOAuth(OAuthClientConfig config) async {
    final pkce = OAuthPkceService.generatePkce();
    final state = OAuthPkceService.generateState();
    final codeFuture = await _loopback.start(expectedState: state, path: config.redirectPath);

    final completion =
        codeFuture.then((code) => completeOAuth(config: config, code: code, codeVerifier: pkce.verifier));
    return PendingOAuth(
      authorizeUrl: OAuthPkceService.buildAuthorizeUrl(config: config, codeChallenge: pkce.challenge, state: state),
      completion: completion,
    );
  }

  /// 取消等待中的浏览器授权。
  Future<void> cancelOAuth() => _loopback.close();

  /// 用授权码换取令牌并持久化（回环服务收到回调后调用；也便于测试直接注入授权码）。
  Future<void> completeOAuth({
    required OAuthClientConfig config,
    required String code,
    required String codeVerifier,
  }) async {
    final tokens = await _oauthFor(config).exchangeCode(config: config, code: code, codeVerifier: codeVerifier);
    if (!config.isDesktop) await _storage.setClientId(config.clientId);
    await _persistOAuth(tokens, config.isDesktop ? AuthMethod.desktop : AuthMethod.oauth);

    // 桌面版会话：立即以桌面身份申请 client-token，之后内部接口与令牌身份一致；失败不影响登录
    if (config.isDesktop) {
      try {
        await ensureClientToken(SpotifyClientProfile.desktop);
      } catch (_) {}
    }

    if (config.isDesktop) {
      await _loadDesktopProfile();
      return;
    }

    // 开发者应用没有 Login5 用户名：以 /v1/me 的用户 ID 作为 username
    final profile = await _profiles.fetch(
      username: '',
      accessToken: tokens.accessToken,
      preferIdentityService: false,
      profile: clientProfile,
    );
    if (profile != null) {
      if (profile.id.isNotEmpty) await _storage.setUsername(profile.id);
      await _storage.setDisplayName(profile.displayName);
      await _storage.setAvatarUrl(profile.avatarUrl);
    }
  }

  OAuthPkceService _oauthFor(OAuthClientConfig config) => config.isDesktop ? _desktopOAuth : _oauth;

  // ---------------------------------------------------------------------------
  // 令牌续期
  // ---------------------------------------------------------------------------

  /// 返回有效 access_token；过期时按登录方式免密续期。
  Future<String> ensureAccessToken() {
    if (_storage.accessToken.isNotEmpty && _isFresh(_storage.accessTokenExpiry)) {
      return Future.value(_storage.accessToken);
    }
    return refreshAccessToken();
  }

  /// 强制续期（并发调用会合并）。
  Future<String> refreshAccessToken() {
    if (!_storage.isLoggedIn) {
      return Future.error(StateError('未登录，无法获取 access_token'));
    }
    return _refreshInFlight ??= _refresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String> _refresh() async {
    final method = _storage.authMethod;
    if (method == AuthMethod.oauth || method == AuthMethod.desktop) {
      final config =
          method == AuthMethod.desktop ? const OAuthClientConfig.desktop() : OAuthClientConfig.developer(_storage.clientId);
      final tokens = await _oauthFor(config).refresh(config: config, refreshToken: _storage.refreshToken);
      await _persistOAuth(tokens, method);
      return _storage.accessToken;
    }

    final result = await _login5.loginWithStoredCredential(
      clientToken: await _androidClientToken(),
      deviceId: await _deviceId(),
      username: _storage.username,
      data: Uint8List.fromList(base64Decode(_storage.storedCredential)),
    );
    if (result is! Login5Success) {
      throw StateError('凭据续期被要求验证码，请重新登录');
    }
    await _persistLogin5(result.ok);
    return _storage.accessToken;
  }

  /// 桌面版会话：先走内部资料接口，失败再回退公开 /v1/me（后者常被限流）。
  Future<void> _loadDesktopProfile() async {
    final profile = await _profiles.fetchProfileView(
          accessToken: _storage.accessToken,
          clientToken: _storage.clientToken,
          profile: SpotifyClientProfile.desktop,
        ) ??
        await _profiles.fetch(
          username: '',
          accessToken: _storage.accessToken,
          preferIdentityService: false,
          profile: SpotifyClientProfile.desktop,
        );
    if (profile == null) return;
    if (profile.id.isNotEmpty) await _storage.setUsername(profile.id);
    await _storage.setDisplayName(profile.displayName);
    await _storage.setAvatarUrl(profile.avatarUrl);
  }

  /// 已登录但昵称缺失时补拉资料（如登录时资料接口失败）；失败静默。
  Future<void> ensureProfile() async {
    if (!isLoggedIn || _storage.displayName.isNotEmpty) return;
    try {
      await ensureAccessToken();
      if (_storage.authMethod == AuthMethod.desktop) {
        await ensureClientToken(SpotifyClientProfile.desktop);
        await _loadDesktopProfile();
      } else if (_storage.authMethod == AuthMethod.login5) {
        await _loadProfile();
      }
    } catch (_) {}
  }

  /// 重新拉取昵称与头像（登录成功后自动调用；失败不影响登录）。
  Future<void> _loadProfile() async {
    try {
      final profile = await _profiles.fetch(
        username: _storage.username,
        accessToken: _storage.accessToken,
        clientToken: _storage.clientToken,
      );
      if (profile == null) return;
      await _storage.setDisplayName(profile.displayName);
      await _storage.setAvatarUrl(profile.avatarUrl);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 登出
  // ---------------------------------------------------------------------------

  /// 登出：尽力通知服务端（`/api/logout/v1`），然后清除全部登录态并切回 Mock 数据（保留 device_id）。
  Future<void> logout() async {
    _pendingSession = null;
    await _loopback.close();
    final token = _storage.accessToken;
    // 官方客户端身份的会话才通知 spclient；开发者应用 OAuth 无对应会话
    if (token.isNotEmpty && clientProfile != null) {
      try {
        await _client.post(
          Uri.parse('${SpotifyEndpoints.defaultSpClientBase}/api/logout/v1'),
          headers: {
            'Authorization': 'Bearer $token',
            if (_storage.clientToken.isNotEmpty) 'client-token': _storage.clientToken,
            ...clientHeaders,
          },
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await _storage.clearLogin();
    await _storage.setUseMockData(true);
  }

  // ---------------------------------------------------------------------------
  // 持久化
  // ---------------------------------------------------------------------------

  Future<void> _persistLogin5(LoginOk ok, {String fallbackUsername = '', Uint8List? fallbackCredential}) async {
    await _storage.setAuthMethod(AuthMethod.login5);
    final name = ok.username.isNotEmpty ? ok.username : fallbackUsername;
    if (name.isNotEmpty) await _storage.setUsername(name);
    await _storage.setAccessToken(ok.accessToken);
    await _storage.setAccessTokenExpiry(
      DateTime.now().add(Duration(seconds: ok.accessTokenExpiresIn)).millisecondsSinceEpoch,
    );
    // stored_credential 仅在交互式登录时返回；续期 / 导入的响应可能为空，保留已有值
    final stored = ok.storedCredential.isNotEmpty ? ok.storedCredential : fallbackCredential;
    if (stored != null && stored.isNotEmpty) {
      await _storage.setStoredCredential(base64Encode(stored));
    }
    await _storage.setUseMockData(false);
  }

  Future<void> _persistOAuth(OAuthTokens tokens, AuthMethod method) async {
    await _storage.setAuthMethod(method);
    await _storage.setAccessToken(tokens.accessToken);
    await _storage.setAccessTokenExpiry(
      DateTime.now().add(Duration(seconds: tokens.expiresIn)).millisecondsSinceEpoch,
    );
    if (tokens.refreshToken.isNotEmpty) await _storage.setRefreshToken(tokens.refreshToken);
    await _storage.setUseMockData(false);
  }
}

/// 待输入的短信验证码信息。
class PendingCodeChallenge {
  final int codeLength;
  final String canonicalPhoneNumber;
  const PendingCodeChallenge({required this.codeLength, required this.canonicalPhoneNumber});
}

/// 进行中的浏览器授权。
class PendingOAuth {
  final Uri authorizeUrl;
  final Future<void> completion;
  const PendingOAuth({required this.authorizeUrl, required this.completion});
}
