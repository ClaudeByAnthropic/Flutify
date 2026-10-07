import 'dart:ui' as ui;

import 'package:flutify_app/ui/widgets/liquid_artwork_painter.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ui.Image image;

  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 128, 128),
      ui.Paint()..color = const ui.Color(0xFFE0457B),
    );
    image = await recorder.endRecording().toImage(128, 128);
  });

  /// 用绘制器画到一张图上，返回不透明像素数。
  Future<int> paintedPixels(Size size, {double fade = 1, ui.Image? art}) async {
    final painter = LiquidArtworkPainter(
      phase: ValueNotifier(0.25),
      fade: AlwaysStoppedAnimation(fade),
      image: art,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), size);
    final result = await recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
    final bytes = (await result.toByteData())!;
    var opaque = 0;
    for (var i = 3; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) > 0) opaque++;
    }
    return opaque;
  }

  test('paints blurred artwork across wide and tall layouts', () async {
    for (final size in const [Size(1600, 900), Size(390, 844)]) {
      expect(await paintedPixels(size, art: image), greaterThan(0), reason: '$size');
    }
  });

  test('paints nothing before the artwork loads or while fully faded out', () async {
    const size = Size(400, 300);
    expect(await paintedPixels(size), 0);
    expect(await paintedPixels(size, art: image, fade: 0), 0);
  });
}
