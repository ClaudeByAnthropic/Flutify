import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/constants/spotify_endpoints.dart';
import 'client_profile.dart';
import 'proto_codec.dart';

/// 登录后拉取账号展示信息（昵称 + 头像）。
///
/// - 首选内部身份服务 `GET identity/v3/user/username/{username}`（protobuf `Identity$UserProfile`，
///   见 01-认证与账号 #17）；
/// - 失败或 OAuth 登录时回退到公开 Web API `GET /v1/me`。
class AccountProfileService {
  final http.Client _client;

  AccountProfileService(this._client);

  Future<AccountProfile?> fetch({
    required String username,
    required String accessToken,
    String clientToken = '',
    bool preferIdentityService = true,
    // 会话所属客户端身份；开发者应用 OAuth 传 null，只发标准请求头
    SpotifyClientProfile? profile = SpotifyClientProfile.android,
  }) async {
    if (preferIdentityService && username.isNotEmpty) {
      try {
        final identity =
            await _fetchIdentity(username, accessToken, clientToken, profile ?? SpotifyClientProfile.android);
        if (identity != null) return identity;
      } catch (_) {}
    }
    try {
      return await _fetchMe(accessToken, profile);
    } catch (_) {
      return null;
    }
  }

  Future<AccountProfile?> _fetchIdentity(
    String username,
    String accessToken,
    String clientToken,
    SpotifyClientProfile profile,
  ) async {
    final res = await _client.get(
      Uri.parse('${SpotifyEndpoints.defaultSpClientBase}/identity/v3/user/username/${Uri.encodeComponent(username)}'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (clientToken.isNotEmpty) 'client-token': clientToken,
        'Accept': 'application/x-protobuf',
        'User-Agent': profile.userAgent,
        ...profile.headers,
      },
    );
    if (res.statusCode != 200) return null;
    return parseIdentityProfile(res.bodyBytes);
  }

  /// 解析 Identity$UserProfile{ username=1 StringValue, name=2 StringValue, images=3 repeated Image }。
  ///
  /// Image 的字段在文档中未给出，按"取最大宽度的 http 链接"宽松解析：
  /// 常见布局为 Image{ max_width=1, max_height=2, url=3 }。
  static AccountProfile? parseIdentityProfile(List<int> bytes) {
    var username = '';
    var name = '';
    var bestUrl = '';
    var bestWidth = -1;

    ProtoReader(_asUint8(bytes)).forEach((f) {
      if (f.wireType != 2) return;
      switch (f.number) {
        case 1:
          username = _stringValue(f.asMessage);
          break;
        case 2:
          name = _stringValue(f.asMessage);
          break;
        case 3:
          var url = '';
          var width = 0;
          f.asMessage.forEach((img) {
            if (img.wireType == 0 && img.number == 1) width = img.varintValue;
            if (img.wireType == 2 && img.asString.startsWith('http')) url = img.asString;
          });
          if (url.isNotEmpty && width > bestWidth) {
            bestUrl = url;
            bestWidth = width;
          }
          break;
      }
    });

    if (username.isEmpty && name.isEmpty) return null;
    return AccountProfile(displayName: name.isNotEmpty ? name : username, avatarUrl: bestUrl);
  }

  /// google.protobuf.StringValue{ value=1 }
  static String _stringValue(ProtoReader r) {
    var value = '';
    r.forEach((f) {
      if (f.number == 1 && f.wireType == 2) value = f.asString;
    });
    return value;
  }

  /// 内部资料接口 `user-profile-view/v3/profile/{username}`（桌面版会话使用）。
  ///
  /// 桌面版 client_id 为众多客户端共用，公开 Web API 常年处于 429 限流，内部接口不受影响。
  /// 注意：路径里必须是真实用户名——`profile/me` 会被当作用户名为 "me" 的另一个账号。
  Future<AccountProfile?> fetchProfileView({
    required String username,
    required String accessToken,
    required String clientToken,
    required SpotifyClientProfile profile,
  }) async {
    if (username.isEmpty) return null;
    try {
      final res = await _client.get(
        Uri.parse('${SpotifyEndpoints.defaultSpClientBase}/user-profile-view/v3/profile/'
            '${Uri.encodeComponent(username)}?playlist_limit=0&artist_limit=0'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          if (clientToken.isNotEmpty) 'client-token': clientToken,
          'Accept': 'application/json',
          'User-Agent': profile.userAgent,
          ...profile.headers,
        },
      );
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final name = (json['name'] as String? ?? '').trim();
      if (name.isEmpty) return null;
      return AccountProfile(displayName: name, avatarUrl: json['image_url'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<AccountProfile?> _fetchMe(String accessToken, SpotifyClientProfile? profile) async {
    final res = await _client.get(
      Uri.parse('${SpotifyEndpoints.defaultWebApiBase}${SpotifyEndpoints.me}'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        if (profile != null) 'User-Agent': profile.userAgent,
      },
    );
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final images = (json['images'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    images.sort((a, b) => ((b['width'] as num?) ?? 0).compareTo((a['width'] as num?) ?? 0));
    return AccountProfile(
      id: json['id'] as String? ?? '',
      displayName: (json['display_name'] as String?)?.trim().isNotEmpty == true
          ? json['display_name'] as String
          : json['id'] as String? ?? '',
      avatarUrl: images.isEmpty ? '' : images.first['url'] as String? ?? '',
    );
  }

  static Uint8List _asUint8(List<int> bytes) => bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}

/// 账号展示信息。
class AccountProfile {
  /// 用户 ID（仅 /v1/me 返回；OAuth 登录时作为 username）。
  final String id;
  final String displayName;
  final String avatarUrl;

  const AccountProfile({this.id = '', required this.displayName, required this.avatarUrl});
}
