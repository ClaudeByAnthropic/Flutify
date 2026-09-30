import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/md3e_shapes.dart';
import '../../../core/utils/artwork_palette.dart';
import '../../../l10n/l10n.dart';
import '../../../models/track.dart';
import '../../../providers/playback_provider.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/liquid_artwork_background.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/playback_scrubber.dart';
import '../../widgets/player_controls.dart';
import 'lyrics/lyrics_view.dart';

/// 同步歌词面板（Apple Music iOS 风格）。
///
/// 层级（自下而上）：
/// 1. 流动封面背景 [LiquidArtworkBackground]；
/// 2. 歌词滚动区 [LyricsView]，可从上下两块玻璃下方滚过；
/// 3. 顶部液态玻璃信息胶囊（封面 / 歌名 / 关闭）；
/// 4. 底部液态玻璃控制台（进度条 / 切歌 / 播放暂停）。
class LyricsSheet extends StatelessWidget {
  const LyricsSheet({super.key});

  static const double _headerHeight = 104;
  static const double _controlsHeight = 150;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const LyricsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlaybackProvider, SpotifyTrack?>((p) => p.currentTrack);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      borderRadius: MD3EShapes.topSheet,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _SheetBackground(imageUrl: track?.coverUrl ?? ''),
            if (track == null)
              Center(
                child: EmptyState(
                  icon: Icons.music_off_rounded,
                  title: context.l10n.playerNothingPlayingTitle,
                  message: context.l10n.lyricsNothingPlayingMessage,
                  onDark: true,
                ),
              )
            else
              LyricsView(
                key: ValueKey(track.id),
                trackId: track.id,
                topInset: _headerHeight,
                bottomInset: _controlsHeight + bottomSafe,
              ),
            Positioned(left: 0, right: 0, top: 0, child: _Header(track: track)),
            if (track != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + bottomSafe,
                child: const _GlassControls(),
              ),
          ],
        ),
      ),
    );
  }
}

/// 背景单独订阅播放状态：暂停时停止流动，且不牵连歌词重建。
class _SheetBackground extends StatelessWidget {
  final String imageUrl;

  const _SheetBackground({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.select<PlaybackProvider, bool>((p) => p.isPlaying);
    return ArtworkColorBuilder(
      imageUrl: imageUrl,
      fallback: const Color(0xFF1E2838),
      builder: (context, artColor) => LiquidArtworkBackground(
        imageUrl: imageUrl,
        fallback: Color.lerp(artColor, Colors.black, 0.35)!,
        animate: isPlaying,
      ),
    );
  }
}

/// 顶部：拖拽条 + 玻璃信息胶囊。
class _Header extends StatelessWidget {
  final SpotifyTrack? track;

  const _Header({required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 12),
          LiquidGlass(
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(
              children: [
                CoverImage(
                  url: track?.coverUrl ?? '',
                  size: 44,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track?.name ?? context.l10n.lyricsTitle,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track?.artistNames ?? context.l10n.lyricsNotPlaying,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (track != null) LikeButton(track: track!, size: 22, inactiveColor: Colors.white70),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                  tooltip: context.l10n.commonClose,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部玻璃控制台：进度条 + 上一首 / 播放暂停 / 下一首。
class _GlassControls extends StatelessWidget {
  const _GlassControls();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: const LiquidGlass(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          padding: EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlaybackScrubber(
                compact: true,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                labelColor: Colors.white60,
              ),
              SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SkipButton(next: false, size: 32),
                  SizedBox(width: 28),
                  PlayPauseButton(size: 56, iconSize: 32),
                  SizedBox(width: 28),
                  SkipButton(next: true, size: 32),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
