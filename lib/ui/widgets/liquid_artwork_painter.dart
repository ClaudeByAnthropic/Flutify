import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// 一块旋转封面的参数：位置、放大倍数、相对相位的角速度与初始角、不透明度。
class LiquidBlob {
  final Alignment alignment;
  final double scale;
  final double speed;
  final double offset;
  final double opacity;

  const LiquidBlob(
    this.alignment, {
    required this.scale,
    required this.speed,
    required this.offset,
    this.opacity = 1,
  });
}

/// 流动封面背景的绘制器：在低分辨率离屏画布上完成「三块封面 + 大模糊」，再放大铺满。
///
/// 规则：
/// - σ=70 的模糊会抹掉所有高频细节，因此在 1/[downscale] 分辨率下模糊、再双线性放大，
///   与全分辨率结果肉眼不可分，但像素工作量约为原来的 1/64；
/// - 离屏画布四周多留 3σ 的余量，让屏幕外的封面像原来一样参与边缘模糊，
///   边缘不会比原来更暗或更「透」；
/// - 模糊用 decal：内容之外是透明，露出下面的主色底，与原 ImageFiltered 一致。
class LiquidArtworkPainter extends CustomPainter {
  static const double sigma = 70;
  static const double downscale = 8;

  static const List<LiquidBlob> blobs = [
    LiquidBlob(Alignment(-0.6, -0.5), scale: 1.9, speed: 1, offset: 0),
    LiquidBlob(Alignment(0.7, 0.2), scale: 1.6, speed: -1.3, offset: 1.2),
    LiquidBlob(Alignment(-0.3, 0.8), scale: 1.4, speed: 0.7, offset: 2.4, opacity: 0.8),
  ];

  final ValueListenable<double> phase;
  final Animation<double> fade;
  final ui.Image? image;

  LiquidArtworkPainter({required this.phase, required this.fade, required this.image})
      : super(repaint: Listenable.merge([phase, fade]));

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    final alpha = fade.value;
    if (image == null || alpha <= 0 || size.isEmpty) return;

    // 1. 离屏小画布：逻辑坐标 (x, y) 映射到 ((x + pad) / k, (y + pad) / k)
    const pad = sigma * 3;
    final w = ((size.width + pad * 2) / downscale).ceil();
    final h = ((size.height + pad * 2) / downscale).ceil();
    final recorder = ui.PictureRecorder();
    final offscreen = Canvas(recorder);
    offscreen.saveLayer(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma / downscale,
          sigmaY: sigma / downscale,
          tileMode: TileMode.decal,
        ),
    );
    offscreen
      ..scale(1 / downscale)
      ..translate(pad, pad);
    final t = phase.value * 2 * math.pi;
    for (final blob in blobs) {
      _paintBlob(offscreen, size, image, blob, t * blob.speed + blob.offset, alpha);
    }
    offscreen.restore();

    // 2. 放大铺满：双线性插值足以还原已被大模糊抹平的画面
    final picture = recorder.endRecording();
    final small = picture.toImageSync(w, h);
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawImageRect(
        small,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Rect.fromLTWH(-pad, -pad, w * downscale, h * downscale),
        Paint()..filterQuality = FilterQuality.low,
      )
      ..restore();
    small.dispose();
    picture.dispose();
  }

  /// 复刻原布局：Align → 宽 75% 的方框（高度不超过画布）→ 绕中心旋转、放大 → cover 填充。
  void _paintBlob(Canvas canvas, Size size, ui.Image image, LiquidBlob blob, double angle, double alpha) {
    final boxW = size.width * 0.75;
    final boxH = math.min(boxW, size.height);
    final center = Offset(
      (size.width - boxW) / 2 * (1 + blob.alignment.x) + boxW / 2,
      (size.height - boxH) / 2 * (1 + blob.alignment.y) + boxH / 2,
    );
    final dst = Rect.fromCenter(center: Offset.zero, width: boxW, height: boxH);
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, imageSize, dst.size);
    final src = Alignment.center.inscribe(fitted.source, Offset.zero & imageSize);
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(angle)
      ..scale(blob.scale)
      ..drawImageRect(
        image,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, blob.opacity * alpha),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(LiquidArtworkPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.phase != phase || oldDelegate.fade != fade;
}
