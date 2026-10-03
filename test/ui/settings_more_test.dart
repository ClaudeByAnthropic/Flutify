import 'package:flutify_app/core/constants/app_info.dart';
import 'package:flutify_app/core/utils/artwork_palette.dart';
import 'package:flutify_app/core/utils/byte_size.dart';
import 'package:flutify_app/main.dart';
import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutify_app/services/protocol/audio_cache_store.dart';
import 'package:flutify_app/services/protocol/track_audio_loader.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/ui/screens/main_shell.dart';
import 'package:flutify_app/ui/screens/settings/settings_screen.dart';
import 'package:flutify_app/ui/screens/settings/widgets/shortcuts_dialog.dart';
import 'package:flutify_app/ui/navigation/tab_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_audio_player_service.dart';
import '../fakes/fake_spotify_api_service.dart';
import '../fakes/fake_track_audio_source.dart';

/// 带缓存管理能力的加载器替身（真实 TrackAudioLoader 同时实现两个接口）。
class _FakeCachingLoader extends FakeTrackAudioSource implements AudioCacheStore {
  int bytes = 3 * ByteSize.mb;

  @override
  int maxCacheBytes = 512 * ByteSize.mb;

  @override
  Future<int> sizeBytes() async => bytes;

  @override
  Future<int> clear() async {
    final freed = bytes;
    bytes = 0;
    return freed;
  }
}

/// 设置页新增分组端到端：语言 / 歌词 / 播放 / Connect / 存储 / 隐私 / 启动 / 关于。
/// 每项都验证「点选即生效 + 已持久化」。
void main() {
  late StorageService storage;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // 高度给足：移动端设置页是懒加载单列，一屏放下全部分组，测试无需滚动
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(500, 5200),
    TrackAudioSource? loader,
    Future<void> Function(StorageService storage)? seed,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ArtworkPalette.enabled = false;

    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.init();
    await seed?.call(storage);
    await tester.pumpWidget(
      FlutifyApp(
        key: UniqueKey(),
        storageService: storage,
        audioEngine: FakeAudioPlayerService(),
        emePlayer: EmePlayer(),
        spotifyApiService: FakeSpotifyApiService(storage),
        trackAudioLoader: loader ?? FakeTrackAudioSource(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openSettings(WidgetTester tester) async {
    Navigator.of(
      tester.element(find.byType(MainShell)),
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await settle(tester);
  }

  AppPreferences savedPrefs() => AppPreferences.decode(storage.preferencesJson);

  int currentTab(WidgetTester tester) => tester
      .widget<IndexedStack>(
        find.ancestor(of: find.byType(TabNavigator).first, matching: find.byType(IndexedStack)).first,
      )
      .index!;

  testWidgets('language switches the UI locale and persists', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    await tapText(tester, 'English');
    final context = tester.element(find.byType(SettingsScreen));
    expect(Localizations.localeOf(context).languageCode, 'en');
    expect(find.text('Language'), findsWidgets);
    expect(savedPrefs().language, AppLanguage.en);

    await tapText(tester, '中文');
    expect(find.text('语言'), findsWidgets);
    expect(savedPrefs().language, AppLanguage.zh);
  });

  testWidgets('lyrics, playback and Connect options apply and persist', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    await tapText(tester, '居中');
    expect(savedPrefs().lyricsAlign, LyricsAlign.center);

    await tapText(tester, '音量均衡');
    expect(storage.normalizeVolume, isTrue);

    // 关闭 Connect：提前量滑杆随之隐藏
    expect(find.text('远程歌词提前'), findsOneWidget);
    await tapText(tester, '启用 Spotify Connect');
    expect(savedPrefs().connectEnabled, isFalse);
    expect(find.text('远程歌词提前'), findsNothing);
  });

  testWidgets('storage: usage, limit change and clear', (tester) async {
    final loader = _FakeCachingLoader();
    await pumpApp(tester, loader: loader);
    await openSettings(tester);

    expect(find.text('已用 3 MB，上限 512 MB'), findsOneWidget);

    await tapText(tester, '1 GB');
    expect(storage.audioCacheLimitMb, 1024);
    expect(loader.maxCacheBytes, ByteSize.gb);
    expect(find.text('已用 3 MB，上限 1 GB'), findsOneWidget);

    await tapText(tester, '清除音频缓存');
    expect(find.text('清除音频缓存？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await settle(tester);
    expect(loader.bytes, 0);
    expect(find.text('已释放 3 MB'), findsOneWidget);
    expect(find.text('已用 0 KB，上限 1 GB'), findsOneWidget);
  });

  testWidgets('network: proxy mode and manual server persist', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    expect(savedPrefs().proxyMode, ProxyMode.system);
    await tapText(tester, '不使用');
    expect(savedPrefs().proxyMode, ProxyMode.none);
    expect(find.byKey(const ValueKey('proxy-host')), findsNothing);

    await tapText(tester, '手动');
    expect(savedPrefs().proxyMode, ProxyMode.manual);

    // 地址框直接粘贴 host:port，自动拆分端口
    await tester.enterText(find.byKey(const ValueKey('proxy-host')), '127.0.0.1:7890');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(savedPrefs().proxyHost, '127.0.0.1');
    expect(savedPrefs().proxyPort, 7890);

    // 无效端口：提示且不覆盖已保存的值
    await tester.enterText(find.byKey(const ValueKey('proxy-port')), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('请填写有效的地址和 1–65535 之间的端口'), findsOneWidget);
    expect(savedPrefs().proxyPort, 7890);
  });

  testWidgets('privacy: clearing search history empties it', (tester) async {
    await pumpApp(tester, seed: (s) => s.addRecentSearch('lofi'));
    await openSettings(tester);

    await tapText(tester, '清除搜索记录');
    expect(storage.recentSearches, isEmpty);
    expect(find.text('没有搜索记录'), findsOneWidget);
    expect(find.text('已清除'), findsOneWidget);
  });

  testWidgets('start page: library and last position', (tester) async {
    await pumpApp(
      tester,
      seed: (s) => s.setPreferencesJson(const AppPreferences(startPage: StartPage.library).encode()),
    );
    expect(currentTab(tester), 2);

    await pumpApp(
      tester,
      seed: (s) async {
        await s.setPreferencesJson(const AppPreferences(startPage: StartPage.last).encode());
        await s.setLastTab(1);
      },
    );
    expect(currentTab(tester), 1);
  });

  testWidgets('desktop about: version and keyboard shortcuts dialog', (tester) async {
    await pumpApp(tester, size: const Size(1440, 2400));
    await openSettings(tester);

    expect(find.text(AppInfo.displayVersion), findsOneWidget);
    await tapText(tester, '键盘快捷键');
    expect(find.byType(ShortcutsDialog), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
  });
}
