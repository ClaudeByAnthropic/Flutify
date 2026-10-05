import 'dart:math';

/// Spotify 鉴权链路的常量与设备标识。
///
/// 桌面 OAuth / AP 使用 Windows 桌面配置，Web 播放使用独立配置和令牌。
/// 桌面版本统一用于 client-token、User-Agent 和 AP 握手 / 登录。
class SpotifyAuthConstants {
  SpotifyAuthConstants._();

  /// 桌面版 OAuth 使用的 client_id（官方桌面客户端 / librespot OAuth 同款，来自 librespot config.rs）。
  static const String desktopClientId = '65b708073fc0480ea92a077233ca87bd';

  // 版本信息（Windows 桌面端，对应 Spotify.exe 1.3.1.234）
  static const String desktopVersion = '1.3.1.234.g59d6bf59';

  /// 桌面端数字版本号：主.次.修订(2 位).构建(5 位) 拼接，如 1.3.1.234 → 130100234。
  static const String desktopBuildNumber = '130100234';
  static const String desktopPlatform = 'Win32_x86_64';
  static const String desktopUserAgent = 'Spotify/$desktopBuildNumber $desktopPlatform/0 (PC desktop)';

  // 端点
  static const String clientTokenEndpoint = 'https://clienttoken.spotify.com/v1/clienttoken';

  /// 生成 40 位十六进制的设备 ID（Spotify device_id 格式）。
  static String generateDeviceId() {
    final rnd = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < 40; i++) {
      sb.write(rnd.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }
}
