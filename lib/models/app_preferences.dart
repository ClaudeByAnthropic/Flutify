import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 界面语言：跟随系统 / 固定中文 / 固定英文。
enum AppLanguage { system, zh, en }

/// 启动时打开的页面；[last] 为上次关闭时所在的 Tab。
enum StartPage { home, library, last }

/// 歌词行的对齐方式。
enum LyricsAlign { left, center }

/// 非外观类的界面偏好（外观见 `AppearanceSettings`，播放类偏好由 PlaybackProvider 持有）。
///
/// 不可变；整体序列化为一段 JSON 存在 `app_prefs` 键下。
/// 解析规则：缺失 / 类型不对 / 越界的字段一律回退到默认值并夹到合法范围，
/// 旧版本或手改坏的数据不会导致启动失败。
@immutable
class AppPreferences {
  final AppLanguage language;

  /// 歌词字号倍率（乘在各歌词视图自身的基准字号上）。
  final double lyricsScale;
  final LyricsAlign lyricsAlign;

  /// 非当前行的模糊强度倍率：0 = 不模糊，1 = 默认（Apple Music 观感），2 = 加倍。
  final double lyricsBlur;

  final StartPage startPage;

  /// 桌面端：记住窗口大小与位置（含最大化状态）。
  final bool rememberWindow;

  /// 是否接入 Spotify Connect（关闭后不再显示 / 遥控其他设备）。
  final bool connectEnabled;

  /// 远程播放时歌词的提前量（毫秒）：正数让歌词更早切行，负数推迟。只影响歌词，不影响进度条。
  final int remoteLyricsLeadMs;

  const AppPreferences({
    this.language = AppLanguage.zh,
    this.lyricsScale = 1.0,
    this.lyricsAlign = LyricsAlign.left,
    this.lyricsBlur = 1.0,
    this.startPage = StartPage.home,
    this.rememberWindow = true,
    this.connectEnabled = true,
    this.remoteLyricsLeadMs = 0,
  });

  static const AppPreferences defaults = AppPreferences();

  static const double minLyricsScale = 0.8;
  static const double maxLyricsScale = 1.4;
  static const double maxLyricsBlur = 2.0;
  static const int maxRemoteLyricsLeadMs = 2000;

  AppPreferences copyWith({
    AppLanguage? language,
    double? lyricsScale,
    LyricsAlign? lyricsAlign,
    double? lyricsBlur,
    StartPage? startPage,
    bool? rememberWindow,
    bool? connectEnabled,
    int? remoteLyricsLeadMs,
  }) {
    return AppPreferences(
      language: language ?? this.language,
      lyricsScale: lyricsScale ?? this.lyricsScale,
      lyricsAlign: lyricsAlign ?? this.lyricsAlign,
      lyricsBlur: lyricsBlur ?? this.lyricsBlur,
      startPage: startPage ?? this.startPage,
      rememberWindow: rememberWindow ?? this.rememberWindow,
      connectEnabled: connectEnabled ?? this.connectEnabled,
      remoteLyricsLeadMs: remoteLyricsLeadMs ?? this.remoteLyricsLeadMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'language': language.name,
    'lyricsScale': lyricsScale,
    'lyricsAlign': lyricsAlign.name,
    'lyricsBlur': lyricsBlur,
    'startPage': startPage.name,
    'rememberWindow': rememberWindow,
    'connectEnabled': connectEnabled,
    'remoteLyricsLeadMs': remoteLyricsLeadMs,
  };

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    double number(Object? v, double fallback, double min, double max) =>
        v is num && v.isFinite ? v.toDouble().clamp(min, max) : fallback;
    bool flag(Object? v, bool fallback) => v is bool ? v : fallback;

    const d = defaults;
    final lead = json['remoteLyricsLeadMs'];
    return AppPreferences(
      language: pick(AppLanguage.values, json['language'], d.language),
      lyricsScale: number(json['lyricsScale'], d.lyricsScale, minLyricsScale, maxLyricsScale),
      lyricsAlign: pick(LyricsAlign.values, json['lyricsAlign'], d.lyricsAlign),
      lyricsBlur: number(json['lyricsBlur'], d.lyricsBlur, 0, maxLyricsBlur),
      startPage: pick(StartPage.values, json['startPage'], d.startPage),
      rememberWindow: flag(json['rememberWindow'], d.rememberWindow),
      connectEnabled: flag(json['connectEnabled'], d.connectEnabled),
      remoteLyricsLeadMs: lead is int ? lead.clamp(-maxRemoteLyricsLeadMs, maxRemoteLyricsLeadMs) : 0,
    );
  }

  /// 从持久化字符串解析；空串或损坏时返回默认值。
  factory AppPreferences.decode(String raw) {
    if (raw.isEmpty) return defaults;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? AppPreferences.fromJson(json) : defaults;
    } catch (_) {
      return defaults;
    }
  }

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is AppPreferences &&
      other.language == language &&
      other.lyricsScale == lyricsScale &&
      other.lyricsAlign == lyricsAlign &&
      other.lyricsBlur == lyricsBlur &&
      other.startPage == startPage &&
      other.rememberWindow == rememberWindow &&
      other.connectEnabled == connectEnabled &&
      other.remoteLyricsLeadMs == remoteLyricsLeadMs;

  @override
  int get hashCode => Object.hash(
    language,
    lyricsScale,
    lyricsAlign,
    lyricsBlur,
    startPage,
    rememberWindow,
    connectEnabled,
    remoteLyricsLeadMs,
  );
}
