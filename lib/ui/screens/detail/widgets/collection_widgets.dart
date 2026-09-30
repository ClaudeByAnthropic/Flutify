import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/md3e_shapes.dart';
import '../../../../core/utils/artwork_palette.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/playback_context.dart';
import '../../../../models/track.dart';
import '../../../../providers/playback_provider.dart';
import '../../../widgets/cover_image.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/player_controls.dart';
import '../../../widgets/skeleton.dart';

// 歌单 / 专辑详情页共用的头部与操作行组件。

/// 可折叠头部：封面主色渐变背景 + 居中大封面，收起后显示标题。
class CollectionAppBar extends StatelessWidget {
  final String title;
  final String coverUrl;
  final Widget? coverOverride;

  const CollectionAppBar({super.key, required this.title, required this.coverUrl, this.coverOverride});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ArtworkColorBuilder(
      imageUrl: coverUrl,
      fallback: const Color(0xFF381B5E),
      builder: (context, artColor) => SliverAppBar(
        expandedHeight: 320.0,
        pinned: true,
        backgroundColor: Color.lerp(artColor, Colors.black, 0.45),
        flexibleSpace: FlexibleSpaceBar(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          background: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [artColor, colorScheme.surface],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: MD3EShapes.roundedLarge,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 24, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: coverOverride ??
                      CoverImage(url: coverUrl, size: 180, borderRadius: MD3EShapes.roundedLarge),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 详情页大号播放按钮：
/// 正在播放该上下文 → 暂停；该上下文已暂停 → 继续；否则从头播放整个上下文。
class ContextPlayButton extends StatelessWidget {
  final List<SpotifyTrack> tracks;
  final PlaybackContext playbackContext;
  final double size;

  const ContextPlayButton({super.key, required this.tracks, required this.playbackContext, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final uri = playbackContext.uri;
    final (isPlayingThis, isThisContext) = context.select<PlaybackProvider, (bool, bool)>(
      (p) => (p.isPlayingContext(uri), p.playbackContext.uri == uri),
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: colorScheme.primary.withAlpha(90), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: colorScheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: tracks.isEmpty
              ? null
              : () {
                  final playback = context.read<PlaybackProvider>();
                  if (isPlayingThis || isThisContext) {
                    playback.togglePlayPause();
                  } else {
                    playback.playContext(tracks, playbackContext);
                  }
                },
          child: Icon(
            isPlayingThis ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.black,
            size: size * 0.6,
          ),
        ),
      ),
    );
  }
}

/// 操作行：左侧自定义按钮（收藏 / 更多等），右侧 随机 + 大播放按钮。
class CollectionActionRow extends StatelessWidget {
  final List<Widget> leading;
  final List<SpotifyTrack> tracks;
  final PlaybackContext playbackContext;

  const CollectionActionRow({
    super.key,
    required this.leading,
    required this.tracks,
    required this.playbackContext,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        ...leading,
        const Spacer(),
        ShuffleButton(size: 26, inactiveColor: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        ContextPlayButton(tracks: tracks, playbackContext: playbackContext),
      ],
    );
  }
}

/// 收藏按钮（歌单 / 专辑 / 播客通用的描边爱心）。
class SaveToggleButton extends StatelessWidget {
  final bool saved;
  final VoidCallback onPressed;

  const SaveToggleButton({super.key, required this.saved, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: saved ? context.l10n.libraryRemove : context.l10n.libraryAdd,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
        child: Icon(
          saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(saved),
          size: 28,
          color: saved ? primary : null,
        ),
      ),
      onPressed: onPressed,
    );
  }
}

/// 列表为空 / 加载中的占位（Sliver）。
///
/// 加载中显示与 TrackTile 等高的骨架行，加载完成时列表不会跳动。
class CollectionPlaceholder extends StatelessWidget {
  final bool loading;
  final String message;
  final IconData icon;

  const CollectionPlaceholder({
    super.key,
    this.loading = false,
    this.message = '',
    this.icon = Icons.queue_music_rounded,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SliverToBoxAdapter(
        child: SkeletonPulse(
          child: Column(
            children: [for (var i = 0; i < 6; i++) const _SkeletonTrackRow()],
          ),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Center(
        child: EmptyState(icon: icon, title: message, compact: true),
      ),
    );
  }
}

class _SkeletonTrackRow extends StatelessWidget {
  const _SkeletonTrackRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SkeletonBox(width: 48, height: 48, borderRadius: BorderRadius.all(Radius.circular(6))),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.6,
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(height: 13),
                ),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.35,
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(height: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
