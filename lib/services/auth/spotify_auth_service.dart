import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/spotify_endpoints.dart';
import '../protocol/access_point.dart';
import '../storage_service.dart';
import 'account_profile_service.dart';
import 'auth_constants.dart';
import 'client_profile.dart';
import 'client_token_service.dart';
import 'oauth_client_config.dart';
import 'oauth_loopback_server.dart';
import 'oauth_pkce_service.dart';

/// Spotify 身份鉴权总控：只有一条登录链路——**在浏览器中登录**（桌面版 OAuth）。
///
/// 与官方桌面版相同，在系统浏览器的 accounts.spotify.com 完成登录 → 本机回环接收授权码 →
/// PKCE 换取令牌；App 不接触密码，账号验证由官方页面处理。
/// 会话以 Windows 桌面端身份申请 client-token；access_token 过期后用 refresh_token 续期。
///
/// 说明：以官方客户端身份登录违反 Spotify 服务条款，存在账号风控风险，建议用小号测试。
class SpotifyAuthService {
  /// 令牌提前续期的余量：剩余有效期不足该值即视为过期。
  static const int _refreshMarginMs = 60 * 1000;

  static const OAuthClientConfig _config = OAuthClientConfig.desktop();
  static const SpotifyClientProfile _profile = SpotifyClientProfile.desktop;

  final StorageService _storage;
  final http.Client _client;
  final ClientTokenService _clientTokenService;
  final OAuthPkceService _oauth;
  final AccountProfileService _profiles;
  final OAuthLoopbackServer _loopback;

  /// 按 access_token 查询 canonical username（默认登录 AP 读 APWelcome；测试注入替身）。
  final Future<String> Function(String accessToken, String deviceId)
  _usernameResolver;

  /// 正在进行中的续期请求：并发调用复用同一个 Future，避免重复打令牌端点。
  Future<String>? _refreshInFlight;
  Future<String>? _clientTokenInFlight;

  /// 登录已失效：服务端吊销了续期凭据，只能重新登录。置位后不再请求令牌端点（避免每个请求都打一次），
  /// 重新登录或登出时清除。不持久化：重启 App 会再试一次续期。
  final ValueNotifier<bool> sessionExpired = ValueNotifier(false);

  SpotifyAuthService._(
    this._storage,
    this._client,
    this._loopback,
    this._usernameResolver,
  ) : _clientTokenService = ClientTokenService(_client),
      _oauth = OAuthPkceService(_client, userAgent: _profile.userAgent),
      _profiles = AccountProfileService(_client);

  factory SpotifyAuthService(
    StorageService storage, [
    http.Client? client,
    OAuthLoopbackServer? loopback,
    Future<String> Function(String accessToken, String deviceId)?
    usernameResolver,
  ]) {
    final http.Client effectiveClient = client ?? http.Client();
    return SpotifyAuthService._(
      storage,
      effectiveClient,
      loopback ?? OAuthLoopbackServer(),
      usernameResolver ??
          (token, deviceId) =>
              _usernameFromAccessPoint(effectiveClient, token, deviceId),
    );
  }

  bool get isLoggedIn => _storage.isLoggedIn;
  String get username => _storage.username;
  String get displayName => _storage.displayName.isNotEmpty
      ? _storage.displayName
      : _storage.username;
  String get avatarUrl => _storage.avatarUrl;

  /// 业务请求应附带的客户端头（User-Agent / app-platform / spotify-app-version），与令牌所属客户端一致。
  Map<String, String> get clientHeaders {
    if (!isLoggedIn) return const {};
    return {'user-agent': _profile.userAgent, ..._profile.headers};
  }

