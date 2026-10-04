import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/app_preferences.dart';
import '../../../../providers/preferences_provider.dart';
import '../../../../providers/spotify_provider.dart';
import '../widgets/settings_section.dart';

/// 语言：跟随系统 / 简繁中文 / English / 日本語。
///
/// 切换后界面立即换语言；主页等由 Spotify 本地化的内容在下一帧（Accept-Language 已更新后）重新拉取。
class LanguageSection extends StatelessWidget {
  const LanguageSection({super.key});

  void _change(BuildContext context, AppLanguage language) {
    final provider = context.read<PreferencesProvider>();
    if (provider.prefs.language == language) return;
    final spotify = context.read<SpotifyProvider>();
    provider.update(provider.prefs.copyWith(language: language));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => spotify.loadInitialData(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = context.select<PreferencesProvider, AppLanguage>(
      (p) => p.prefs.language,
    );

    return SettingsSection(
      title: l10n.settingsLanguageSection,
      children: [
        SettingsTile(
          title: l10n.settingsLanguage,
          subtitle: l10n.settingsLanguageSubtitle,
          below: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final value in AppLanguage.values)
                ChoiceChip(
                  label: Text(switch (value) {
                    AppLanguage.system => l10n.settingsLanguageSystem,
                    AppLanguage.zh => l10n.settingsLanguageZh,
                    AppLanguage.zhHant => l10n.settingsLanguageZhHant,
                    AppLanguage.en => l10n.settingsLanguageEn,
                    AppLanguage.ja => l10n.settingsLanguageJa,
                  }),
                  selected: language == value,
                  onSelected: (_) => _change(context, value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
