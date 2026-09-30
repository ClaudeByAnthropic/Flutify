import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/mock_spotify_data.dart';
import '../../../core/theme/md3e_shapes.dart';
import '../../../core/utils/artwork_palette.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/model_labels.dart';
import '../../../models/playback_context.dart';
import '../../../models/track.dart';
import '../../../providers/playback_provider.dart';
import '../../../providers/spotify_provider.dart';
import '../../navigation/app_routes.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/playback_scrubber.dart';
import '../../widgets/player_controls.dart';
import '../../widgets/track_options_sheet.dart';
import 'device_picker_sheet.dart';
import 'lyrics_sheet.dart';
import 'queue_sheet.dart';

/// 全屏播放器（移动端底部全屏面板 / 桌面端居中对话框）。
///
/// 本组件只在切歌或播放上下文变化时重建；进度条、播放按钮、随机/循环、
/// 点赞按钮均为独立订阅的子组件。
class FullPlayerSheet extends StatelessWidget {
  const FullPlayerSheet({super.key});

  /// 根据窗口宽度选择以底部面板或对话框形式打开。
  static Future<void> show(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    if (isDesktop) {
      return showDialog(
        context: context,
        builder: (_) => const Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(24),
          child: SizedBox(width: 420, height: 720, child: FullPlayerSheet()),
        ),
      );
    }
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: false,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: const FullPlayerSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlaybackProvider, SpotifyTrack?>((p) => p.currentTrack);
    final playbackContext = context.select<PlaybackProvider, PlaybackContext>((p) => p.playbackContext);
    final colorScheme = Theme.of(context).colorScheme;
    if (track == null) return _NothingPlaying(color: colorScheme.surfaceContainerLowest);

    return ArtworkColorBuilder(
      imageUrl: track.coverUrl,
      fallback: const Color(0xFF2C2543),
      builder: (context, artColor) => AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: MD3EShapes.topSheet,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [artColor, colorScheme.surfaceContainerLowest],
            stops: const [0.0, 0.8],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              final isVeryCompact = availableHeight < 560;

              // 封面尺寸随可用高度自适应，保证控件不会被挤出屏幕
              final artSize = (availableHeight * (isVeryCompact ? 0.28 : 0.4))
                  .clamp(140.0, 380.0)
                  .clamp(140.0, constraints.maxWidth * 0.86);

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: availableHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            _TopBar(track: track, playbackContext: playbackContext),
                            const Spacer(),
                            _Artwork(url: track.coverUrl, size: artSize),
                            const Spacer(),
                            _TitleRow(track: track),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: PlaybackScrubber(
                                activeColor: Colors.white,
                                inactiveColor: Colors.white24,
                                labelColor: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  ShuffleButton(),
                                  SkipButton(next: false),
                                  PlayPauseButton(),
                                  SkipButton(next: true),
                                  RepeatButton(),
                                ],
                              ),
                            ),
                            const Spacer(),
                            const _BottomBar(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final SpotifyTrack track;
  final PlaybackContext playbackContext;

  const _TopBar({required this.track, required this.playbackContext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            color: Colors.white,
            tooltip: context.l10n.commonClose,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  context.l10n.playingFrom(playbackContext),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Colors.white.withAlpha(180),
                  ),
                ),
                if (!playbackContext.isNone) ...[
                  const SizedBox(height: 2),
                  Text(
                    playbackContext.name,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, size: 22),
            color: Colors.white,
            tooltip: context.l10n.commonMoreOptions,
            onPressed: () => TrackOptionsSheet.show(context, track),
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final String url;
  final double size;

  const _Artwork({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: MD3EShapes.roundedExtraLarge,
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: CoverImage(
          key: ValueKey(url),
          url: url,
          size: size,
          borderRadius: MD3EShapes.roundedExtraLarge,
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final SpotifyTrack track;

  const _TitleRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                GestureDetector(
                  onTap: track.artists.isEmpty
                      ? null
                      : () {
                          final a = track.artists.first;
                          AppRoutes.openArtist(context, MockSpotifyData.findArtist(a.id) ?? a);
                        },
                  child: Text(
                    track.artistNames,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          LikeButton(track: track, size: 28),
        ],
      ),
    );
  }
}

/// 没有当前曲目时的占位（例如队列被清空后面板仍打开）。
class _NothingPlaying extends StatelessWidget {
  final Color color;

  const _NothingPlaying({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: MD3EShapes.topSheet),
      child: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                tooltip: context.l10n.commonClose,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Center(
              child: EmptyState(
                icon: Icons.music_note_rounded,
                title: context.l10n.playerNothingPlayingTitle,
                message: context.l10n.playerNothingPlayingMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    final deviceName = context.select<SpotifyProvider, String?>((s) => s.activeDevice?.name);
    final primary = Theme.of(context).colorScheme.primary;
    final deviceColor = deviceName != null ? primary : Colors.white70;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: MD3EShapes.pill,
              onTap: () => DevicePickerSheet.show(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.devices_rounded, size: 16, color: deviceColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        deviceName ?? context.l10n.playerThisDevice,
                        style: TextStyle(color: deviceColor, fontWeight: FontWeight.w600, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.lyrics_outlined, color: Colors.white70, size: 20),
            tooltip: context.l10n.lyricsTitle,
            onPressed: () => LyricsSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 22),
            tooltip: context.l10n.queueTitle,
            onPressed: () => QueueSheet.show(context),
          ),
        ],
      ),
    );
  }
}
