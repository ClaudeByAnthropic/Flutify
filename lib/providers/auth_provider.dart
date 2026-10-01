import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/auth/auth_constants.dart';
import '../services/auth/credential_parsers.dart';
import '../services/auth/oauth_pkce_service.dart';
import '../services/auth/spotify_auth_service.dart';
import '../services/storage_service.dart';

/// 登录流程所处阶段。
enum AuthStatus {
  /// 未登录（可展示登录表单）。
  signedOut,

  /// 正在提交凭据（含 client-token 申请与 Hashcash 求解）。
  signingIn,

  /// 服务端已下发短信验证码，等待用户输入。
  awaitingCode,

  /// 正在校验 / 重新发送验证码。
  verifyingCode,

  /// 已打开浏览器授权页，等待回调。
  authorizing,

  /// 已登录。
  signedIn,
}

/// Spotify 账号登录态。
///
/// UI 只与本类交互：它把 [SpotifyAuthService] 的异步结果翻译成可渲染的状态与中文错误提示。
/// 登录 / 登出成功后回调 [onSessionChanged]，由外部刷新依赖登录态的数据。
class AuthProvider extends ChangeNotifier {
  /// 重新发送验证码的冷却时间。
  static const Duration resendCooldown = Duration(seconds: 60);

  final SpotifyAuthService _auth;

  /// 登录态变化（登录成功 / 登出）后的回调。
  VoidCallback? onSessionChanged;

  AuthStatus _status;
  String? _error;
  PendingCodeChallenge? _challenge;
  bool _refreshing = false;
  DateTime? _codeSentAt;
  Uri? _authorizeUrl;

  AuthProvider(this._auth) : _status = _auth.isLoggedIn ? AuthStatus.signedIn : AuthStatus.signedOut {
    // 恢复的会话缺资料（昵称 / 桌面版用户名）时启动后补拉一次；拿到用户名后媒体库需要重新加载
    if (_auth.needsProfile) {
      final usernameBefore = _auth.username;
      unawaited(_auth.ensureProfile().then((_) {
        notifyListeners();
        if (_auth.username != usernameBefore) onSessionChanged?.call();
      }));
    }
    _auth.sessionExpired.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _auth.sessionExpired.removeListener(notifyListeners);
    super.dispose();
  }

  /// 已登录但续期凭据被服务端吊销：界面应提示「登录已过期」并引导重新登录，而不是报网络错误。
  bool get sessionExpired => isSignedIn && _auth.sessionExpired.value;

  AuthStatus get status => _status;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get isBusy => _status == AuthStatus.signingIn || _status == AuthStatus.verifyingCode;
  bool get isRefreshing => _refreshing;
  bool get isAwaitingCode => _status == AuthStatus.awaitingCode || _status == AuthStatus.verifyingCode;

  /// 最近一次操作的错误提示；新的操作开始时清空。
  String? get error => _error;

  /// 当前短信验证码挑战（仅验证码阶段有值）。
  PendingCodeChallenge? get challenge => _challenge;

  /// 验证码发送时间，用于计算重新发送的冷却。
  DateTime? get codeSentAt => _codeSentAt;

  /// 浏览器授权页地址（[AuthStatus.authorizing] 时有值，供"复制链接"）。
  Uri? get authorizeUrl => _authorizeUrl;

  AuthMethod get method => _auth.method;
  String get username => _auth.username;
  String get displayName => _auth.displayName;
  String get avatarUrl => _auth.avatarUrl;
  String get savedOAuthClientId => _auth.savedOAuthClientId;
  DateTime? get accessTokenExpiry => _auth.accessTokenExpiry;

  // ---------------------------------------------------------------------------
  // Login5 登录方式。均返回 true 表示已完成登录（无需验证码）。
  // ---------------------------------------------------------------------------

  Future<bool> signIn(String username, String password) {
    if (username.trim().isEmpty || password.isEmpty) return _reject('请输入账号和密码');
    return _start(() => _auth.login(username, password));
  }

  Future<bool> signInWithPhone({
    required String number,
    required String isoCountryCode,
    required String callingCode,
  }) {
    if (number.replaceAll(RegExp(r'[^0-9]'), '').length < 5) return _reject('请输入正确的手机号');
    return _start(() => _auth.loginWithPhone(
          number: number,
          isoCountryCode: isoCountryCode,
          callingCode: callingCode,
        ));
  }

  Future<bool> signInWithOneTimeToken(String input) {
    if (CredentialParsers.extractOneTimeToken(input).isEmpty) {
      return _reject('没有识别到一次性令牌，请粘贴完整的登录链接或令牌');
    }
    return _start(() => _auth.loginWithOneTimeToken(input));
  }

  /// 导入可复用凭据：[json] 为 librespot credentials.json 内容；或手动填写 [username] + [blob]。
  Future<bool> importCredential({String? json, String? username, String? blob, String? deviceId}) async {
    if (isBusy) return false;
    final ImportedCredential credential;
    try {
      credential = json != null && json.trim().isNotEmpty
          ? CredentialParsers.parseCredentialsJson(json)
          : CredentialParsers.build(username: username ?? '', blobBase64: blob ?? '', deviceId: deviceId);
    } on FormatException catch (e) {
      return _reject(e.message);
    }
    return _start(() async {
      await _auth.importStoredCredential(credential);
      return null;
    });
  }

  // ---------------------------------------------------------------------------
  // 短信验证码
  // ---------------------------------------------------------------------------

  Future<bool> submitCode(String code) async {
    if (_status != AuthStatus.awaitingCode) return false;
    if (code.trim().isEmpty) return _reject('请输入验证码');
    _enter(AuthStatus.verifyingCode);
    return _complete(() => _auth.submitCode(code), fromCode: true);
  }

