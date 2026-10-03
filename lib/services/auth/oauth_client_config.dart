import 'auth_constants.dart';

/// 浏览器 OAuth 授权所用的客户端配置：桌面版 client_id、本机回调地址与权限范围。
///
/// 官方 Windows 桌面程序使用 `127.0.0.1` 与 `http://%s/login` 回环回调。
/// 这里采用同样的地址 / 路径，固定端口 8898 与 librespot 的已登记实现保持兼容。
/// 回调形式相同不代表客户端身份无法被识别。
class OAuthClientConfig {
  static const int redirectPort = 8898;

  final String clientId;
  final String redirectPath;
  final List<String> scopes;

  const OAuthClientConfig.desktop()
    : clientId = SpotifyAuthConstants.desktopClientId,
      redirectPath = '/login',
      scopes = desktopScopes;

  String get redirectUri => 'http://127.0.0.1:$redirectPort$redirectPath';

  /// 桌面版 client_id 可申请的完整权限（含内部接口所需的 user-modify / user-personalized 等）。
  static const List<String> desktopScopes = [
    'app-remote-control',
    'playlist-modify',
    'playlist-modify-private',
    'playlist-modify-public',
    'playlist-read',
    'playlist-read-collaborative',
    'playlist-read-private',
    'streaming',
    'ugc-image-upload',
    'user-follow-modify',
    'user-follow-read',
    'user-library-modify',
    'user-library-read',
    'user-modify',
    'user-modify-playback-state',
    'user-modify-private',
    'user-personalized',
    'user-read-birthdate',
    'user-read-currently-playing',
    'user-read-email',
    'user-read-play-history',
    'user-read-playback-position',
    'user-read-playback-state',
    'user-read-private',
    'user-read-recently-played',
    'user-top-read',
  ];
}
