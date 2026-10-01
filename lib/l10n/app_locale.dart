import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../models/app_preferences.dart';
import 'app_localizations.dart';

/// App 语言配置（MaterialApp 使用）。
///
/// 规则：
/// * 默认简体中文（zh_CN）；设置页可改为跟随系统或固定英文（[localeFor]）。
///   跟随系统时由 MaterialApp 在 zh / en 中挑最接近的，其余语言回退到中文（列表第一项）。
/// * Global*Localizations 让系统组件（日期选择器、文本选择菜单、Tooltip、返回按钮等）同样随之切换。
/// * 实际生效的语言由 [resolved] 回写，决定请求 Spotify 时的 Accept-Language。
class AppLocale {
  AppLocale._();

  /// 偏好对应的固定语言；跟随系统时返回 null，交给 MaterialApp 按系统语言解析。
  static Locale? localeFor(AppLanguage language) => switch (language) {
    AppLanguage.system => null,
    AppLanguage.zh => const Locale('zh', 'CN'),
    AppLanguage.en => const Locale('en'),
  };

  static String _spotifyLanguage = 'zh-CN';

  /// 请求 Spotify 接口时的 Accept-Language（与官方客户端的语言包名一致：zh-CN 简体、en 英文）。
  /// 服务端据此本地化主页问候语、分区标题、筛选标签等文案；不带时一律返回英文。
  static String get spotifyLanguage => _spotifyLanguage;

  /// 界面实际使用的语言确定后调用（MaterialApp.builder 内）；返回值表示是否发生了变化。
  static bool resolved(Locale locale) {
    final next = locale.languageCode == 'zh' ? 'zh-CN' : 'en';
    if (next == _spotifyLanguage) return false;
    _spotifyLanguage = next;
    return true;
  }

  /// 支持的全部语言（与生成的 AppLocalizations 一致）；zh 在前，系统语言都不匹配时回退到中文。
  static const List<Locale> supportedLocales = [Locale('zh'), Locale('en')];

  /// App 文案 + Material / Cupertino / Widgets 系统文案。
  static const List<LocalizationsDelegate<dynamic>> delegates = [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];
}
