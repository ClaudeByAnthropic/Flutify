import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/md3e_colors.dart';

/// Flutify 品牌标：连续曲率圆角方块（squircle）内三道向右扩散的声波弧 + 圆心音点。
///
/// 纯矢量绘制（等价于一枚 SVG），任意尺寸清晰；[glow] 为登录页添加柔和的品牌色光晕。
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
        borderRadius: BorderRadius.circular(size * 0.28),
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
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;

    // 底板：自上而下的品牌绿渐变，带连续曲率圆角
    final plate = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28));
    canvas.drawRRect(
      plate,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3BE477), MD3EColors.spotifyGreenDark],
        ).createShader(rect),
    );

    // 顶部高光：极淡的白色描边，增加玻璃质感
    canvas.drawRRect(
      plate.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withAlpha(90), Colors.white.withAlpha(0)],
        ).createShader(rect),
    );

    // 声波：以左侧偏中的音点为圆心，三道同心弧，越外越细越淡
    const ink = Color(0xFF0B0F0C);
    final center = Offset(s * 0.34, s * 0.5);
    canvas.drawCircle(center, s * 0.075, Paint()..color = ink);

    const sweep = math.pi * 0.62;
    for (var i = 0; i < 3; i++) {
      final radius = s * (0.17 + i * 0.12);
      final paint = Paint()
        ..color = ink.withAlpha(255 - i * 55)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * (0.072 - i * 0.012);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -sweep / 2,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
