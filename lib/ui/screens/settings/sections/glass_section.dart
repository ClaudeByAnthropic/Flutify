import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/appearance.dart';
import '../../../../providers/appearance_provider.dart';
import '../widgets/glass_preview.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_slider_tile.dart';

/// 液态玻璃：实时预览 + 模糊强度 + 不透明度。
///
/// 拖动滑杆时只把草稿值交给预览（局部重绘），松手才写入全局外观。
class GlassSection extends StatefulWidget {
  const GlassSection({super.key});

  @override
  State<GlassSection> createState() => _GlassSectionState();
}

class _GlassSectionState extends State<GlassSection> {
  double? _blurDraft;
  double? _opacityDraft;

  static String _percent(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppearanceProvider>();
    final settings = context.select<AppearanceProvider, AppearanceSettings>((p) => p.settings);
    final l10n = context.l10n;

    return SettingsSection(
      title: l10n.settingsGlassSection,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: GlassPreview(blur: _blurDraft, opacity: _opacityDraft),
        ),
        SettingsSliderTile(
          title: l10n.settingsGlassBlur,
          labelOf: _percent,
          value: settings.glassBlur,
          divisions: 20,
          minIcon: Icons.blur_off_rounded,
          maxIcon: Icons.blur_on_rounded,
          onPreview: (v) => setState(() => _blurDraft = v),
          onChanged: (v) => provider.update(settings.copyWith(glassBlur: v)),
        ),
        SettingsSliderTile(
          title: l10n.settingsGlassOpacity,
          labelOf: _percent,
          value: settings.glassOpacity,
          divisions: 20,
          minIcon: Icons.circle_outlined,
          maxIcon: Icons.circle_rounded,
          onPreview: (v) => setState(() => _opacityDraft = v),
          onChanged: (v) => provider.update(settings.copyWith(glassOpacity: v)),
        ),
      ],
    );
  }
}
