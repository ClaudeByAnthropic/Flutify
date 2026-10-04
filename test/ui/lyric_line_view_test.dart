import 'package:flutify_app/ui/screens/player/lyrics/lyric_line_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 单行歌词的译文渲染：有译文时多一行小字，间奏不渲染译文。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('译文在原文下方以小字渲染', (tester) async {
    await tester.pumpWidget(
      wrap(
        const LyricLineView(
          text: 'walking down the road',
          translation: '走在路上',
          distance: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('walking down the road'), findsOneWidget);
    expect(find.text('走在路上'), findsOneWidget);
    final original = tester.widget<Text>(find.text('walking down the road'));
    final translation = tester.widget<Text>(find.text('走在路上'));
    expect(
      translation.style?.fontSize,
      lessThan(original.style!.fontSize!),
      reason: '译文必须比原文小',
    );
  });

  testWidgets('间奏行只显示圆点，不渲染译文', (tester) async {
    await tester.pumpWidget(
      wrap(const LyricLineView(text: '', translation: '走在路上', distance: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('走在路上'), findsNothing);
  });

  testWidgets('无译文时不渲染第二行', (tester) async {
    await tester.pumpWidget(
      wrap(const LyricLineView(text: 'walking down the road', distance: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNWidgets(1));
  });
}
