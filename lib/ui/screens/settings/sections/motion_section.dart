import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/appearance.dart';
import '../../../../providers/appearance_provider.dart';
import '../widgets/settings_section.dart';

/// 动效：减弱动效开关 + 恢复默认外观。
class MotionSection extends StatelessWidget {
  const MotionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppearanceProvider>();
    final settings = context.select<AppearanceProvider, AppearanceSettings>((p) => p.settings);
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final isDefault = settings == AppearanceSettings.defaults;

    return SettingsSection(
      title: l10n.settingsMotionSection,
      children: [
        SettingsSwitchTile(
          title: l10n.settingsReduceMotion,
          subtitle: l10n.settingsReduceMotionSubtitle,
          value: settings.reduceMotion,
          onChanged: (v) => provider.update(settings.copyWith(reduceMotion: v)),
        ),
        // 已是默认外观时置灰、不可点
        Opacity(
          opacity: isDefault ? 0.45 : 1,
          child: SettingsTile(
            title: l10n.settingsResetAppearance,
            trailing: Icon(Icons.restart_alt_rounded, color: colorScheme.onSurfaceVariant),
            onTap: isDefault ? null : provider.reset,
          ),
        ),
      ],
    );
  }
}
