import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../services/auth/oauth_pkce_service.dart';
import '../services/auth/spotify_auth_service.dart';

/// 登录流程所处阶段。
enum AuthStatus {
  /// 未登录（可展示登录页）。
  signedOut,

  /// 已打开浏览器授权页，等待回调。
  authorizing,

  /// 已登录。
  signedIn,
}

/// Spotify 账号登录态（唯一方式：在浏览器中登录）。
///
/// UI 只与本类交互：它把 [SpotifyAuthService] 的异步结果翻译成可渲染的状态与中文错误提示。
/// 登录 / 登出成功后回调 [onSessionChanged]，由外部刷新依赖登录态的数据。
class AuthProvider extends ChangeNotifier {
  final SpotifyAuthService _auth;

  /// 登录态变化（登录成功 / 登出）后的回调。
  VoidCallback? onSessionChanged;

  AuthStatus _status;
  String? _error;
  bool _refreshing = false;
  Uri? _authorizeUrl;

  AuthProvider(this._auth) : _status = _auth.isLoggedIn ? AuthStatus.signedIn : AuthStatus.signedOut {
    // 恢复的会话缺资料（昵称 / 用户名）时启动后补拉一次；拿到用户名后媒体库需要重新加载
    if (_auth.needsProfile) {
      final usernameBefore = _auth.username;
      unawaited(
        _auth.ensureProfile().then((_) {
          notifyListeners();
          if (_auth.username != usernameBefore) onSessionChanged?.call();
        }),
      );
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
  bool get isAuthorizing => _status == AuthStatus.authorizing;
  bool get isRefreshing => _refreshing;

  /// 最近一次操作的错误提示；新的操作开始时清空。
  String? get error => _error;

  /// 浏览器授权页地址（[AuthStatus.authorizing] 时有值，供「复制链接」）。
  Uri? get authorizeUrl => _authorizeUrl;

  String get username => _auth.username;
  String get displayName => _auth.displayName;
  String get avatarUrl => _auth.avatarUrl;
  DateTime? get accessTokenExpiry => _auth.accessTokenExpiry;

  // ---------------------------------------------------------------------------
  // 浏览器授权
  // ---------------------------------------------------------------------------

  /// 启动浏览器授权并进入等待态，返回授权页地址（由 UI 打开）；失败返回 null。
  /// 授权完成后状态自动切到 [AuthStatus.signedIn] 并回调 [onSessionChanged]。
  Future<Uri?> beginOAuth() async {
    if (_status == AuthStatus.authorizing) return null;
    _error = null;
    final PendingOAuth pending;
    try {
      pending = await _auth.beginOAuth();
    } catch (e) {
      _error = describeError(e);
      notifyListeners();
      return null;
    }
    _authorizeUrl = pending.authorizeUrl;
    _status = AuthStatus.authorizing;
    notifyListeners();

    unawaited(
      pending.completion
          .then((_) {
            _authorizeUrl = null;
            _status = AuthStatus.signedIn;
            notifyListeners();
            onSessionChanged?.call();
          })
          .catchError((Object e) {
            // 用户主动取消时状态已被 cancelOAuth 重置，不再覆盖
            if (_status != AuthStatus.authorizing) return;
            _authorizeUrl = null;
            _status = AuthStatus.signedOut;
            _error = describeError(e);
            notifyListeners();
          }),
    );
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

  /// 立即续期 access_token（设置页「刷新令牌」）。
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

  /// 把底层异常翻译为面向用户的中文提示。
  @visibleForTesting
  static String describeError(Object e) {
    if (e is OAuthException) return e.toString();
    if (e is SocketException || e is TimeoutException || e is http.ClientException) {
      return '无法连接到 Spotify，请检查网络或代理';
    }
    if (e is StateError) return e.message;
    return '登录失败：$e';
  }
}
