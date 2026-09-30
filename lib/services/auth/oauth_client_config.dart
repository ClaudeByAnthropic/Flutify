import 'auth_constants.dart';

/// 一次 OAuth 授权所用的客户端配置：client_id、本机回调地址与权限范围。
///
/// - [OAuthClientConfig.desktop]：桌面版 client_id，无需用户申请开发者应用；回调
///   `http://127.0.0.1:8898/login` 与权限范围对齐 librespot 的 OAuth 实现（已在该 client_id 下登记）；
/// - [OAuthClientConfig.developer]：用户自己在 developer.spotify.com 创建的应用，只能访问公开 Web API。
class OAuthClientConfig {
  static const int redirectPort = 8898;

  final String clientId;
  final String redirectPath;
  final List<String> scopes;

  /// 是否为桌面版授权（决定会话的客户端身份与续期方式）。
  final bool isDesktop;

  const OAuthClientConfig._({
    required this.clientId,
    required this.redirectPath,
    required this.scopes,
    required this.isDesktop,
  });

  const OAuthClientConfig.desktop()
      : this._(
          clientId: SpotifyAuthConstants.desktopClientId,
          redirectPath: '/login',
          scopes: desktopScopes,
          isDesktop: true,
        );

  const OAuthClientConfig.developer(String clientId)
      : this._(clientId: clientId, redirectPath: '/callback', scopes: developerScopes, isDesktop: false);

  String get redirectUri => 'http://127.0.0.1:$redirectPort$redirectPath';

  /// 开发者应用的回调地址（需用户在开发者后台原样登记）。
  static const String developerRedirectUri = 'http://127.0.0.1:$redirectPort/callback';

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

  /// 开发者应用可申请的公开权限，覆盖 App 现有功能。
  static const List<String> developerScopes = [
    'user-read-private',
    'user-read-email',
    'user-library-read',
    'user-library-modify',
    'user-follow-read',
    'user-follow-modify',
    'user-top-read',
    'user-read-recently-played',
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
    'playlist-read-private',
    'playlist-read-collaborative',
    'playlist-modify-private',
    'playlist-modify-public',
    'streaming',
  ];
}
