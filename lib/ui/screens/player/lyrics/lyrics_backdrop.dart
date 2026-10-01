import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/flutify_tokens.dart';
import '../../../../core/utils/artwork_palette.dart';
import '../../../../providers/playback_provider.dart';
import '../../../widgets/liquid_artwork_background.dart';

/// 所有歌词界面共用的液态背景：封面流动模糊 + 压暗层。
///
/// 全屏歌词、全屏播放器的歌词视图、桌面右栏歌词、沉浸式歌词都使用它，观感一致。
/// 单独订阅播放状态：暂停或「减弱动效」时停止流动，且不牵连歌词重建。
class LyricsBackdrop extends StatelessWidget {
  final String imageUrl;

  const LyricsBackdrop({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.select<PlaybackProvider, bool>((p) => p.isPlaying);
    final animate = isPlaying && !context.reduceMotion;
    return ArtworkColorBuilder(
      imageUrl: imageUrl,
      fallback: const Color(0xFF1E2838),
      builder: (context, artColor) => LiquidArtworkBackground(
        imageUrl: imageUrl,
        fallback: Color.lerp(artColor, Colors.black, 0.35)!,
        animate: animate,
      ),
    );
  }
}
