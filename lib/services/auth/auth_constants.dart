import 'dart:math';

/// Spotify 鉴权链路的常量与设备标识。
///
/// 只有一种客户端身份：Windows 桌面端浏览器 OAuth。client_id 为桌面版（keymaster），
/// 版本号取自本机安装的官方桌面版，使 client-token、User-Agent 与令牌所属客户端保持一致。
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
