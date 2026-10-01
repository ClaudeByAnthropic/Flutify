import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/md3e_colors.dart';

/// Flutify 品牌标：连续曲率圆角方块（superellipse）+ 品牌绿对角渐变 + 白色「F」字形
/// （竖笔 + 一长一短两道横笔，第三行收成圆点）。
///
/// 与应用图标同一套比例：母版见 `tool/brand/generate_logo.py`（生成 `assets/brand/flutify_logo.svg`
/// 及各平台图标），改几何时两处一起改。纯矢量绘制，任意尺寸清晰；[glow] 为登录页添加柔和的品牌色光晕。
class FlutifyMark extends StatelessWidget {
  final double size;
  final bool glow;

  const FlutifyMark({super.key, this.size = 72, this.glow = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: MD3EColors.spotifyGreen.withAlpha(70),
                  blurRadius: size * 0.6,
                  spreadRadius: -size * 0.12,
                  offset: Offset(0, size * 0.18),
                ),
              ]
            : null,
      ),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  // 与 generate_logo.py 保持一致的几何（边长为 1）
  static const _greenLight = Color(0xFF3BE477);
  static const _greenDeep = Color(0xFF129A48);
  static const _n = 5.0;
  static const _t = 0.118;
  static const _x0 = 0.300;
  static const _y0 = 0.250;
  static const _y1 = 0.750;
  static const _topRight = 0.720;
  static const _midRight = 0.600;
  static const _dotGap = 0.062;

  /// superellipse |x|^n + |y|^n = 1 的轮廓（n = 5，接近 iOS 图标的连续曲率圆角）。
  static Path _plate(double s) {
    const steps = 160;
    final path = Path();
    final c = s / 2;
    for (var i = 0; i < steps; i++) {
      final a = 2 * math.pi * i / steps;
      final ca = math.cos(a), sa = math.sin(a);
      final x = c + c * ca.sign * math.pow(ca.abs(), 2 / _n);
      final y = c + c * sa.sign * math.pow(sa.abs(), 2 / _n);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;

    final plate = _plate(s);
    canvas.drawPath(
      plate,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_greenLight, _greenDeep],
        ).createShader(rect),
    );

    // 顶部高光：极淡的白色描边，增加玻璃质感
    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, s * 0.012)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.white.withAlpha(80), Colors.white.withAlpha(0)],
        ).createShader(rect),
    );

    // 字形：全圆角笔画 + 圆点
    final ink = Paint()..color = Colors.white;
    final r = Radius.circular(_t / 2 * s);
    RRect bar(double l, double t, double rt, double b) => RRect.fromLTRBR(l * s, t * s, rt * s, b * s, r);
    canvas.drawRRect(bar(_x0, _y0, _x0 + _t, _y1), ink); // 竖笔
    canvas.drawRRect(bar(_x0, _y0, _topRight, _y0 + _t), ink); // 上横（长）
    canvas.drawRRect(bar(_x0, 0.5 - _t / 2, _midRight, 0.5 + _t / 2), ink); // 中横（短）
    canvas.drawCircle(Offset((_x0 + _t + _dotGap + _t / 2) * s, (_y1 - _t / 2) * s), _t / 2 * s, ink); // 圆点
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