  /// access_token 到期时间；未登录返回 null。
  DateTime? get accessTokenExpiry {
    final ms = _storage.accessTokenExpiry;
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 设备 ID：首次调用时生成并持久化（client-token 与其绑定，不可随意更换）。
  Future<String> _deviceId() async {
    var id = _storage.deviceId;
    if (id.isEmpty) {
      id = SpotifyAuthConstants.generateDeviceId();
      await _storage.setDeviceId(id);
    }
    return id;
  }

  static bool _isFresh(int expiryMs) =>
      expiryMs > DateTime.now().millisecondsSinceEpoch + _refreshMarginMs;

  // ---------------------------------------------------------------------------
  // client-token
  // ---------------------------------------------------------------------------

  /// 获取有效的桌面端 client-token；过期、缺失或身份不一致（旧版本留下的）则重新申请。
  Future<String> ensureClientToken() {
    if (_storage.clientToken.isNotEmpty &&
        _storage.clientTokenProfile == _profile.name &&
        _isFresh(_storage.clientTokenExpiry)) {
      return Future.value(_storage.clientToken);
    }
    return _clientTokenInFlight ??= _requestClientToken().whenComplete(() {
      _clientTokenInFlight = null;
    });
  }

  Future<String> _requestClientToken() async {
    final granted = await _clientTokenService.request(
      await _deviceId(),
      _profile,
    );
    await _storage.setClientToken(granted.token);
    await _storage.setClientTokenExpiry(granted.expiryEpochMs(DateTime.now()));
    await _storage.setClientTokenProfile(_profile.name);
    return granted.token;
  }

  // ---------------------------------------------------------------------------
  // 浏览器授权（OAuth PKCE）
  // ---------------------------------------------------------------------------

  /// 启动本机回环监听并返回授权页地址。
  ///
  /// UI 负责用浏览器打开 [PendingOAuth.authorizeUrl]；[PendingOAuth.completion] 在令牌换取成功后完成。
  Future<PendingOAuth> beginOAuth() async {
    final pkce = OAuthPkceService.generatePkce();
    final state = OAuthPkceService.generateState();
    final codeFuture = await _loopback.start(
      expectedState: state,
      path: _config.redirectPath,
    );

    final completion = codeFuture.then(
      (code) => completeOAuth(code: code, codeVerifier: pkce.verifier),
    );
    return PendingOAuth(
      authorizeUrl: OAuthPkceService.buildAuthorizeUrl(
        config: _config,
        codeChallenge: pkce.challenge,
        state: state,
      ),
      completion: completion,
    );
  }

  /// 取消等待中的浏览器授权。
  Future<void> cancelOAuth() => _loopback.close();

  /// 用授权码换取令牌并持久化（回环服务收到回调后调用；也便于测试直接注入授权码）。
  Future<void> completeOAuth({
    required String code,
    required String codeVerifier,
  }) async {
    final tokens = await _oauth.exchangeCode(
      config: _config,
      code: code,
      codeVerifier: codeVerifier,
    );
    await _persist(tokens);

    // 立即以桌面身份申请 client-token，之后内部接口与令牌身份一致；失败不影响登录
    try {
      await ensureClientToken();
    } catch (_) {}
    await _loadProfile();
  }

  // ---------------------------------------------------------------------------
  // 令牌续期
  // ---------------------------------------------------------------------------

  /// 返回有效 access_token；过期时用 refresh_token 免密续期。
  Future<String> ensureAccessToken() {
    if (_storage.accessToken.isNotEmpty &&
        _isFresh(_storage.accessTokenExpiry)) {
      return Future.value(_storage.accessToken);
    }
    return refreshAccessToken();
  }

  /// 强制续期（并发调用会合并）。
  Future<String> refreshAccessToken() {
    if (!_storage.isLoggedIn) {
      return Future.error(StateError('未登录，无法获取 access_token'));
    }
    if (sessionExpired.value) {
      return Future.error(const OAuthException('登录已过期，请重新登录', 'invalid_grant'));
    }
    return _refreshInFlight ??= _refresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  /// 等待进行中的续期落盘（关窗前调用）。
  ///
  /// 续期请求一旦发出，服务端可能已轮换 refresh_token、旧值作废；此时进程被结束而新值没写入，
  /// 下次启动就只能重新登录。
  Future<void> settle() async {
    final inFlight = _refreshInFlight;
    if (inFlight == null) return;
    try {
      await inFlight;
    } catch (_) {}
  }

  Future<String> _refresh() async {
    try {
      final tokens = await _oauth.refresh(
        config: _config,
        refreshToken: _storage.refreshToken,
      );
      await _persist(tokens);
    } on OAuthException catch (e) {
      if (e.isRevoked) sessionExpired.value = true;
      rethrow;
    }
    return _storage.accessToken;
  }

  // ---------------------------------------------------------------------------
  // 账号资料
  // ---------------------------------------------------------------------------

  /// 先确定用户名，再走内部资料接口，失败回退公开 /v1/me（后者常被限流）。
  Future<void> _loadProfile() async {
    if (_storage.username.isEmpty) {
      // 旧版本按 `profile/me` 取到的是另一个账号的资料，先清掉，取不到新资料时宁可显示用户名
      await _storage.setDisplayName('');
      await _storage.setAvatarUrl('');
      try {
        final username = await _usernameResolver(
          _storage.accessToken,
          _storage.deviceId,
        );
        if (username.isNotEmpty) await _storage.setUsername(username);
      } catch (_) {
        // AP 不可达时交给 /v1/me 回退（其响应的 id 即用户名）
      }
    }
    final profile =
        await _profiles.fetchProfileView(
          username: _storage.username,
          accessToken: _storage.accessToken,
          clientToken: _storage.clientToken,
        ) ??
        await _profiles.fetchMe(_storage.accessToken);
    if (profile == null) return;
    if (profile.id.isNotEmpty && _storage.username.isEmpty)
      await _storage.setUsername(profile.id);
    await _storage.setDisplayName(profile.displayName);
    await _storage.setAvatarUrl(profile.avatarUrl);
  }

  /// 令牌响应不含用户名：用 access_token 登录 AP，从 APWelcome 取 canonical username。
  /// 媒体库（rootlist / 收藏集合）与资料接口都按用户名寻址，缺它整个媒体库为空。
  static Future<String> _usernameFromAccessPoint(
    http.Client client,
    String accessToken,
    String deviceId,
  ) async {
    final ap = await SpotifyAccessPoint.connect(client: client);
    try {
      final welcome = await ap.authenticate(
        ApCredentials.accessToken(accessToken),
        deviceId: deviceId.isEmpty ? null : deviceId,
      );
      return welcome.canonicalUsername;
    } finally {
      ap.close();
    }
  }

  /// 恢复的会话缺资料时需要补拉：昵称或用户名缺失（如登录时资料接口失败）。
  bool get needsProfile =>
      isLoggedIn && (_storage.displayName.isEmpty || _storage.username.isEmpty);

  /// 补拉资料；失败静默。
  Future<void> ensureProfile() async {
    if (!needsProfile) return;
    try {
      await ensureAccessToken();
      await ensureClientToken();
      await _loadProfile();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 登出
  // ---------------------------------------------------------------------------

  /// 登出：尽力通知服务端（`/api/logout/v1`），然后清除全部登录态（保留 device_id）。
  Future<void> logout() async {
    // 已失效的会话不必再通知服务端（令牌早已过期）
    final expired = sessionExpired.value;
    sessionExpired.value = false;
    await _loopback.close();
    final token = _storage.accessToken;
    if (!expired && isLoggedIn && token.isNotEmpty) {
      try {
        await _client
            .post(
              Uri.parse(
                '${SpotifyEndpoints.defaultSpClientBase}/api/logout/v1',
              ),
              headers: {
                'Authorization': 'Bearer $token',
                if (_storage.clientToken.isNotEmpty)
                  'client-token': _storage.clientToken,
                ...clientHeaders,
              },
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await _storage.clearLogin();
  }

  // ---------------------------------------------------------------------------
  // 持久化
  // ---------------------------------------------------------------------------

  Future<void> _persist(OAuthTokens tokens) async {
    sessionExpired.value = false;
    await _storage.markDesktopSession();
    await _storage.setAccessToken(tokens.accessToken);
    await _storage.setAccessTokenExpiry(
      DateTime.now()
          .add(Duration(seconds: tokens.expiresIn))
          .millisecondsSinceEpoch,
    );
    if (tokens.refreshToken.isNotEmpty)
      await _storage.setRefreshToken(tokens.refreshToken);
  }
}

/// 进行中的浏览器授权。
class PendingOAuth {
  final Uri authorizeUrl;
  final Future<void> completion;
  const PendingOAuth({required this.authorizeUrl, required this.completion});
}
