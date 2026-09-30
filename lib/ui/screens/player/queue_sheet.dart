import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/md3e_shapes.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/playback_provider.dart';
import '../../widgets/cover_image.dart';

/// 播放队列面板：Now playing / Next in queue / Next from: 上下文。
/// 两个列表都支持拖拽排序、左滑移除、点击跳播。
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => const QueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 进度不再触发 PlaybackProvider 通知，这里直接 watch 也只会在队列/切歌时重建
    final playback = context.watch<PlaybackProvider>();
    final current = playback.currentTrack;
    final userQueue = playback.userQueue;
    final upNext = playback.upNext;
    final ctx = playback.playbackContext;
    final l10n = context.l10n;

    // 背景必须是 Material 而不是带颜色的 DecoratedBox，否则 ListTile 的水波纹会被遮住
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: MD3EShapes.topSheet),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.queueTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      l10n.commonDone,
                      style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (current != null) ...[
                    _SectionHeader(title: l10n.nowPlaying),
                    SliverToBoxAdapter(
                      child: _QueueRow(
                        coverUrl: current.coverUrl,
                        title: current.name,
                        subtitle: current.artistNames,
                        highlighted: true,
                      ),
                    ),
                  ],

                  if (userQueue.isNotEmpty) ...[
                    _SectionHeader(
                      title: l10n.queueNextInQueue,
                      action: TextButton(onPressed: playback.clearUserQueue, child: Text(l10n.queueClear)),
                    ),
                    SliverReorderableList(
                      itemCount: userQueue.length,
                      onReorderItem: playback.reorderUserQueue,
                      itemBuilder: (context, i) {
                        final entry = userQueue[i];
                        return _DismissibleRow(
                          key: ValueKey('uq_${entry.uid}'),
                          index: i,
                          onDismissed: () => playback.removeFromUserQueue(i),
                          onTap: () => playback.playFromUserQueue(i),
                          coverUrl: entry.track.coverUrl,
                          title: entry.track.name,
                          subtitle: entry.track.artistNames,
                        );
                      },
                    ),
                  ],

                  if (upNext.isNotEmpty) ...[
                    _SectionHeader(title: ctx.isNone ? l10n.queueNextUp : l10n.queueNextFrom(ctx.name)),
                    SliverReorderableList(
                      itemCount: upNext.length,
                      onReorderItem: playback.reorderUpNext,
                      itemBuilder: (context, i) {
                        final entry = upNext[i];
                        return _DismissibleRow(
                          key: ValueKey('ctx_${entry.uid}'),
                          index: i,
                          onDismissed: () => playback.removeFromUpNext(i),
                          onTap: () => playback.playFromUpNext(i),
                          coverUrl: entry.track.coverUrl,
                          title: entry.track.name,
                          subtitle: entry.track.artistNames,
                        );
                      },
                    ),
                  ],

                  if (userQueue.isEmpty && upNext.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(l10n.queueEmpty, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// 可左滑删除、可拖拽排序的队列行。
class _DismissibleRow extends StatelessWidget {
  final int index;
  final VoidCallback onDismissed;
  final VoidCallback onTap;
  final String coverUrl;
  final String title;
  final String subtitle;

  const _DismissibleRow({
    super.key,
    required this.index,
    required this.onDismissed,
    required this.onTap,
    required this.coverUrl,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.redAccent,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: _QueueRow(
          coverUrl: coverUrl,
          title: title,
          subtitle: subtitle,
          onTap: onTap,
          trailing: ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.drag_handle_rounded, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final String coverUrl;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _QueueRow({
    required this.coverUrl,
    required this.title,
    required this.subtitle,
    this.highlighted = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 20, right: 8),
      onTap: onTap,
      leading: CoverImage(url: coverUrl, size: 44, borderRadius: BorderRadius.circular(6)),
      title: Text(
        title,
        style: TextStyle(color: highlighted ? colorScheme.primary : colorScheme.onSurface, fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }
}
