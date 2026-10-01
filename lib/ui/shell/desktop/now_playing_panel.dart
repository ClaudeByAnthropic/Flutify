import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../models/track.dart';
import '../../../providers/playback_provider.dart';
import '../../screens/player/immersive_lyrics_screen.dart';
import '../../screens/player/lyrics/glass_icon_button.dart';
import '../../screens/player/lyrics/lyrics_backdrop.dart';
import '../../screens/player/lyrics/lyrics_view.dart';
import '../../screens/player/queue_list.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/filter_pill.dart';
import '../panel_surface.dart';
import '../shell_layout_controller.dart';
import 'now_playing_details.dart';

/// 桌面端右栏：「正在播放 / 播放队列 / 歌词」三个标签 + 关闭按钮。
///
/// 标签由 [ShellLayoutController] 管理，播放栏上的按钮与这里的胶囊共用同一状态；
/// 无播放内容时「正在播放」与「歌词」显示空状态，「播放队列」照常可用。
class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<ShellLayoutController>();
    final track = context.select<PlaybackProvider, SpotifyTrack?>((p) => p.currentTrack);
    final l10n = context.l10n;

    final labels = {
      NowPlayingTab.details: l10n.nowPlaying,
      NowPlayingTab.queue: l10n.queueTitle,
      NowPlayingTab.lyrics: l10n.lyricsTitle,
    };

    return PanelSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry in labels.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterPill(
                              label: entry.value,
                              isSelected: layout.tab == entry.key,
                              onTap: () => layout.selectTab(entry.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: l10n.shellHidePanel,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: layout.closeRightPanel,
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: context.motion(const Duration(milliseconds: 220)),
              switchInCurve: Curves.easeOutCubic,
              child: KeyedSubtree(
                key: ValueKey(layout.tab),
                child: switch (layout.tab) {
                  NowPlayingTab.queue => const QueueList(horizontalPadding: 16),
                  NowPlayingTab.details => track == null
                      ? _Nothing(title: l10n.playerNothingPlayingTitle, message: l10n.playerNothingPlayingMessage)
                      : NowPlayingDetails(track: track),
                  NowPlayingTab.lyrics => track == null
                      ? _Nothing(title: l10n.lyricsNotPlaying, message: l10n.lyricsNothingPlayingMessage)
                      : _LyricsCard(track: track),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌词卡片：与全屏歌词同一套液态玻璃观感（流动封面背景 + 白色对焦歌词），
/// 右上角玻璃按钮进入桌面沉浸式歌词。
class _LyricsCard extends StatelessWidget {
  final SpotifyTrack track;

  const _LyricsCard({required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: context.tokens.radius(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LyricsBackdrop(imageUrl: track.coverUrl),
            LyricsView(
              key: ValueKey(track.id),
              trackId: track.id,
              topInset: 56,
              bottomInset: 16,
              fontSize: 24,
              horizontalPadding: 20,
            ),
            Positioned(
              top: 10,
              right: 10,
              child: GlassIconButton(
                icon: Icons.open_in_full_rounded,
                tooltip: context.l10n.lyricsImmersive,
                size: 36,
                onPressed: () => ImmersiveLyricsScreen.open(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nothing extends StatelessWidget {
  final String title;
  final String message;

  const _Nothing({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(icon: Icons.music_note_rounded, title: title, message: message),
    );
  }
}
