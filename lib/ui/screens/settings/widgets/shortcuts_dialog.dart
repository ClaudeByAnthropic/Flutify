import 'package:flutter/material.dart';

import '../../../../core/theme/flutify_tokens.dart';
import '../../../../l10n/l10n.dart';

/// 键盘快捷键一览（设置页「关于」）。
///
/// 与 `MainShell._shortcuts`、沉浸式歌词的按键处理保持一致；改快捷键时两处一起改。
class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const ShortcutsDialog());

  /// 按键组合（每个元素是一个键帽）与说明。
  static List<(List<String>, String)> entries(AppLocalizations l10n) => [
    (['Space'], l10n.shortcutPlayPause),
    (['Ctrl', '→'], l10n.shortcutNext),
    (['Ctrl', '←'], l10n.shortcutPrevious),
    (['Ctrl', '↑'], l10n.shortcutVolumeUp),
    (['Ctrl', '↓'], l10n.shortcutVolumeDown),
    (['Ctrl', 'S'], l10n.shortcutShuffle),
    (['Ctrl', 'R'], l10n.shortcutRepeat),
    (['Ctrl', 'K'], l10n.shortcutSearch),
    (['Alt', '←'], l10n.shortcutBack),
    (['Alt', '→'], l10n.shortcutForward),
    (['F11'], l10n.shortcutImmersive),
    (['F11'], l10n.shortcutImmersiveMode),
    (['Esc'], l10n.shortcutExitImmersive),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.settingsShortcuts),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (keys, label) in entries(l10n))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                      const SizedBox(width: 16),
                      for (var i = 0; i < keys.length; i++) ...[if (i > 0) const SizedBox(width: 4), _KeyCap(keys[i])],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose))],
    );
  }
}

/// 键帽：浅色凹槽 + 等宽数字，类似 macOS 菜单里的快捷键标注。
class _KeyCap extends StatelessWidget {
  final String label;

  const _KeyCap(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: context.tokens.radius(6),
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant, width: 1.5)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
