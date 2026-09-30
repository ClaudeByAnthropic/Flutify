import 'package:flutify_app/core/utils/artwork_palette.dart';
import 'package:flutify_app/core/utils/error_placeholder.dart';
import 'package:flutify_app/main.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/ui/widgets/filter_pill.dart';
import 'package:flutify_app/ui/widgets/liquid_glass.dart';
import 'package:flutify_app/ui/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player_service.dart';

/// 关键交互流程的冒烟测试：布局溢出、断言失败等都会让测试失败。
void main() {
  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
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
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('mobile: open full player, lyrics and queue', (tester) async {
    await pumpApp(tester, const Size(400, 860));

    await tester.tap(find.text('Blinding Lights').first);
    await settle(tester);
    expect(find.text('正在播放歌单'), findsOneWidget);
    expect(find.text("Today's Top Hits"), findsWidgets);

    await tester.tap(find.byTooltip('歌词'));
    await settle(tester);
    expect(find.textContaining("blinded by the lights"), findsOneWidget);
    // 顶部信息胶囊 + 底部控制台两块液态玻璃；非当前行带模糊
    expect(find.byType(LiquidGlass), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsWidgets);
    // 0:00（前奏）时第一句也应清晰，并停在上下玻璃之间的正中
    final firstLine = find.text('Yeah, yeah');
    expect(find.ancestor(of: firstLine, matching: find.byType(ImageFiltered)), findsNothing);
    const sheetHeight = 860 * 0.92;
    const sheetTop = 860 - sheetHeight;
    const expectedCenter = sheetTop + (104 + (sheetHeight - 150)) / 2;
    expect(tester.getCenter(firstLine).dy, closeTo(expectedCenter, 24));
    await tester.tap(find.byTooltip('关闭').last);
    await settle(tester);

    await tester.tap(find.byTooltip('播放队列'));
    await settle(tester);
    expect(find.textContaining('接下来播放：'), findsOneWidget);
  });

  testWidgets('mobile: album page stays under the mini player', (tester) async {
    await pumpApp(tester, const Size(400, 860));

    final feed = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('After Hours'), 300, scrollable: feed);
    // 再上滑一段，确保卡片不被底部的迷你播放器 / 导航栏遮挡
    await tester.drag(feed, const Offset(0, -250));
    await settle(tester);
    await tester.tap(find.text('After Hours'));
    await settle(tester);

    expect(find.text('专辑 · 2020'), findsOneWidget);
    // 详情页压入 Tab 内部的 Navigator，迷你播放器依旧可见
    expect(find.text('Blinding Lights'), findsWidgets);
    expect(find.byType(MiniPlayer), findsOneWidget);
  });

  testWidgets('build errors render a quiet placeholder instead of the red screen', (tester) async {
    // 测试框架要求在测试体结束前恢复 ErrorWidget.builder（tearDown 太晚）
    final previous = ErrorWidget.builder;
    installErrorPlaceholder();
    try {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _Throws())));
      expect(tester.takeException(), isA<StateError>());
      expect(find.byIcon(Icons.hide_image_outlined), findsOneWidget);
    } finally {
      ErrorWidget.builder = previous;
    }
  });

  testWidgets('desktop: library filters, sort and grid view', (tester) async {
    await pumpApp(tester, const Size(1280, 800));

    // 侧栏标签与音乐库页标题同为「音乐库」，侧栏在前
    await tester.tap(find.text('音乐库').first);
    await settle(tester);
    expect(find.text('已点赞的歌曲'), findsWidgets);

    // 艺人条目的副标题也是「艺人」，只点筛选药丸
    await tester.tap(find.widgetWithText(FilterPill, '艺人'));
    await settle(tester);
    // 资料库列表 + 桌面播放栏（当前曲目艺人）各一处
    expect(find.text('The Weeknd'), findsWidgets);
    expect(find.text('Chill Hits'), findsNothing);

    await tester.tap(find.byTooltip('网格视图'));
    await settle(tester);
    expect(find.byType(GridView), findsOneWidget);

    await tester.tap(find.byTooltip('清除筛选'));
    await settle(tester);
    expect(find.text('Chill Hits'), findsOneWidget);
  });
}

/// 构建时必定抛异常的组件，用于验证全局错误占位。
class _Throws extends StatelessWidget {
  const _Throws();

  @override
  Widget build(BuildContext context) => throw StateError('boom');
}
