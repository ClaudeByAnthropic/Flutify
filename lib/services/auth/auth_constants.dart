import 'dart:math';

/// Spotify 鉴权链路的常量与设备标识。
///
/// 两套客户端身份：
/// - Android 移动端：Login5 直连（密码 / 短信 / 一次性令牌 / 导入凭据），取值对齐 librespot；
/// - Windows 桌面端：浏览器 OAuth（默认登录方式），client_id 为桌面版（keymaster），
///   版本号取自本机安装的官方桌面版，使 client-token、User-Agent 与令牌所属客户端保持一致。
class SpotifyAuthConstants {
  SpotifyAuthConstants._();

  // 各平台官方 client_id（来自 librespot config.rs）
  static const String androidClientId = '9a8d2f0ce77a4e248bb71fefcb557637';
  static const String iosClientId = '58bd3c95768941ea9eb4350aaa033eb3';
  static const String keymasterClientId = '65b708073fc0480ea92a077233ca87bd';

  /// Login5 链路伪装为 Android 移动端。
  static const String clientId = androidClientId;

  /// 桌面版 OAuth 使用的 client_id（官方桌面客户端 / librespot OAuth 同款）。
  static const String desktopClientId = keymasterClientId;

  // 版本信息（Windows 桌面端，对应 Spotify.exe 1.3.1.234）
  static const String desktopVersion = '1.3.1.234.g59d6bf59';

  /// 桌面端数字版本号：主.次.修订(2 位).构建(5 位) 拼接，如 1.3.1.234 → 130100234。
  static const String desktopBuildNumber = '130100234';
  static const String desktopPlatform = 'Win32_x86_64';
  static const String desktopUserAgent = 'Spotify/$desktopBuildNumber $desktopPlatform/0 (PC desktop)';

  // 端点
  static const String clientTokenEndpoint = 'https://clienttoken.spotify.com/v1/clienttoken';
  static const String login5Endpoint = 'https://login5.spotify.com/v3/login';

  // 版本信息（Android 移动端）
  static const String mobileVersion = '8.9.82.620';
  static const int androidApiVersion = 31;
  static const String androidOsVersion = '12';

  /// Android User-Agent，格式对齐 librespot：`Spotify/<ver> Android/<os> (<device>)`。
  static const String userAgent = 'Spotify/$mobileVersion Android/$androidApiVersion (Pixel)';

  // ConnectivitySdkData 里的机型伪装
  static const String deviceName = 'Pixel';
  static const String modelStr = 'GF5KQ';
  static const String vendor = 'Google';

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

/// Login5 服务端错误码（login5.proto 的 LoginError 枚举）。
enum Login5Error {
  unknown(0),
  invalidCredentials(1),
  badRequest(2),
  unsupportedLoginProtocol(3),
  timeout(4),
  unknownIdentifier(5),
  tooManyAttempts(6),
  invalidPhoneNumber(7),
  tryAgainLater(8);

  final int code;
  const Login5Error(this.code);

  static Login5Error fromCode(int code) =>
      Login5Error.values.firstWhere((e) => e.code == code, orElse: () => Login5Error.unknown);

  /// 面向用户的中文提示。
  String get message => switch (this) {
        Login5Error.invalidCredentials => '账号或密码错误',
        Login5Error.badRequest => '请求格式有误（可能是协议已变化）',
        Login5Error.unsupportedLoginProtocol => '该登录方式已不受支持',
        Login5Error.timeout => '登录超时，请重试',
        Login5Error.unknownIdentifier => '找不到该账号',
        Login5Error.tooManyAttempts => '尝试次数过多，请稍后再试',
        Login5Error.invalidPhoneNumber => '手机号无效',
        Login5Error.tryAgainLater => '请稍后再试',
        Login5Error.unknown => '登录失败（未知原因）',
      };
}

/// 服务端要求了原生协议无法完成的挑战（如 reCAPTCHA 网页人机验证）。
class Login5UnsupportedChallenge implements Exception {
  const Login5UnsupportedChallenge();

  @override
  String toString() => '服务端要求网页人机验证，当前方式无法完成。请改用「在浏览器中登录」';
}

/// 登录失败（携带服务端错误码）。
class Login5Failure implements Exception {
  final Login5Error error;
  Login5Failure(this.error);

  @override
  String toString() => error.message;
}