  /// 冷却结束后可重新发送验证码。
  bool get canResendCode {
    final sentAt = _codeSentAt;
    return _status == AuthStatus.awaitingCode &&
        (sentAt == null || DateTime.now().difference(sentAt) >= resendCooldown);
  }

  Future<void> resendCode() async {
    if (!canResendCode) return;
    _enter(AuthStatus.verifyingCode);
    await _complete(() => _auth.resendCode(), fromCode: true, isResend: true);
  }

  /// 放弃验证码，回到登录表单。
  void cancelCode() {
    _auth.cancelPendingCode();
    _challenge = null;
    _codeSentAt = null;
    _error = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // OAuth 浏览器授权
  // ---------------------------------------------------------------------------

  /// 桌面版授权（默认登录方式），返回授权页地址（由 UI 打开）；失败返回 null。
  Future<Uri?> beginDesktopOAuth() => _beginAuthorize(_auth.beginDesktopOAuth);

  /// 开发者应用授权，返回授权页地址（由 UI 打开）；失败返回 null。
  Future<Uri?> beginOAuth(String clientId) => _beginAuthorize(() => _auth.beginOAuth(clientId));

  /// 启动浏览器授权并进入等待态。
  /// 授权完成后状态自动切到 [AuthStatus.signedIn] 并回调 [onSessionChanged]。
  Future<Uri?> _beginAuthorize(Future<PendingOAuth> Function() begin) async {
    if (isBusy || _status == AuthStatus.authorizing) return null;
    _error = null;
    final PendingOAuth pending;
    try {
      pending = await begin();
    } catch (e) {
      _setError(describeError(e));
      return null;
    }
    _authorizeUrl = pending.authorizeUrl;
    _status = AuthStatus.authorizing;
    notifyListeners();

    unawaited(pending.completion.then((_) {
      _authorizeUrl = null;
      _succeed();
    }).catchError((Object e) {
      // 用户主动取消时状态已被 cancelOAuth 重置，不再覆盖
      if (_status != AuthStatus.authorizing) return;
      _authorizeUrl = null;
      _status = AuthStatus.signedOut;
      _error = describeError(e);
      notifyListeners();
    }));
    return pending.authorizeUrl;
  }

  Future<void> cancelOAuth() async {
    if (_status != AuthStatus.authorizing) return;
    _status = AuthStatus.signedOut;
    _authorizeUrl = null;
    notifyListeners();
    await _auth.cancelOAuth();
  }

  // ---------------------------------------------------------------------------
  // 已登录操作
  // ---------------------------------------------------------------------------

  /// 立即续期 access_token（设置页"刷新令牌"）。
  Future<void> refreshToken() async {
    if (!isSignedIn || _refreshing) return;
    _refreshing = true;
    _error = null;
    notifyListeners();
    try {
      await _auth.refreshAccessToken();
    } catch (e) {
      _error = describeError(e);
    }
    _refreshing = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _auth.logout();
    _challenge = null;
    _codeSentAt = null;
    _error = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
    onSessionChanged?.call();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  Future<bool> _start(Future<PendingCodeChallenge?> Function() step) async {
    if (isBusy || _status == AuthStatus.authorizing) return false;
    _enter(AuthStatus.signingIn);
    return _complete(step);
  }

  Future<bool> _reject(String message) {
    _setError(message);
    return Future.value(false);
  }

  void _enter(AuthStatus status) {
    _status = status;
    _error = null;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _succeed() {
    _challenge = null;
    _codeSentAt = null;
    _status = AuthStatus.signedIn;
    notifyListeners();
    onSessionChanged?.call();
  }

  /// 执行一步登录并按结果切换状态：null = 成功；PendingCodeChallenge = 需要验证码。
  Future<bool> _complete(
    Future<PendingCodeChallenge?> Function() step, {
    bool fromCode = false,
    bool isResend = false,
  }) async {
    try {
      final challenge = await step();
      if (challenge == null) {
        _succeed();
        return true;
      }
      _challenge = challenge;
      _status = AuthStatus.awaitingCode;
      // 首次下发或重新发送时重置冷却；提交验证码后再次收到挑战说明验证码不正确
      if (!fromCode || isResend) _codeSentAt = DateTime.now();
      if (fromCode && !isResend) _error = '验证码不正确，请重新输入';
    } catch (e) {
      _error = describeError(e);
      // 验证码阶段出错仍停留在验证码页，便于重试；否则回到表单
      _status = fromCode ? AuthStatus.awaitingCode : AuthStatus.signedOut;
    }
    notifyListeners();
    return false;
  }

  /// 把底层异常翻译为面向用户的中文提示。
  @visibleForTesting
  static String describeError(Object e) {
    if (e is Login5Failure) {
      if (e.error == Login5Error.invalidCredentials) {
        return '${e.error.message}。若确认密码无误：可能是 Spotify 限制了非官方客户端的密码登录，'
            '或该账号没有设置密码（通过 Google / Facebook / 邮箱验证码注册）。'
            '请返回改用「在浏览器中登录」，频繁重试可能触发风控';
      }
      return '${e.error.message}（错误码 ${e.error.code}）';
    }
    if (e is Login5UnsupportedChallenge || e is OAuthException) return e.toString();
    if (e is FormatException) return e.message;
    if (e is SocketException || e is TimeoutException || e is http.ClientException) {
      return '无法连接到 Spotify，请检查网络或代理';
    }
    if (e is StateError) return e.message;
    return '登录失败：$e';
  }
}
