import 'package:flutify_app/l10n/app_locale.dart';
import 'package:flutify_app/services/auth/web_token_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/ui/screens/settings/widgets/web_login_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全曲播放（Web 登录）卡片的响应式排版：窄屏（竖屏手机）按钮下沉、文字不折行。
///
/// 只挂载卡片本身并给定宽度，不拉起整个 App（避免无关的周期定时器）。
void main() {
  const title = '全曲播放（Web 登录）';

  Future<void> pumpCard(
    WidgetTester tester, {
    required double width,
    bool signedIn = true,
  }) async {
    SharedPreferences.setMockInitialValues(
      signedIn ? {'sp_dc': 'test-dc'} : {},
    );
    final storage = await StorageService.init();
    await tester.pumpWidget(
      Provider<WebTokenService>.value(
        value: WebTokenService(storage),
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocale.supportedLocales,
          localizationsDelegates: AppLocale.delegates,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: const WebLoginCard()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('竖屏手机：标题与副标题单行，操作按钮下沉到文字下方', (tester) async {
    // 先取单行基线（宽卡片一定单行），再对比竖屏，避免写死字号高度。
    await pumpCard(tester, width: 700);
    final wideTitle = tester.getRect(find.text(title)).height;
    final wideSubtitle = tester.getRect(find.text('已就绪，可以播放完整曲目')).height;

    await pumpCard(tester, width: 328);
    expect(tester.takeException(), isNull);

    final titleRect = tester.getRect(find.text(title));
    final subtitleRect = tester.getRect(find.text('已就绪，可以播放完整曲目'));
    final loginRect = tester.getRect(find.text('重新登录'));

    expect(titleRect.height, lessThan(wideTitle * 1.5));
    expect(subtitleRect.height, lessThan(wideSubtitle * 1.5));
    expect(loginRect.top, greaterThan(titleRect.bottom));
  });

  testWidgets('宽卡片：维持单行布局，按钮在文字右侧', (tester) async {
    await pumpCard(tester, width: 700);
    expect(tester.takeException(), isNull);

    final titleRect = tester.getRect(find.text(title));
    final loginRect = tester.getRect(find.text('重新登录'));
    expect(loginRect.left, greaterThan(titleRect.right));
  });

  testWidgets('竖屏未登录：单个按钮同样下沉，标题不折行', (tester) async {
    await pumpCard(tester, width: 700, signedIn: false);
    final wideTitle = tester.getRect(find.text(title)).height;

    await pumpCard(tester, width: 328, signedIn: false);
    expect(tester.takeException(), isNull);

    final titleRect = tester.getRect(find.text(title));
    final loginRect = tester.getRect(find.text('Web 登录'));
    expect(titleRect.height, lessThan(wideTitle * 1.5));
    expect(loginRect.top, greaterThan(titleRect.bottom));
  });
}
