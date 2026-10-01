import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

/// 偏好的序列化：往返一致；坏数据 / 越界值回退或夹紧，不会导致启动失败。
void main() {
  test('encode / decode round-trips every field', () {
    const prefs = AppPreferences(
      language: AppLanguage.en,
      lyricsScale: 1.2,
      lyricsAlign: LyricsAlign.center,
      lyricsBlur: 0,
      startPage: StartPage.last,
      rememberWindow: false,
      connectEnabled: false,
      remoteLyricsLeadMs: -300,
      proxyMode: ProxyMode.manual,
      proxyHost: '10.0.0.2',
      proxyPort: 8080,
      lyricsFallback: false,
      taskbarLyrics: true,
      taskbarLyricsColor: TaskbarLyricsColor.custom,
      taskbarLyricsCustomColor: 0xFF336699,
      taskbarLyricsOpacity: 60,
    );
    expect(AppPreferences.decode(prefs.encode()), prefs);
  });

  test('taskbar lyrics: off by default, bad values are sanitised', () {
    expect(AppPreferences.defaults.taskbarLyrics, isFalse);
    expect(AppPreferences.defaults.lyricsFallback, isTrue);
    final prefs = AppPreferences.fromJson({'taskbarLyricsColor': 'rainbow', 'taskbarLyricsOpacity': 3});
    expect(prefs.taskbarLyricsColor, TaskbarLyricsColor.auto);
    expect(prefs.taskbarLyricsOpacity, AppPreferences.minTaskbarLyricsOpacity);
  });

  test('proxy fields: unknown mode falls back to system, bad port to 0', () {
    final prefs = AppPreferences.fromJson({'proxyMode': 'socks', 'proxyHost': '  h  ', 'proxyPort': 70000});
    expect(prefs.proxyMode, ProxyMode.system);
    expect(prefs.proxyHost, 'h');
    expect(prefs.proxyPort, 0);
  });

  test('empty or corrupt data falls back to defaults', () {
    expect(AppPreferences.decode(''), AppPreferences.defaults);
    expect(AppPreferences.decode('{not json'), AppPreferences.defaults);
    expect(AppPreferences.decode('[1, 2]'), AppPreferences.defaults);
  });

  test('unknown enums, wrong types and out-of-range values are sanitised', () {
    final prefs = AppPreferences.fromJson({
      'language': 'klingon',
      'lyricsScale': 9.0,
      'lyricsAlign': 42,
      'lyricsBlur': -3,
      'startPage': null,
      'rememberWindow': 'yes',
      'connectEnabled': false,
      'remoteLyricsLeadMs': 99999,
    });
    expect(prefs.language, AppPreferences.defaults.language);
    expect(prefs.lyricsScale, AppPreferences.maxLyricsScale);
    expect(prefs.lyricsAlign, LyricsAlign.left);
    expect(prefs.lyricsBlur, 0);
    expect(prefs.startPage, StartPage.home);
    expect(prefs.rememberWindow, isTrue);
    expect(prefs.connectEnabled, isFalse);
    expect(prefs.remoteLyricsLeadMs, AppPreferences.maxRemoteLyricsLeadMs);
  });

  test('copyWith changes only the given field', () {
    final prefs = AppPreferences.defaults.copyWith(lyricsScale: 0.9);
    expect(prefs.lyricsScale, 0.9);
    expect(prefs.copyWith(lyricsScale: 1.0), AppPreferences.defaults);
  });
}
