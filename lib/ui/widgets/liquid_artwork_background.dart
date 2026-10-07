import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'liquid_artwork_painter.dart';

/// Apple Music 歌词页的"流动封面"背景。
///
/// 做法：同一张封面放大成三份，以不同速度、不同中心缓慢旋转，
/// 再整体做一次大半径模糊，得到颜色持续流动的液态渐变（绘制见 [LiquidArtworkPainter]）。
///
/// 性能：
/// - 封面以 128px 解码，模糊半径很大，原图分辨率毫无意义；
/// - 模糊在 1/8 分辨率的离屏画布上完成再放大，不再每帧做全屏全分辨率的大模糊；
/// - 整个背景包在 RepaintBoundary 里，前景歌词滚动不会触发它重绘；
/// - [animate] 为 false（暂停播放）时停止旋转，与 Apple Music 行为一致；
/// - 旋转一圈 40 秒、又叠了 σ=70 的大模糊，30fps 与 60fps 肉眼无差别，
///   所以动画只按 30fps 推进：背景每变一帧，上面所有玻璃都要重新采样，帧率减半即 GPU 占用减半。
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
  State<LiquidArtworkBackground> createState() =>
      _LiquidArtworkBackgroundState();
}

class _LiquidArtworkBackgroundState extends State<LiquidArtworkBackground>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(seconds: 40);
  static const Duration _frameInterval = Duration(microseconds: 33333);
  static const Duration _fadeIn = Duration(milliseconds: 400);

  /// 用定时器而不是 Ticker 推进相位：Ticker 每个 vsync 都会回调并预约下一帧，
  /// 即使回调里跳过更新，引擎仍会重新合成整个窗口（含所有玻璃），
  /// 165Hz 屏上就是每秒 165 次整窗重绘。定时器只在相位真正变化时才让引擎出帧。
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();

  /// 所在路由被遮住等情况下 TickerMode 关闭，与 Ticker 一样停止流动。
  bool _tickerEnabled = true;

  /// 旋转相位（0~1 循环）。只有这个 notifier 变化才会重绘封面。
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);

  /// 本次启动前的相位：暂停后继续从原处转，不回到起点。
  double _resumeFrom = 0;

  /// 封面淡入：与原 CachedNetworkImage 的 400ms 淡入一致；内存缓存命中时直接显示。
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: _fadeIn,
  );

  ImageStream? _stream;
  ImageInfo? _artwork;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: _onImageError,
  );

  /// 正在同步 addListener：此时回调的图片来自内存缓存，不做淡入。
  bool _resolvingSync = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncAnimation();
    _resolveImage();
  }

  @override
  void didUpdateWidget(LiquidArtworkBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) _resolveImage();
    _syncAnimation();
  }

  // ---- 封面加载 ----

  void _resolveImage() {
    if (widget.imageUrl.isEmpty) {
      _setStream(null);
      return;
    }
    final provider = ResizeImage(
      CachedNetworkImageProvider(widget.imageUrl),
      width: 128,
    );
    _setStream(provider.resolve(createLocalImageConfiguration(context)));
  }

  void _setStream(ImageStream? stream) {
    if (stream != null && stream.key == _stream?.key) return;
    _inLifecycle = true;
    _stream?.removeListener(_listener);
    _replaceArtwork(null);
    _fade.value = 0;
    _stream = stream;
    _resolvingSync = true;
    stream?.addListener(_listener);
    _resolvingSync = false;
    _inLifecycle = false;
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    _replaceArtwork(info);
    if (_resolvingSync || synchronousCall) {
      _fade.value = 1;
    } else {
      _fade.forward(from: 0);
    }
  }

  /// 加载失败：只显示主色底，与原 errorWidget 一致。
  void _onImageError(Object error, StackTrace? stackTrace) =>
      _replaceArtwork(null);

  /// 生命周期内（didChangeDependencies / didUpdateWidget / 同步命中）本就会重建，
  /// 只有异步回调才需要 setState。
  void _replaceArtwork(ImageInfo? info) {
    if (!mounted) {
      info?.dispose();
      return;
    }
    final old = _artwork;
    _artwork = info;
    if (!_inLifecycle) setState(() {});
    old?.dispose();
  }

  bool _inLifecycle = false;

  // ---- 旋转动画 ----

  void _syncAnimation() =>
      widget.animate && _tickerEnabled ? _start() : _stop();

  void _start() {
    if (_timer != null) return;
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(_frameInterval, (_) => _tick());
  }

  void _stop() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    _clock.stop();
    _resumeFrom = _phase.value;
  }

  void _tick() {
    _phase.value =
        (_resumeFrom + _clock.elapsedMicroseconds / _period.inMicroseconds) %
        1.0;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _artwork?.dispose();
    _timer?.cancel();
    _fade.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: widget.fallback),
          CustomPaint(
            painter: LiquidArtworkPainter(
              phase: _phase,
              fade: _fade,
              image: _artwork?.image,
            ),
          ),
          // 压暗一层，保证白色歌词在任何封面上都有足够对比度
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x59000000),
                  Color(0x33000000),
                  Color(0x80000000),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
