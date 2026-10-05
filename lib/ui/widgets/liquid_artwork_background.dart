import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Apple Music 歌词页的"流动封面"背景。
///
/// 做法：同一张封面放大成三份，以不同速度、不同中心缓慢旋转，
/// 再整体做一次大半径模糊，得到颜色持续流动的液态渐变。
///
/// 性能：
/// - 封面以 128px 解码，模糊半径很大，原图分辨率毫无意义；
/// - 整个背景包在 RepaintBoundary 里，前景歌词滚动不会触发它重绘；
/// - [animate] 为 false（暂停播放）时停止旋转，与 Apple Music 行为一致；
/// - 旋转一圈 40 秒、又叠了 σ=70 的大模糊，30fps 与 60fps 肉眼无差别，
///   所以动画只按 30fps 推进：这一层每帧都要重新做全屏大模糊，还会连带让上面
///   所有玻璃重新采样背景，帧率减半即 GPU 占用减半。
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
  static const Duration _period = Duration(seconds: 40);
  // 略小于 1/30 秒：vsync 抖动时也不会被误判成「还没到点」而掉到 20fps
  static const Duration _minFrameGap = Duration(milliseconds: 30);

  late final Ticker _ticker;

  /// 旋转相位（0~1 循环）。只有这个 notifier 变化才会重建三块封面。
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);

  /// 本次启动前的相位：暂停后继续从原处转，不回到起点。
  double _resumeFrom = 0;
  Duration _lastEmit = Duration.zero;

  @override
  void initState() {
    super.initState();
    // 即使首次为暂停状态也提前创建，避免 dispose 才初始化并访问失效的 context。
    _ticker = createTicker(_tick);
    if (widget.animate) _start();
  }

  @override
  void didUpdateWidget(LiquidArtworkBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    widget.animate ? _start() : _stop();
  }

  void _start() {
    if (_ticker.isActive) return;
    _lastEmit = Duration.zero;
    _ticker.start();
  }

  void _stop() {
    if (!_ticker.isActive) return;
    _ticker.stop();
    _resumeFrom = _phase.value;
  }

  void _tick(Duration elapsed) {
    if (elapsed - _lastEmit < _minFrameGap) return;
    _lastEmit = elapsed;
    _phase.value =
        (_resumeFrom + elapsed.inMicroseconds / _period.inMicroseconds) % 1.0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
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
                animation: _phase,
                builder: (context, _) {
                  final t = _phase.value * 2 * math.pi;
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
