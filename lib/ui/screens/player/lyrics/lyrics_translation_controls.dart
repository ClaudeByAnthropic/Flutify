import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../providers/spotify_provider.dart';
import '../../../../services/lyrics/lyrics_translation.dart';
import 'glass_icon_button.dart';

/// A lyrics surface and its toolbar share one lookup and cancellation state.
class LyricsTranslationScope extends StatelessWidget {
  final Widget child;

  const LyricsTranslationScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<LyricsTranslationController>(
        create: (context) => LyricsTranslationController(
          lookup: context.read<SpotifyProvider>().fetchLyricsTranslation,
        ),
        child: child,
      );
}

class LyricsTranslationButton extends StatelessWidget {
  /// Mobile player / lyrics sheet chip: a 40 visible circle with a standard
  /// 24 glyph (matching shuffle/repeat), inside a 48 touch target.
  static const playerChipSize = 40.0;
  static const playerChipIconSize = 24.0;
  static const playerTapSize = 48.0;

  /// Transparent ring around the visible chip; layouts align the visible edge.
  static const playerTapInset = (playerTapSize - playerChipSize) / 2;

  final double size;
  final double? iconSize;
  final double? tapSize;
  final bool glass;

  const LyricsTranslationButton({
    super.key,
    this.size = 48,
    this.iconSize,
    this.tapSize,
    this.glass = true,
  });

  /// The mobile player / lyrics sheet variant (40 / 24 / 48).
  const LyricsTranslationButton.player({super.key, this.glass = true})
    : size = playerChipSize,
      iconSize = playerChipIconSize,
      tapSize = playerTapSize;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LyricsTranslationController>();
    final l10n = context.l10n;
    final active = controller.lines != null || controller.busy;
    final label = controller.busy
        ? l10n.lyricsTranslating
        : controller.lines != null
        ? l10n.lyricsCancelTranslation
        : controller.failed
        ? l10n.lyricsTranslationFailed
        : controller.unavailable
        ? l10n.lyricsTranslationUnavailable
        : l10n.lyricsTranslate;
    return GlassIconButton(
      icon: Icons.translate_rounded,
      tooltip: label,
      size: size,
      iconSize: iconSize,
      tapSize: tapSize,
      glass: glass,
      selected: active,
      onPressed: !controller.available
          ? null
          : active
          ? controller.cancel
          : controller.translate,
    );
  }
}

/// 与播放器底栏的「歌词 / 队列」切换同一风格的翻译开关（图标 + 激活小圆点），
/// 用在控制卡片的底栏里，不再是浮在歌词旁的白色圆形按钮。
class LyricsTranslationToggle extends StatelessWidget {
  const LyricsTranslationToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LyricsTranslationController>();
    final l10n = context.l10n;
    final primary = Theme.of(context).colorScheme.primary;
    final active = controller.lines != null || controller.busy;
    final label = controller.busy
        ? l10n.lyricsTranslating
        : controller.lines != null
        ? l10n.lyricsCancelTranslation
        : controller.failed
        ? l10n.lyricsTranslationFailed
        : controller.unavailable
        ? l10n.lyricsTranslationUnavailable
        : l10n.lyricsTranslate;
    return IconButton(
      tooltip: label,
      isSelected: active,
      onPressed: !controller.available
          ? null
          : active
          ? controller.cancel
          : controller.translate,
      icon: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.translate_rounded,
            color: active
                ? primary
                : controller.available
                ? Colors.white70
                : Colors.white24,
            size: 22,
          ),
          if (active)
            Positioned(
              bottom: -7,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
