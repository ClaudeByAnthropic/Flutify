import 'package:flutter/material.dart';

/// 滑杆行：标题 + 右侧当前值，下方为两端带小图标的滑杆（iOS 亮度 / 字号滑杆样式）。
class SettingsSliderTile extends StatelessWidget {
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final IconData? minIcon;
  final IconData? maxIcon;
  final ValueChanged<double> onChanged;

  const SettingsSliderTile({
    super.key,
    required this.title,
    required this.valueLabel,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.minIcon,
    this.maxIcon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600))),
              Text(
                valueLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (minIcon != null) Icon(minIcon, size: 16, color: muted),
              Expanded(
                // 分档只用于吸附，不画刻度点（iOS 滑杆观感更干净）
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onChanged,
                  ),
                ),
              ),
              if (maxIcon != null) Icon(maxIcon, size: 22, color: muted),
            ],
          ),
        ],
      ),
    );
  }
}
