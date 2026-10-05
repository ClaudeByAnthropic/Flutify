import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/widgets/liquid_artwork_background.dart';

void main() {
  Widget host({required bool animate}) => MaterialApp(
    home: SizedBox.expand(
      child: LiquidArtworkBackground(
        imageUrl: '',
        fallback: Colors.indigo,
        animate: animate,
      ),
    ),
  );

  testWidgets('can remove an initially paused background without starting a ticker', (tester) async {
    await tester.pumpWidget(host(animate: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('keeps drawing while animating and stops when paused', (
    tester,
  ) async {
    await tester.pumpWidget(host(animate: true));
    await tester.pump(const Duration(milliseconds: 100));
    // 节流后的 ticker 仍在持续要帧
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(host(animate: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);

    // 暂停后可以再次恢复
    await tester.pumpWidget(host(animate: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
