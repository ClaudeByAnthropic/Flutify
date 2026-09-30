import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Apple Music 歌词页的"流动封面"背景。
///
/// 做法：同一张封面放大成三份，以不同速度、不同中心缓慢旋转，
/// 再整体做一次大半径模糊，得到颜色持续流动的液态渐变。
///
/// 性能：
/// - 封面以 128px 解码，模糊半径很大，原图分辨率毫无意义；
/// - 整个背景包在 RepaintBoundary 里，前景歌词滚动不会触发它重绘；
/// - [animate] 为 false（暂停播放）时停止旋转，与 Apple Music 行为一致。
class LiquidArtworkBackground extends StatefulWidget {
  final String imageUrl;
  final Color fallback;
  final bool animate;

  const LiquidArtworkBackground({
    super.key,
    required this.imageUrl,
    required this.fallback,
    this.animate = true,
  });

  @override
  State<LiquidArtworkBackground> createState() => _LiquidArtworkBackgroundState();
}

class _LiquidArtworkBackgroundState extends State<LiquidArtworkBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(LiquidArtworkBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    widget.animate ? _controller.repeat() : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(color: widget.fallback);
    // 图片失败或无封面时，退化为主色 + 深色的静态渐变，不留空白
    final artwork = widget.imageUrl.isEmpty
        ? fallback
        : CachedNetworkImage(
            imageUrl: widget.imageUrl,
            memCacheWidth: 128,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 400),
            placeholder: (_, _) => fallback,
            errorWidget: (_, _, _) => fallback,
          );

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: widget.fallback),
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70, tileMode: TileMode.decal),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value * 2 * math.pi;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _blob(artwork, const Alignment(-0.6, -0.5), scale: 1.9, angle: t),
                      _blob(artwork, const Alignment(0.7, 0.2), scale: 1.6, angle: -t * 1.3 + 1.2),
                      _blob(artwork, const Alignment(-0.3, 0.8), scale: 1.4, angle: t * 0.7 + 2.4, opacity: 0.8),
                    ],
                  );
                },
              ),
            ),
          ),
          // 压暗一层，保证白色歌词在任何封面上都有足够对比度
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x59000000), Color(0x33000000), Color(0x80000000)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(Widget artwork, Alignment alignment, {required double scale, required double angle, double opacity = 1}) {
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: 0.75,
        child: AspectRatio(
          aspectRatio: 1,
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(scale: scale, child: artwork),
            ),
          ),
        ),
      ),
    );
  }
}
