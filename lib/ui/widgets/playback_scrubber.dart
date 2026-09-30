import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../providers/playback_provider.dart';

/// 播放进度条（全屏播放器 / 桌面播放栏共用）。
///
/// - 仅本组件订阅高频的 positionNotifier，父组件不会因进度变化重建。
/// - 拖动过程中只更新本地值，松手（onChangeEnd）时才真正 seek，
///   避免每一帧都向音频引擎发送 seek 请求。
class PlaybackScrubber extends StatefulWidget {
  /// true：桌面样式（时间在两侧，单行）；false：移动端样式（时间在下方）。
  final bool compact;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? labelColor;

  const PlaybackScrubber({
    super.key,
    this.compact = false,
    this.activeColor,
    this.inactiveColor,
    this.labelColor,
  });

  @override
  State<PlaybackScrubber> createState() => _PlaybackScrubberState();
}

class _PlaybackScrubberState extends State<PlaybackScrubber> {
  /// 拖动中的临时值（毫秒）；为 null 表示未在拖动。
  double? _dragValueMs;

  @override
  Widget build(BuildContext context) {
    final playback = context.read<PlaybackProvider>();
    final durationMs = context.select<PlaybackProvider, int>((p) => p.duration.inMilliseconds);
    final colorScheme = Theme.of(context).colorScheme;
    final labelColor = widget.labelColor ?? colorScheme.onSurfaceVariant;
    final labelStyle = TextStyle(
      color: labelColor,
      fontSize: 11,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: widget.compact ? 3.0 : 3.5,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: widget.compact ? 5 : 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: widget.compact ? 10 : 14),
      activeTrackColor: widget.activeColor,
      inactiveTrackColor: widget.inactiveColor,
      thumbColor: widget.activeColor,
    );

    return RepaintBoundary(
      child: ValueListenableBuilder<Duration>(
        valueListenable: playback.positionNotifier,
        builder: (context, position, _) {
          final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
          final valueMs = (_dragValueMs ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs);
          final shown = Duration(milliseconds: valueMs.round());

          final slider = SliderTheme(
            data: sliderTheme,
            child: Slider(
              value: valueMs,
              max: maxMs,
              onChangeStart: (v) => setState(() => _dragValueMs = v),
              onChanged: (v) => setState(() => _dragValueMs = v),
              onChangeEnd: (v) {
                playback.seekTo(Duration(milliseconds: v.round()));
                setState(() => _dragValueMs = null);
              },
            ),
          );

          if (widget.compact) {
            return Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(Formatters.formatDuration(shown), style: labelStyle, textAlign: TextAlign.right),
                ),
                const SizedBox(width: 8),
                Expanded(child: slider),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(Formatters.formatDurationMs(durationMs), style: labelStyle),
                ),
              ],
            );
          }

          final remaining = Duration(milliseconds: (durationMs - valueMs).round().clamp(0, durationMs));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              slider,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(Formatters.formatDuration(shown), style: labelStyle),
                    Text('-${Formatters.formatDuration(remaining)}', style: labelStyle),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 细进度线（MiniPlayer 底部），同样只局部订阅进度。
class PlaybackProgressLine extends StatelessWidget {
  final double height;
  final Color? color;
  final Color? backgroundColor;

  const PlaybackProgressLine({super.key, this.height = 2.5, this.color, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    final playback = context.read<PlaybackProvider>();
    final durationMs = context.select<PlaybackProvider, int>((p) => p.duration.inMilliseconds);
    final colorScheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: ValueListenableBuilder<Duration>(
        valueListenable: playback.positionNotifier,
        builder: (context, position, _) {
          final fraction = durationMs <= 0 ? 0.0 : (position.inMilliseconds / durationMs).clamp(0.0, 1.0);
          return LinearProgressIndicator(
            value: fraction,
            minHeight: height,
            backgroundColor: backgroundColor ?? colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color ?? colorScheme.primary),
          );
        },
      ),
    );
  }
}
