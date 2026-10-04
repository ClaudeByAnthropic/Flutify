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
  final double size;
  final bool glass;

  const LyricsTranslationButton({super.key, this.size = 36, this.glass = true});

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
