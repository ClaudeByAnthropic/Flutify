import 'package:flutter/material.dart';
import '../services/spotify_api_service.dart';
import '../services/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  final SpotifyApiService _api;

  String _accessToken = '';
  String _refreshToken = '';
  String _clientId = '';
  String _clientSecret = '';
  String _apiBaseUrl = '';
  String _spClientToken = '';
  bool _useMockData = true;

  // Reverse Engineering Debugger
  String _testEndpoint = '/me';
  String _testMethod = 'GET';
  Map<String, dynamic>? _lastApiResponse;
  bool _isTestingApi = false;

  SettingsProvider(this._storage, this._api) {
    _readStorage();
  }

  void _readStorage() {
    _accessToken = _storage.accessToken;
    _refreshToken = _storage.refreshToken;
    _clientId = _storage.clientId;
    _clientSecret = _storage.clientSecret;
    _apiBaseUrl = _storage.apiBaseUrl;
    _spClientToken = _storage.spClientToken;
    _useMockData = _storage.useMockData;
  }

  /// 登录 / 登出会直接改写存储（令牌、数据模式），之后调用以同步本地缓存。
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
  bool get useMockData => _useMockData;

  String get testEndpoint => _testEndpoint;
  String get testMethod => _testMethod;
  Map<String, dynamic>? get lastApiResponse => _lastApiResponse;
  bool get isTestingApi => _isTestingApi;

  Future<void> updateConfig({
    String? accessToken,
    String? refreshToken,
    String? clientId,
    String? clientSecret,
    String? apiBaseUrl,
    String? spClientToken,
    bool? useMockData,
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
    if (useMockData != null) {
      _useMockData = useMockData;
      await _storage.setUseMockData(useMockData);
    }
    notifyListeners();
  }

  void setTestEndpoint(String path) {
    _testEndpoint = path;
    notifyListeners();
  }

  void setTestMethod(String method) {
    _testMethod = method;
    notifyListeners();
  }

  Future<void> executeTestApi() async {
    _isTestingApi = true;
    _lastApiResponse = null;
    notifyListeners();

    final res = await _api.testApiEndpoint(_testEndpoint, method: _testMethod);
    _lastApiResponse = res;
    _isTestingApi = false;
    notifyListeners();
  }
}
