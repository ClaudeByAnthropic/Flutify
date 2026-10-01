import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/app_preferences.dart';
import '../../../../providers/preferences_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_segmented.dart';

/// 启动：启动时打开的页面；桌面端另有「记住窗口大小和位置」（下次启动生效）。
class StartupSection extends StatelessWidget {
  const StartupSection({super.key});

  static bool get _isDesktopPlatform => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.read<PreferencesProvider>();
    final (startPage, rememberWindow) = context.select<PreferencesProvider, (StartPage, bool)>(
      (p) => (p.prefs.startPage, p.prefs.rememberWindow),
    );

    return SettingsSection(
      title: l10n.settingsStartupSection,
      children: [
        SettingsTile(
          title: l10n.settingsStartPage,
          below: SettingsSegmented<StartPage>(
            values: StartPage.values,
            labelOf: (v) => switch (v) {
              StartPage.home => l10n.settingsStartPageHome,
              StartPage.library => l10n.settingsStartPageLibrary,
              StartPage.last => l10n.settingsStartPageLast,
            },
            selected: startPage,
            onChanged: (v) => provider.update(provider.prefs.copyWith(startPage: v)),
          ),
        ),
        if (_isDesktopPlatform)
          SettingsSwitchTile(
            title: l10n.settingsRememberWindow,
            subtitle: l10n.settingsRememberWindowSubtitle,
            value: rememberWindow,
            onChanged: (v) => provider.update(provider.prefs.copyWith(rememberWindow: v)),
          ),
      ],
    );
  }
}
