import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/flutify_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/lyrics.dart';
import '../../../../providers/playback_provider.dart';
import '../../../../providers/spotify_provider.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import 'lyric_line_view.dart';

/// 歌词滚动区。
///
/// 行为（对齐 Apple Music iOS）：
/// - 当前行固定在上下玻璃之间的正中，上下句按距离逐级模糊（前奏 / 暂停时同样对焦）；
/// - 用户手动拖动时全部行变清晰（[_browsing]），停手 3 秒后恢复对焦并滚回当前行；
/// - 点击任意行跳转到该行时间点；
/// - 非同步歌词（UNSYNCED）全部清晰显示、不可点击。
///
/// 性能：手动监听 positionNotifier，只有「当前行」变化时才 setState；
/// 当前行用二分查找定位。
class LyricsView extends StatefulWidget {
  final String trackId;

  /// 顶部 / 底部被玻璃控件覆盖的高度，歌词可从其下方滚过。
  final double topInset;
  final double bottomInset;

  /// 歌词字号：手机 / 右栏 30，桌面沉浸式更大。
  final double fontSize;

  /// 歌词区左右留白。
  final double horizontalPadding;

  const LyricsView({
    super.key,
    required this.trackId,
    this.topInset = 0,
    this.bottomInset = 0,
    this.fontSize = 30,
    this.horizontalPadding = 28,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const Duration _browseHold = Duration(seconds: 3);

  /// 提前切行量：进度流约 200ms 一次，加上对焦/滚动动画耗时，
  /// 不提前的话视觉上会比演唱慢半拍（Apple Music 同样提前切行）。
  static const int _leadMs = 300;

  /// 歌词区可视高度（由 LayoutBuilder 写入），用于把当前行对准"未被玻璃遮挡区域"的正中。
  double _viewportHeight = 0;

  late final ValueNotifier<Duration> _position;
  late final PlaybackProvider _playback;
  final ScrollController _scroll = ScrollController();

  SpotifyLyrics? _lyrics;
  List<GlobalKey> _lineKeys = const [];
  int _activeIndex = -1;
  bool _browsing = false;
  Timer? _browseTimer;

  bool get _isSynced => _lyrics?.syncType == 'LINE_SYNCED';

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackProvider>();
    _position = _playback.positionNotifier..addListener(_onPosition);

    final spotify = context.read<SpotifyProvider>();
    final cached = spotify.cachedLyrics(widget.trackId);
    if (cached != null) {
      _setLyrics(cached);
    } else {
      spotify.fetchLyrics(widget.trackId).then((lyrics) {
        if (mounted) setState(() => _setLyrics(lyrics));
      });
    }
  }

  void _setLyrics(SpotifyLyrics lyrics) {
    _lyrics = lyrics;
    _lineKeys = List.generate(lyrics.lines.length, (_) => GlobalKey());
    _activeIndex = _indexFor(_position.value.inMilliseconds + _leadMs);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive(animate: false));
  }

  /// 对焦行：前奏阶段（尚未唱到第一句，_activeIndex 为 -1）对焦第一句，
  /// 保证任何时刻（包括暂停、刚打开）都有一句清晰地停在中间。
  int get _focusIndex => _activeIndex < 0 ? 0 : _activeIndex;

  /// 对焦中心的纵坐标：顶部信息胶囊与底部控制台之间的正中。
  double get _focusCenterY =>
      (widget.topInset + (_viewportHeight - widget.bottomInset)) / 2;

