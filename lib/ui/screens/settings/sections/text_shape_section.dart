import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/appearance.dart';
import '../../../../providers/appearance_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_segmented.dart';
import '../widgets/settings_slider_tile.dart';

/// 文字与形状：字号（带示例文字）+ 圆角风格。
class TextShapeSection extends StatelessWidget {
  const TextShapeSection({super.key});

  /// 字号档位：0.85 ~ 1.30，每档 5%。
  static const int _fontDivisions = 9;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppearanceProvider>();
    final settings = context.select<AppearanceProvider, AppearanceSettings>((p) => p.settings);
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return SettingsSection(
      title: l10n.settingsTextShapeSection,
      children: [
        SettingsSliderTile(
          title: l10n.settingsFontScale,
          valueLabel: '${(settings.fontScale * 100).round()}%',
          value: settings.fontScale,
          min: AppearanceSettings.minFontScale,
          max: AppearanceSettings.maxFontScale,
          divisions: _fontDivisions,
          minIcon: Icons.text_decrease_rounded,
          maxIcon: Icons.text_increase_rounded,
          onChanged: (v) => provider.update(settings.copyWith(fontScale: v)),
        ),
        // 示例文字：已受全局字号缩放影响，所见即所得
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Text(
            l10n.settingsFontPreview,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        SettingsTile(
          title: l10n.settingsCornerStyle,
          below: SettingsSegmented<CornerStyle>(
            values: CornerStyle.values,
            selected: settings.cornerStyle,
            labelOf: (style) => switch (style) {
              CornerStyle.rounded => l10n.settingsCornerRounded,
              CornerStyle.standard => l10n.settingsCornerStandard,
              CornerStyle.square => l10n.settingsCornerSquare,
            },
            onChanged: (style) => provider.update(settings.copyWith(cornerStyle: style)),
          ),
        ),
      ],
    );
  }
}
