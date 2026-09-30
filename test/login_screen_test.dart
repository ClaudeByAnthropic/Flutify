import 'package:flutify_app/core/utils/artwork_palette.dart';
import 'package:flutify_app/main.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/ui/screens/auth/login_screen.dart';
import 'package:flutify_app/ui/screens/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player_service.dart';

/// 登录页各阶段在小屏手机上的冒烟测试：切换不报错、无布局溢出、返回键逐级后退。
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('login: every method stage renders and back navigation steps out', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ArtworkPalette.enabled = false;

    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    await tester.pumpWidget(FlutifyApp(
      storageService: storage,
      audioPlayerService: FakeAudioPlayerService(),
      spotifyApiService: SpotifyApiService(storage),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    LoginScreen.open(tester.element(find.byType(MainShell)));
    await settle(tester);

    // 默认：在浏览器中登录（桌面版授权）
    expect(find.text('登录 Spotify'), findsOneWidget);
    expect(find.text('在浏览器中登录'), findsOneWidget);

    // 账号密码 → 手机号 → 返回直接回到默认页
    await tester.tap(find.text('账号密码'));
    await settle(tester);
    expect(find.text('账号密码登录'), findsOneWidget);
    await tester.ensureVisible(find.text('手机号'));
    await tester.tap(find.text('手机号'));
    await settle(tester);
    expect(find.text('手机号登录'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await settle(tester);
    expect(find.text('在浏览器中登录'), findsOneWidget);

    // "更多方式"面板中的方式
    Future<void> openMore(String title) async {
      await tester.ensureVisible(find.text('更多方式'));
      await tester.tap(find.text('更多方式'));
      await settle(tester);
      await tester.tap(find.text(title));
      await settle(tester);
    }

    await openMore('登录链接 / 一次性令牌');
    expect(find.text('使用登录链接'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await settle(tester);

    await openMore('导入已保存凭据');
    expect(find.text('验证并导入'), findsOneWidget);
    await tester.tap(find.text('手动填写'));
    await settle(tester);
    expect(find.text('设备 ID（可选）'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await settle(tester);

    await openMore('开发者应用授权');
    expect(find.text('在浏览器中授权'), findsOneWidget);
    // 无效 Client ID 在本地即被拦截并提示
    await tester.tap(find.text('在浏览器中授权'));
    await settle(tester);
    expect(find.textContaining('32 位十六进制'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await settle(tester);

    // 根页面：关闭登录页
    await tester.tap(find.byTooltip('关闭'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