  /// 最后一个 startTimeMs <= ms 的行；在第一行之前返回 -1。
  int _indexFor(int ms) {
    final lines = _lyrics?.lines ?? const <LyricLine>[];
    var lo = 0, hi = lines.length - 1, result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].startTimeMs <= ms) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  void _onPosition() {
    if (!_isSynced) return;
    final index = _indexFor(_position.value.inMilliseconds + _leadMs);
    if (index == _activeIndex) return;
    setState(() => _activeIndex = index);
    if (!_browsing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  void _scrollToActive({bool animate = true}) {
    if (!mounted || _lineKeys.isEmpty || _viewportHeight <= 0) return;
    final ctx = _lineKeys[_focusIndex.clamp(0, _lineKeys.length - 1)].currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (ctx == null || box == null || !box.hasSize) return;

    // ensureVisible 的 alignment 表示「行顶部位于 (视口高 - 行高) × alignment」，
    // 反推出让行的中心恰好落在 _focusCenterY 的 alignment
    final lineHeight = box.size.height;
    final free = _viewportHeight - lineHeight;
    final alignment = free <= 0 ? 0.0 : ((_focusCenterY - lineHeight / 2) / free).clamp(0.0, 1.0);

    Scrollable.ensureVisible(
      ctx,
      alignment: alignment,
      duration: animate && !context.reduceMotion ? const Duration(milliseconds: 500) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  /// 只响应用户手势（程序滚动不会产生 UserScrollNotification）。
  bool _onUserScroll(UserScrollNotification n) {
    if (!_isSynced) return false;
    _browseTimer?.cancel();
    if (!_browsing) setState(() => _browsing = true);
    _browseTimer = Timer(_browseHold, _endBrowsing);
    return false;
  }

  void _endBrowsing() {
    if (!mounted) return;
    setState(() => _browsing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  void _seekToLine(LyricLine line) {
    _browseTimer?.cancel();
    _playback.seekTo(Duration(milliseconds: line.startTimeMs));
    if (_browsing) setState(() => _browsing = false);
  }

  @override
  void dispose() {
    _browseTimer?.cancel();
    _position.removeListener(_onPosition);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = _lyrics;
    if (lyrics == null) return _LoadingLines(topInset: widget.topInset);
    if (lyrics.lines.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: widget.topInset, bottom: widget.bottomInset),
        child: Center(
          child: EmptyState(
            icon: Icons.lyrics_outlined,
            title: context.l10n.lyricsUnavailableTitle,
            message: context.l10n.lyricsUnavailableMessage,
            onDark: true,
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      // 窗口尺寸变化后重新把对焦行对准中心
      if (constraints.maxHeight != _viewportHeight) {
        _viewportHeight = constraints.maxHeight;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive(animate: false));
      }
      return _buildLines(lyrics);
    });
  }

  Widget _buildLines(SpotifyLyrics lyrics) {
    final centerY = _focusCenterY;

    return NotificationListener<UserScrollNotification>(
      onNotification: _onUserScroll,
      child: ShaderMask(
        // 上下边缘柔和淡出，歌词像从玻璃下方浮现
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.14, 0.82, 1.0],
        ).createShader(rect),
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          // 上下各留出到对焦中心的距离，第一句和最后一句也能停在正中
          padding: EdgeInsets.fromLTRB(
            widget.horizontalPadding,
            centerY,
            widget.horizontalPadding,
            _viewportHeight - centerY,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isSynced)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    context.l10n.lyricsUnsynced,
                    style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              for (var i = 0; i < lyrics.lines.length; i++)
                LyricLineView(
                  key: _lineKeys[i],
                  text: lyrics.lines[i].words,
                  fontSize: widget.fontSize,
                  // 以对焦行为中心：当句清晰，上下句按行距逐级模糊
                  distance: _isSynced ? i - _focusIndex : 0,
                  focusAll: !_isSynced || _browsing,
                  onTap: _isSynced ? () => _seekToLine(lyrics.lines[i]) : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 歌词加载中的骨架（白色半透明横条，适配深色流动背景）。
class _LoadingLines extends StatelessWidget {
  final double topInset;

  const _LoadingLines({required this.topInset});

  static const List<double> _widths = [0.82, 0.64, 0.9, 0.48, 0.74, 0.58];

  @override
  Widget build(BuildContext context) {
    // 不可滚动的 ScrollView：窗口很矮时直接裁掉多余骨架，而不是溢出报错
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(28, topInset + 24, 28, 0),
      child: SkeletonPulse(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in _widths)
                Container(
                  width: constraints.maxWidth * w,
                  height: 26,
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
