import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/flutify_tokens.dart';

/// 单行歌词（Apple Music iOS 风格）。
///
/// 视觉规则由 [distance]（与当前行的行距，负数为已唱过）决定：
/// - 当前行：纯白、不模糊、原始大小；
/// - 其余行：透明度逐行降低，模糊半径逐行增大（上限 [_maxBlur]），略微缩小；
/// - [focusAll] 为 true（用户正在手动浏览 / 非同步歌词）时全部清晰，方便阅读。
///
/// 所有参数通过 TweenAnimationBuilder 平滑过渡，行切换时呈现"对焦"动画。
class LyricLineView extends StatelessWidget {
  final String text;
  final int distance;
  final bool focusAll;
  final VoidCallback? onTap;

  /// 字号；行距随字号等比放大。
  final double fontSize;

  /// 居中对齐时文字居中、缩放以中心为基准；默认左对齐（Apple Music）。
  final bool centered;

  /// 模糊强度倍率（设置页「其他行模糊」）：0 不模糊，1 默认。
  final double blurScale;

  const LyricLineView({
    super.key,
    required this.text,
    required this.distance,
    this.focusAll = false,
    this.onTap,
    this.fontSize = 30,
    this.centered = false,
    this.blurScale = 1,
  });

  static const double _maxBlur = 3.5;
  static const Duration _duration = Duration(milliseconds: 520);

  @override
  Widget build(BuildContext context) {
    final d = distance.abs();
    final isActive = distance == 0;

    // 相邻句 1.0、隔一句 2.0 …… 上限 3.5：近处可辨认，远处退为氛围；再乘用户设置的强度
    final blur = focusAll || isActive ? 0.0 : (d * 1.0).clamp(0.0, _maxBlur) * blurScale;
    final opacity = focusAll
        ? (isActive ? 1.0 : 0.62)
        : isActive
        ? 1.0
        : (0.52 - d * 0.06).clamp(0.2, 0.46);
    final scale = isActive ? 1.0 : 0.965;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: fontSize * 0.4),
        child: TweenAnimationBuilder<_LineVisual>(
          tween: _LineVisualTween(end: _LineVisual(blur, opacity, scale)),
          duration: context.motion(_duration),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) {
            // 透明度直接写进文字颜色，省去 Opacity 的离屏图层
            Widget result = _LineText(text: text, opacity: v.opacity, fontSize: fontSize, centered: centered);
            // sigma 过小时跳过滤镜，避免无意义的离屏渲染
            if (v.blur > 0.05) {
              result = ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: v.blur, sigmaY: v.blur),
                child: result,
              );
            }
            return Transform.scale(
              scale: v.scale,
              alignment: centered ? Alignment.center : Alignment.centerLeft,
              child: result,
            );
          },
        ),
      ),
    );
  }
}

/// 歌词文字；空行（间奏）显示三个圆点。
class _LineText extends StatelessWidget {
  final String text;
  final double opacity;
  final double fontSize;
  final bool centered;

  const _LineText({required this.text, required this.opacity, required this.fontSize, required this.centered});

  @override
  Widget build(BuildContext context) {
    final isInterlude = text.trim().isEmpty || text.trim() == '♪';
    return SizedBox(
      width: double.infinity,
      child: Text(
        isInterlude ? '•  •  •' : text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: opacity),
          // 中文歌词：字距只轻微收紧，行高放宽并上下均分，多行时汉字不挤、不裁切
          letterSpacing: -0.2,
          height: 1.3,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}

/// 动画插值所需的三元组。
@immutable
class _LineVisual {
  final double blur;
  final double opacity;
  final double scale;

  const _LineVisual(this.blur, this.opacity, this.scale);
}

class _LineVisualTween extends Tween<_LineVisual> {
  _LineVisualTween({required _LineVisual end}) : super(begin: end, end: end);

  @override
  _LineVisual lerp(double t) {
    final a = begin!, b = end!;
    return _LineVisual(
      lerpDouble(a.blur, b.blur, t)!,
      lerpDouble(a.opacity, b.opacity, t)!,
      lerpDouble(a.scale, b.scale, t)!,
    );
  }
}
