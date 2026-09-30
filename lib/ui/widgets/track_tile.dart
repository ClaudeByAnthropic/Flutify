import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/md3e_shapes.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/l10n.dart';
import '../../models/playback_context.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/playback_provider.dart';
import 'cover_image.dart';
import 'track_options_sheet.dart';
import 'waveform_visualizer.dart';

/// 曲目行。
///
/// 通过 `context.select` 只订阅「是否当前曲目 / 是否正在播放 / 是否已点赞」，
/// 播放进度变化、其它曲目切换都不会让整张列表重建。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (isCurrent, isPlaying) = context.select<PlaybackProvider, (bool, bool)>((p) {
      final current = p.isCurrent(track.id);
      return (current, current && p.isPlaying);
    });
    final isLiked = context.select<LibraryProvider, bool>((l) => l.isLiked(track.id));

    return InkWell(
      onTap: onTap ??
          () => context.read<PlaybackProvider>().playTrack(
                track,
                contextQueue: contextQueue,
                context: playbackContext,
              ),
      onLongPress: () => TrackOptionsSheet.show(context, track),
      borderRadius: MD3EShapes.roundedMedium,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // 序号或跳动波形
            if (index != null && !showCover)
              SizedBox(
                width: 32,
                child: Center(
                  child: isCurrent
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
                    if (isCurrent)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Center(
                          child: WaveformVisualizer(isPlaying: isPlaying, color: colorScheme.primary),
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
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            IconButton(
              icon: Icon(
                isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isLiked ? colorScheme.primary : colorScheme.onSurfaceVariant,
                size: 22,
              ),
              tooltip: isLiked ? context.l10n.likeRemove : context.l10n.likeAdd,
              onPressed: () => context.read<LibraryProvider>().toggleLike(track),
            ),

            Text(
              Formatters.formatDurationMs(track.durationMs),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),

            IconButton(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              color: colorScheme.onSurfaceVariant,
              tooltip: context.l10n.commonMoreOptions,
              onPressed: () => TrackOptionsSheet.show(context, track),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「E」显式内容角标。
class _ExplicitBadge extends StatelessWidget {
  const _ExplicitBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
      margin: const EdgeInsets.only(right: 6.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(60),
        borderRadius: BorderRadius.circular(3.0),
      ),
      child: const Text(
        'E',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}
