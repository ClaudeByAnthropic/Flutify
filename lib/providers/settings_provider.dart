import 'package:flutter/material.dart';
import '../services/storage_service.dart';

/// 设置页的凭据与 API 基址配置（手动令牌、OAuth 密钥、自定义 Web API 地址、SpClient 令牌）。
///
/// 登录 / 登出会直接改写存储，之后调用 [reloadFromStorage] 同步本地缓存。
class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;

  String _accessToken = '';
  String _refreshToken = '';
  String _clientId = '';
  String _clientSecret = '';
  String _apiBaseUrl = '';
  String _spClientToken = '';

  SettingsProvider(this._storage) {
    _readStorage();
  }

  void _readStorage() {
    _accessToken = _storage.accessToken;
    _refreshToken = _storage.refreshToken;
    _clientId = _storage.clientId;
    _clientSecret = _storage.clientSecret;
    _apiBaseUrl = _storage.apiBaseUrl;
    _spClientToken = _storage.spClientToken;
  }

  /// 登录 / 登出会直接改写存储（令牌等），之后调用以同步本地缓存。
  void reloadFromStorage() {
    _readStorage();
    notifyListeners();
  }

  String get accessToken => _accessToken;
  String get refreshToken => _refreshToken;
  String get clientId => _clientId;
  String get clientSecret => _clientSecret;
  String get apiBaseUrl => _apiBaseUrl;
  String get spClientToken => _spClientToken;

  Future<void> updateConfig({
    String? accessToken,
    String? refreshToken,
    String? clientId,
    String? clientSecret,
    String? apiBaseUrl,
    String? spClientToken,
  }) async {
    if (accessToken != null) {
      _accessToken = accessToken;
      await _storage.setAccessToken(accessToken);
    }
    if (refreshToken != null) {
      _refreshToken = refreshToken;
      await _storage.setRefreshToken(refreshToken);
    }
    if (clientId != null) {
      _clientId = clientId;
      await _storage.setClientId(clientId);
    }
    if (clientSecret != null) {
      _clientSecret = clientSecret;
      await _storage.setClientSecret(clientSecret);
    }
    if (apiBaseUrl != null) {
      _apiBaseUrl = apiBaseUrl;
      await _storage.setApiBaseUrl(apiBaseUrl);
    }
    if (spClientToken != null) {
      _spClientToken = spClientToken;
      await _storage.setSpClientToken(spClientToken);
    }
    notifyListeners();
  }
}
