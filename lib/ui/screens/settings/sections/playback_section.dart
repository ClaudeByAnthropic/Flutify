import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../providers/playback_provider.dart';
import '../widgets/settings_section.dart';

/// 播放：连续多首无法播放时自动暂停（默认开启）。
class PlaybackSection extends StatelessWidget {
  const PlaybackSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = context.select<PlaybackProvider, bool>((p) => p.pauseAfterFailures);

    return SettingsSection(
      title: l10n.settingsPlaybackSection,
      children: [
        SettingsSwitchTile(
          title: l10n.settingsPauseAfterFailures,
          subtitle: l10n.settingsPauseAfterFailuresSubtitle(PlaybackProvider.failureLimit),
          value: enabled,
          onChanged: context.read<PlaybackProvider>().setPauseAfterFailures,
        ),
      ],
    );
  }
}
