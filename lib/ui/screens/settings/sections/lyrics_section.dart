import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/app_preferences.dart';
import '../../../../providers/preferences_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_segmented.dart';
import '../widgets/settings_slider_tile.dart';

/// 歌词：字号、对齐、其他行模糊强度、LRCLIB 补全、双语歌词（开启才查网易云译文）、全屏歌词默认铺满屏幕还是窗口。
///
/// 对所有歌词视图生效（右栏、手机歌词面板、全屏播放器、沉浸式歌词，含远程模式）。
class LyricsSection extends StatelessWidget {
  const LyricsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.read<PreferencesProvider>();
    final prefs = context.select<PreferencesProvider, AppPreferences>(
      (p) => p.prefs,
    );
    final immersiveScreen = context.select<PreferencesProvider, bool>(
      (p) => p.immersiveScreen,
    );

    return SettingsSection(
      title: l10n.settingsLyricsSection,
      children: [
        SettingsSliderTile(
          title: l10n.settingsLyricsSize,
          value: prefs.lyricsScale,
          min: AppPreferences.minLyricsScale,
          max: AppPreferences.maxLyricsScale,
          divisions: 12,
          minIcon: Icons.text_decrease_rounded,
          maxIcon: Icons.text_increase_rounded,
          labelOf: (v) => '${(v * 100).round()}%',
          onChanged: (v) =>
              provider.update(provider.prefs.copyWith(lyricsScale: v)),
        ),
        SettingsTile(
          title: l10n.settingsLyricsAlign,
          below: SettingsSegmented<LyricsAlign>(
            values: LyricsAlign.values,
            labelOf: (v) => v == LyricsAlign.left
                ? l10n.settingsLyricsAlignLeft
                : l10n.settingsLyricsAlignCenter,
            selected: prefs.lyricsAlign,
            onChanged: (v) =>
                provider.update(provider.prefs.copyWith(lyricsAlign: v)),
          ),
        ),
        SettingsSliderTile(
          title: l10n.settingsLyricsBlur,
          value: prefs.lyricsBlur,
          max: AppPreferences.maxLyricsBlur,
          divisions: 8,
          minIcon: Icons.blur_off_rounded,
          maxIcon: Icons.blur_on_rounded,
          labelOf: (v) => v == 0 ? l10n.settingsOff : '${(v * 100).round()}%',
          onChanged: (v) =>
              provider.update(provider.prefs.copyWith(lyricsBlur: v)),
        ),
        SettingsSwitchTile(
          title: l10n.settingsLyricsFallback,
          subtitle: l10n.settingsLyricsFallbackSubtitle,
          value: prefs.lyricsFallback,
          onChanged: (v) =>
              provider.update(provider.prefs.copyWith(lyricsFallback: v)),
        ),
        SettingsSwitchTile(
          title: l10n.settingsLyricsBilingual,
          subtitle: l10n.settingsLyricsBilingualSubtitle,
          value: prefs.lyricsBilingual,
          onChanged: (v) =>
              provider.update(provider.prefs.copyWith(lyricsBilingual: v)),
        ),
        SettingsSwitchTile(
          title: l10n.settingsLyricsImmersiveScreen,
          subtitle: l10n.settingsLyricsImmersiveScreenSubtitle,
          value: immersiveScreen,
          onChanged: provider.setImmersiveScreen,
        ),
      ],
    );
  }
}
