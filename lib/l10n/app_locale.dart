import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_localizations.dart';

/// App 语言配置（MaterialApp 使用）。
///
/// 规则：
/// * 界面固定为简体中文（zh_CN），不跟随系统语言；英文 ARB 仅作为备用翻译保持同步。
/// * Global*Localizations 让系统组件（日期选择器、文本选择菜单、Tooltip、返回按钮等）同样显示中文。
class AppLocale {
  AppLocale._();

  /// 当前界面语言：简体中文。
  static const Locale locale = Locale('zh', 'CN');

  /// 生成的 AppLocalizations 支持的全部语言（zh / en）。
  static const List<Locale> supportedLocales = AppLocalizations.supportedLocales;

  /// App 文案 + Material / Cupertino / Widgets 系统文案。
  static const List<LocalizationsDelegate<dynamic>> delegates = [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];
}
