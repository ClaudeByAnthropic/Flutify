import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 持久化封装：凭证、配置、媒体库与播放偏好。
class StorageService {
  static const String _keyAccessToken = 'sp_access_token';
  static const String _keyRefreshToken = 'sp_refresh_token';
  static const String _keyClientId = 'sp_client_id';
  static const String _keyClientSecret = 'sp_client_secret';
  static const String _keyApiBaseUrl = 'sp_api_base_url';
  static const String _keySpClientToken = 'sp_spclient_token';

  // Login5 鉴权持久化
  static const String _keyDeviceId = 'sp_device_id';
  static const String _keyUsername = 'sp_username';
  static const String _keyStoredCredential = 'sp_stored_credential'; // base64
  static const String _keyAccessTokenExpiry = 'sp_access_token_expiry'; // epoch ms
  static const String _keyClientToken = 'sp_client_token';
  static const String _keyClientTokenExpiry = 'sp_client_token_expiry'; // epoch ms
  static const String _keyClientTokenProfile = 'sp_client_token_profile'; // 'android' | 'desktop'

  // 登录方式与账号展示信息
  static const String _keyAuthMethod = 'sp_auth_method'; // AuthMethod.name
  static const String _keyDisplayName = 'sp_display_name';
  static const String _keyAvatarUrl = 'sp_avatar_url';

  static const String _keyRecentSearches = 'sp_recent_searches';
  static const String _keyVolume = 'sp_volume';
  static const String _keyPauseAfterFailures = 'play_pause_after_failures';
  static const String _keyAppearance = 'ui_appearance'; // 外观设置 JSON

  // 媒体库（JSON 序列化的实体列表）
  static const String keyLibraryLikedTracks = 'lib_liked_tracks';
  static const String keyLibraryPlaylists = 'lib_playlists';
  static const String keyLibraryArtists = 'lib_artists';
  static const String keyLibraryAlbums = 'lib_albums';

  /// 用户在本机创建 / 保存的歌单（不随账号同步；远端 rootlist 歌单缓存在 [keyLibraryPlaylists]）。
  static const String keyLibraryLocalPlaylists = 'lib_playlists_local';
  static const String _keyLibraryAccount = 'lib_account'; // 媒体库缓存所属账号
  static const String _keyLibrarySchema = 'lib_schema'; // 缓存结构版本（旧版含示例数据）

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // ---------------------------------------------------------------------------
  // Tokens & Configuration
  // ---------------------------------------------------------------------------
  String get accessToken => _prefs.getString(_keyAccessToken) ?? '';
  Future<bool> setAccessToken(String value) => _prefs.setString(_keyAccessToken, value);

  String get refreshToken => _prefs.getString(_keyRefreshToken) ?? '';
  Future<bool> setRefreshToken(String value) => _prefs.setString(_keyRefreshToken, value);

  String get clientId => _prefs.getString(_keyClientId) ?? '';
  Future<bool> setClientId(String value) => _prefs.setString(_keyClientId, value);

  String get clientSecret => _prefs.getString(_keyClientSecret) ?? '';
  Future<bool> setClientSecret(String value) => _prefs.setString(_keyClientSecret, value);

  String get apiBaseUrl => _prefs.getString(_keyApiBaseUrl) ?? 'https://api.spotify.com/v1';
  Future<bool> setApiBaseUrl(String value) => _prefs.setString(_keyApiBaseUrl, value);

  String get spClientToken => _prefs.getString(_keySpClientToken) ?? '';
  Future<bool> setSpClientToken(String value) => _prefs.setString(_keySpClientToken, value);

  // ---------------------------------------------------------------------------
  // Login5 鉴权
  // ---------------------------------------------------------------------------
  /// 设备 ID：首次访问时生成并持久化（由调用方传入生成器，避免此层依赖）。
  String get deviceId => _prefs.getString(_keyDeviceId) ?? '';
  Future<bool> setDeviceId(String value) => _prefs.setString(_keyDeviceId, value);

  String get username => _prefs.getString(_keyUsername) ?? '';
  Future<bool> setUsername(String value) => _prefs.setString(_keyUsername, value);

  String get storedCredential => _prefs.getString(_keyStoredCredential) ?? '';
  Future<bool> setStoredCredential(String base64Value) => _prefs.setString(_keyStoredCredential, base64Value);

  int get accessTokenExpiry => _prefs.getInt(_keyAccessTokenExpiry) ?? 0;
  Future<bool> setAccessTokenExpiry(int epochMs) => _prefs.setInt(_keyAccessTokenExpiry, epochMs);

  String get clientToken => _prefs.getString(_keyClientToken) ?? '';
  Future<bool> setClientToken(String value) => _prefs.setString(_keyClientToken, value);

  int get clientTokenExpiry => _prefs.getInt(_keyClientTokenExpiry) ?? 0;
  Future<bool> setClientTokenExpiry(int epochMs) => _prefs.setInt(_keyClientTokenExpiry, epochMs);

  /// 当前 client-token 以哪种客户端身份申请（与登录方式不一致时需重新申请）。
  String get clientTokenProfile => _prefs.getString(_keyClientTokenProfile) ?? '';
  Future<bool> setClientTokenProfile(String value) => _prefs.setString(_keyClientTokenProfile, value);

