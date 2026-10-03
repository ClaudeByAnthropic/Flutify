/// 应用信息（设置页「关于」、开源许可页使用）。
///
/// 版本号必须与 pubspec.yaml 的 `version` 一致，`test/core/app_info_test.dart` 会校验。
class AppInfo {
  AppInfo._();

  static const String name = 'Flutify';
  static const String version = '0.0.1';
  static const int build = 1;

  /// 「0.0.1 (1)」
  static String get displayVersion => '$version ($build)';
}
