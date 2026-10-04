import 'dart:io';

import 'auth_constants.dart';
import 'proto_codec.dart';

/// 向 Spotify 声明的客户端身份（目前只有 Windows 桌面端）。
///
/// 桌面 OAuth 数据请求共用 client_id、client-token 平台数据及请求头。
/// Web 播放另有独立身份；协议差异与未验证的账号风险见 docs/RISK_REVIEW.md。
enum SpotifyClientProfile {
  /// Windows 桌面端：桌面版浏览器 OAuth。
  desktop;

  String get clientId => SpotifyAuthConstants.desktopClientId;

  /// client-token 请求中的 client_version。
  String get clientVersion => SpotifyAuthConstants.desktopVersion;

  String get userAgent => SpotifyAuthConstants.desktopUserAgent;

  /// 访问内部接口（spclient / identity 等）时附带的客户端头。键统一小写，便于调用方覆盖。
  Map<String, String> get headers => const {
    'app-platform': SpotifyAuthConstants.desktopPlatform,
    'spotify-app-version': SpotifyAuthConstants.desktopVersion,
  };

  /// 写入 ConnectivitySdkData.platform_specific_data 的 desktop_windows=4（NativeDesktopWindowsData），
  /// 字段取值对齐 librespot（x64 进程）。
  ProtoWriter platformData() => ProtoWriter()
    ..message(
      4,
      ProtoWriter()
        ..int32(1, 10) // os_version：Windows 10/11 均报告 10
        ..int32(3, _windowsBuild()) // os_build
        ..int32(4, 2) // platform_id：VER_PLATFORM_WIN32_NT
        ..int32(6, 9) // unknown_value_6
        ..int32(7, 332) // image_file_machine：IMAGE_FILE_MACHINE_I386
        ..int32(8, 34404) // pe_machine：IMAGE_FILE_MACHINE_AMD64
        ..boolValue(10, true), // unknown_value_10
    );

  /// 本机 Windows 构建号（如 26200）；非 Windows 或解析失败时用 Windows 10 22H2 的 19045。
  static int _windowsBuild() {
    if (!Platform.isWindows) return 19045;
    final match = RegExp(
      r'Build (\d+)',
    ).firstMatch(Platform.operatingSystemVersion);
    return int.tryParse(match?.group(1) ?? '') ?? 19045;
  }
}
