import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/appearance.dart';
import '../../../../providers/appearance_provider.dart';
import '../widgets/glass_preview.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_slider_tile.dart';

/// 液态玻璃：实时预览 + 模糊强度 + 不透明度。
class GlassSection extends StatelessWidget {
  const GlassSection({super.key});

  static String _percent(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppearanceProvider>();
    final settings = context.select<AppearanceProvider, AppearanceSettings>((p) => p.settings);
    final l10n = context.l10n;

    return SettingsSection(
      title: l10n.settingsGlassSection,
      children: [
        const Padding(padding: EdgeInsets.all(12), child: GlassPreview()),
        SettingsSliderTile(
          title: l10n.settingsGlassBlur,
          valueLabel: _percent(settings.glassBlur),
          value: settings.glassBlur,
          divisions: 20,
          minIcon: Icons.blur_off_rounded,
          maxIcon: Icons.blur_on_rounded,
          onChanged: (v) => provider.update(settings.copyWith(glassBlur: v)),
        ),
        SettingsSliderTile(
          title: l10n.settingsGlassOpacity,
          valueLabel: _percent(settings.glassOpacity),
          value: settings.glassOpacity,
          divisions: 20,
          minIcon: Icons.circle_outlined,
          maxIcon: Icons.circle_rounded,
          onChanged: (v) => provider.update(settings.copyWith(glassOpacity: v)),
        ),
      ],
    );
  }
}
