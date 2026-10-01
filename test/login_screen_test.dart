import 'package:flutify_app/core/utils/artwork_palette.dart';
import 'package:flutify_app/main.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/ui/screens/auth/login_screen.dart';
import 'package:flutify_app/ui/screens/auth/widgets/login_hero.dart';
import 'package:flutify_app/ui/screens/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player_service.dart';

/// 登录页在小屏手机上的冒烟测试：只有「在浏览器中登录」一种方式、无布局溢出、可关闭。
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('login: single browser sign-in page renders and closes', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ArtworkPalette.enabled = false;

    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    await tester.pumpWidget(
      FlutifyApp(
        storageService: storage,
        audioPlayerService: FakeAudioPlayerService(),
        spotifyApiService: SpotifyApiService(storage),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    LoginScreen.open(tester.element(find.byType(MainShell)));
    await settle(tester);

    expect(find.byType(LoginHero), findsOneWidget);
    expect(find.text('登录 Spotify'), findsOneWidget);
    expect(find.text('在浏览器中登录'), findsOneWidget);
    // 其他登录方式已移除
    expect(find.text('账号密码'), findsNothing);
    expect(find.text('更多方式'), findsNothing);

    await tester.tap(find.byTooltip('关闭'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
