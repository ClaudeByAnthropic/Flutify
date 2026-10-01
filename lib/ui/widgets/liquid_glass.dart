import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/flutify_tokens.dart';
import '../shell/desktop/desktop_window.dart';

/// iOS 风格的克制型玻璃容器。
///
/// 三层叠加：
/// 1. 背景模糊 + 轻微提饱和（1.15×，只让身后颜色略微通透，不"发光"）；
/// 2. 极淡的白色填充（玻璃体本身几乎不可见，靠模糊界定形状）；
/// 3. 一圈发丝级描边，上缘略亮于下缘，暗示光从上方来。
///
/// 设计原则：玻璃应该"退后"，让内容和背景说话；任何一层都不应被一眼注意到。
/// 性能：每个实例是一次 BackdropFilter，页面内应控制在少量几个。
class LiquidGlass extends StatelessWidget {
  final Widget child;

  /// 为空时按 28px 基准随「圆角风格」缩放。
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;

  /// 模糊半径；为空时取设置页「玻璃模糊」。
  final double? blur;

  /// 玻璃填充亮度（0~1）；为空时取设置页「玻璃不透明度」（默认约 0.05）。
  final double? tint;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding = EdgeInsets.zero,
    this.blur,
    this.tint,
  });

  /// 饱和度 1.15 的颜色矩阵（按 Rec.709 亮度权重）。
  static const ColorFilter _saturate = ColorFilter.matrix(<double>[
    1.1181, -0.1073, -0.0108, 0, 0, //
    -0.0319, 1.0427, -0.0108, 0, 0, //
    -0.0319, -0.1073, 1.1392, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final radius = borderRadius ?? tokens.radius(28);
    final sigma = blur ?? tokens.glassSigma;
    final body = CustomPaint(
      foregroundPainter: _HairlinePainter(radius),
      child: ColoredBox(
        color: Colors.white.withValues(alpha: tint ?? tokens.glassTint),
        child: Padding(padding: padding, child: child),
      ),
    );
    return ClipRRect(
      borderRadius: radius,
      // 系统全屏切换期间引擎合成器对 BackdropFilter 会访问冲突（详见 DesktopWindow.fullscreenTransition），
      // 这约 300ms 内退化为无模糊玻璃，肉眼几乎不可辨
      child: ValueListenableBuilder<bool>(
        valueListenable: DesktopWindow.fullscreenTransition,
        builder: (context, transitioning, _) {
          if (transitioning) return body;
          return BackdropFilter(
            filter: ImageFilter.compose(
              outer: _saturate,
              inner: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.mirror,
              ),
            ),
            child: body,
          );
        },
      ),
    );
  }
}

/// 发丝描边：上缘 14% 白、下缘 4% 白。
class _HairlinePainter extends CustomPainter {
  final BorderRadius borderRadius;

  _HairlinePainter(this.borderRadius);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0.04),
        ],
      ).createShader(rect);
    canvas.drawRRect(borderRadius.toRRect(rect).deflate(0.3), paint);
  }

  @override
  bool shouldRepaint(_HairlinePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius;
}
