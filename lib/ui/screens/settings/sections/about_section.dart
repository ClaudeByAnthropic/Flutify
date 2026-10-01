import 'package:flutter/material.dart';

import '../../../../core/constants/app_info.dart';
import '../../../../l10n/l10n.dart';
import '../../../shell/shell_breakpoints.dart';
import '../widgets/settings_section.dart';
import '../widgets/shortcuts_dialog.dart';

/// 关于：版本号、键盘快捷键（仅桌面布局）、开源许可（Flutter 自带许可页，含所有依赖包）。
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final desktop = ShellBreakpoints.isDesktop(MediaQuery.sizeOf(context).width);
    final chevron = Icon(Icons.chevron_right_rounded, color: muted);

    return SettingsSection(
      title: l10n.settingsAboutSection,
      children: [
        SettingsTile(
          title: l10n.settingsVersion,
          trailing: Text(AppInfo.displayVersion, style: TextStyle(color: muted)),
        ),
        if (desktop)
          SettingsTile(title: l10n.settingsShortcuts, trailing: chevron, onTap: () => ShortcutsDialog.show(context)),
        SettingsTile(
          title: l10n.settingsLicenses,
          trailing: chevron,
          onTap: () => showLicensePage(
            context: context,
            applicationName: AppInfo.name,
            applicationVersion: AppInfo.displayVersion,
          ),
        ),
      ],
    );
  }
}