  /// 登录方式；未知或缺省值按 Login5 处理（兼容旧版本数据）。
  AuthMethod get authMethod {
    final name = _prefs.getString(_keyAuthMethod);
    return AuthMethod.values.firstWhere((m) => m.name == name, orElse: () => AuthMethod.login5);
  }

  Future<bool> setAuthMethod(AuthMethod value) => _prefs.setString(_keyAuthMethod, value.name);

  String get displayName => _prefs.getString(_keyDisplayName) ?? '';
  Future<bool> setDisplayName(String value) => _prefs.setString(_keyDisplayName, value);

  String get avatarUrl => _prefs.getString(_keyAvatarUrl) ?? '';
  Future<bool> setAvatarUrl(String value) => _prefs.setString(_keyAvatarUrl, value);

  /// 是否已登录：Login5 需要可复用凭据；OAuth 需要 refresh_token（开发者应用还需 client_id）。
  bool get isLoggedIn => switch (authMethod) {
        AuthMethod.login5 => storedCredential.isNotEmpty && username.isNotEmpty,
        AuthMethod.oauth => refreshToken.isNotEmpty && clientId.isNotEmpty,
        AuthMethod.desktop => refreshToken.isNotEmpty,
      };

  /// 清除全部登录态（登出）。device_id 与 OAuth client_id 保留，便于下次登录。
  Future<void> clearLogin() async {
    await _prefs.remove(_keyAuthMethod);
    await _prefs.remove(_keyDisplayName);
    await _prefs.remove(_keyAvatarUrl);
    await _prefs.remove(_keyRefreshToken);
    await _prefs.remove(_keyUsername);
    await _prefs.remove(_keyStoredCredential);
    await _prefs.remove(_keyAccessToken);
    await _prefs.remove(_keyAccessTokenExpiry);
    await _prefs.remove(_keyClientToken);
    await _prefs.remove(_keyClientTokenExpiry);
    await _prefs.remove(_keyClientTokenProfile);
    await _prefs.remove(_keySpClientToken);
  }

  // ---------------------------------------------------------------------------
  // Playback preferences
  // ---------------------------------------------------------------------------
  double get volume => _prefs.getDouble(_keyVolume) ?? 0.8;
  Future<bool> setVolume(double value) => _prefs.setDouble(_keyVolume, value);

  /// 连续多首无法播放时自动暂停（默认开启）。
  bool get pauseAfterFailures => _prefs.getBool(_keyPauseAfterFailures) ?? true;
  Future<bool> setPauseAfterFailures(bool value) => _prefs.setBool(_keyPauseAfterFailures, value);

  /// 外观设置（JSON 字符串，解析见 AppearanceSettings.fromJson）；未保存过为空串。
  String get appearanceJson => _prefs.getString(_keyAppearance) ?? '';
  Future<bool> setAppearanceJson(String value) => _prefs.setString(_keyAppearance, value);

  // ---------------------------------------------------------------------------
  // Generic JSON list persistence (used by LibraryProvider)
  // ---------------------------------------------------------------------------
  bool hasKey(String key) => _prefs.containsKey(key);

  Future<bool> removeKey(String key) => _prefs.remove(key);

  /// 媒体库缓存所属账号（canonical username）；账号变化时缓存作废。
  String get libraryAccount => _prefs.getString(_keyLibraryAccount) ?? '';
  Future<bool> setLibraryAccount(String value) => _prefs.setString(_keyLibraryAccount, value);

  /// 媒体库缓存结构版本：低于当前版本说明缓存来自带示例数据的旧版，需要迁移。
  int get librarySchema => _prefs.getInt(_keyLibrarySchema) ?? 0;
  Future<bool> setLibrarySchema(int value) => _prefs.setInt(_keyLibrarySchema, value);

  /// 读取 JSON 对象列表；单条损坏的数据会被跳过而不是让整个列表失效。
  List<Map<String, dynamic>> readJsonList(String key) {
    final raw = _prefs.getStringList(key);
    if (raw == null) return const [];
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) result.add(decoded);
      } catch (_) {}
    }
    return result;
  }

  Future<bool> writeJsonList(String key, Iterable<Map<String, dynamic>> items) {
    return _prefs.setStringList(key, items.map(jsonEncode).toList());
  }

  // ---------------------------------------------------------------------------
  // Search History
  // ---------------------------------------------------------------------------
  List<String> get recentSearches => _prefs.getStringList(_keyRecentSearches) ?? [];
  Future<bool> addRecentSearch(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return Future.value(false);
    final list = recentSearches;
    list.remove(clean);
    list.insert(0, clean);
    if (list.length > 20) list.removeLast();
    return _prefs.setStringList(_keyRecentSearches, list);
  }

  Future<bool> removeRecentSearch(String query) {
    final list = recentSearches..remove(query);
    return _prefs.setStringList(_keyRecentSearches, list);
  }

  Future<bool> clearRecentSearches() => _prefs.remove(_keyRecentSearches);
}

/// 账号登录方式。
enum AuthMethod {
  /// Login5 直连（Android 身份）：密码 / 短信 / 一次性令牌 / 导入凭据。
  login5,

  /// 开发者应用 OAuth（用户自己的 client_id）。
  oauth,

  /// 桌面版 OAuth（官方桌面 client_id，默认登录方式）。
  desktop,
}
