import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/md3e_shapes.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/l10n.dart';
import '../../models/playback_context.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/playback_provider.dart';
import '../shell/shell_breakpoints.dart';
import 'cover_image.dart';
import 'hover_builder.dart';
import 'track_menu.dart';
import 'waveform_visualizer.dart';

/// 曲目行。
///
/// 通过 `context.select` 只订阅「是否当前曲目 / 是否正在播放 / 是否已点赞」，
/// 播放进度变化、其它曲目切换都不会让整张列表重建。
///
/// 桌面端悬停（Spotify 桌面端行为）：序号 / 封面变为 ▶（当前曲目播放中为 ⏸），
/// 未点赞的爱心与「⋯」只在悬停时出现；右键弹出曲目菜单。移动端长按弹出底部面板。
class TrackTile extends StatelessWidget {
  final SpotifyTrack track;
  final int? index;
  final bool showCover;
  final List<SpotifyTrack>? contextQueue;
  final PlaybackContext? playbackContext;
  final VoidCallback? onTap;

  const TrackTile({
    super.key,
    required this.track,
    this.index,
    this.showCover = true,
    this.contextQueue,
    this.playbackContext,
    this.onTap,
  });

  void _play(BuildContext context) {
    context.read<PlaybackProvider>().playTrack(track, contextQueue: contextQueue, context: playbackContext);
  }

  /// 悬停播放键：当前曲目 → 播放 / 暂停切换；其它曲目 → 从这首开始播放。
  void _playOrToggle(BuildContext context, bool isCurrent) {
    if (isCurrent) {
      context.read<PlaybackProvider>().togglePlayPause();
    } else if (onTap != null) {
      onTap!();
    } else {
      _play(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hoverCapable = ShellBreakpoints.isDesktop(MediaQuery.sizeOf(context).width);

    final (isCurrent, isPlaying) = context.select<PlaybackProvider, (bool, bool)>((p) {
      final current = p.isCurrent(track.id);
      return (current, current && p.isPlaying);
    });
    final isLiked = context.select<LibraryProvider, bool>((l) => l.isLiked(track.id));

    return HoverBuilder(
      builder: (context, hovered) {
        final revealed = hovered || !hoverCapable;
        final playIcon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;

        return InkWell(
          onTap: onTap ?? () => _play(context),
          onLongPress: () => TrackMenu.show(context, track),
          onSecondaryTapUp: (details) => TrackMenu.show(context, track, position: details.globalPosition),
          borderRadius: MD3EShapes.roundedMedium,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                // 序号 / 波形 / 悬停播放键
                if (index != null && !showCover)
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: hovered
                          ? _HoverPlayIcon(
                              icon: playIcon,
                              color: colorScheme.onSurface,
                              onTap: () => _playOrToggle(context, isCurrent),
                            )
                          : isCurrent
                              ? WaveformVisualizer(isPlaying: isPlaying, color: colorScheme.primary)
                              : Text(
                                  '$index',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                    ),
                  )
                else if (showCover)
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CoverImage(url: track.coverUrl, size: 48, borderRadius: BorderRadius.circular(8.0)),
                        if (isCurrent || hovered)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: Center(
                              child: hovered
                                  ? _HoverPlayIcon(
                                      icon: playIcon,
                                      color: Colors.white,
                                      onTap: () => _playOrToggle(context, isCurrent),
                                    )
                                  : WaveformVisualizer(isPlaying: isPlaying, color: colorScheme.primary),
                            ),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(width: 14),

                // 歌名与艺人
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (track.explicit) const _ExplicitBadge(),
                          Expanded(
                            child: Text(
                              track.artistNames,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: hovered ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 已点赞常驻；未点赞只在悬停时出现（保留占位，避免时长列左右跳动）
                _Reveal(
                  visible: isLiked || revealed,
                  child: IconButton(
                    icon: Icon(
                      isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isLiked ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    tooltip: isLiked ? context.l10n.likeRemove : context.l10n.likeAdd,
                    onPressed: () => context.read<LibraryProvider>().toggleLike(track),
                  ),
                ),

                Text(
                  Formatters.formatDurationMs(track.durationMs),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                _Reveal(
                  visible: revealed,
                  child: Builder(
                    // 独立 context：桌面菜单锚定在按钮下方
                    builder: (buttonContext) => IconButton(
                      icon: Icon(hoverCapable ? Icons.more_horiz_rounded : Icons.more_vert_rounded, size: 20),
                      color: colorScheme.onSurfaceVariant,
                      tooltip: context.l10n.commonMoreOptions,
                      onPressed: () => TrackMenu.show(buttonContext, track),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 悬停出现的控件：隐藏时保留占位、不响应点击。
class _Reveal extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _Reveal({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        child: child,
      ),
    );
  }
}

/// 序号 / 封面位置上的小播放键（点击不触发整行的 onTap）。
class _HoverPlayIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HoverPlayIcon({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

/// 「E」显式内容角标。
class _ExplicitBadge extends StatelessWidget {
  const _ExplicitBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
      margin: const EdgeInsets.only(right: 6.0),
      decoration: BoxDecoration(
        color: colorScheme.onSurfaceVariant.withAlpha(60),
        borderRadius: BorderRadius.circular(3.0),
      ),
      child: Text(
        'E',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: colorScheme.onSurface),
      ),
    );
  }
}
