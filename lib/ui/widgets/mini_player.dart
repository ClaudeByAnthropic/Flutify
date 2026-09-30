import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/md3e_shapes.dart';
import '../../core/utils/artwork_palette.dart';
import '../../l10n/l10n.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/spotify_provider.dart';
import '../screens/player/device_picker_sheet.dart';
import '../screens/player/full_player_sheet.dart';
import 'cover_image.dart';
import 'playback_scrubber.dart';
import 'player_controls.dart';

/// 移动端底部悬浮迷你播放器。
///
/// - 背景色取自专辑封面（与 Spotify 一致），切歌时平滑过渡。
/// - 左右滑动切换上一首 / 下一首。
/// - 只在切歌时重建；进度线与播放按钮各自局部订阅。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlaybackProvider, SpotifyTrack?>((p) => p.currentTrack);
    if (track == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return ArtworkColorBuilder(
      imageUrl: track.coverUrl,
      fallback: colorScheme.surfaceContainerHigh,
      builder: (context, artColor) {
        final background = Color.lerp(artColor, Colors.black, 0.35)!;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: background,
            borderRadius: MD3EShapes.roundedMedium,
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => FullPlayerSheet.show(context),
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v.abs() < 300) return;
                  final playback = context.read<PlaybackProvider>();
                  v < 0 ? playback.nextTrack() : playback.previousTrack();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniPlayerRow(track: track),
                    PlaybackProgressLine(
                      height: 2,
                      color: Colors.white,
                      backgroundColor: Colors.white.withAlpha(40),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayerRow extends StatelessWidget {
  final SpotifyTrack track;

  const _MiniPlayerRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeDeviceName = context.select<SpotifyProvider, String?>((s) => s.activeDevice?.name);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showDevice = width >= 340;
        final showLike = width >= 260;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
          child: Row(
            children: [
              CoverImage(url: track.coverUrl, size: 42, borderRadius: BorderRadius.circular(6.0)),
              const SizedBox(width: 10),

              // 歌名 / 艺人（或当前 Connect 设备）
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Column(
                    key: ValueKey(track.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.name,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artistNames,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              if (showDevice)
                IconButton(
                  tooltip: activeDeviceName ?? context.l10n.deviceConnectTitle,
                  icon: Icon(
                    Icons.devices_rounded,
                    color: activeDeviceName != null ? colorScheme.primary : Colors.white70,
                    size: 20,
                  ),
                  onPressed: () => DevicePickerSheet.show(context),
                ),

              if (showLike) LikeButton(track: track, size: 22),

              const PlayPauseButton(
                size: 40,
                iconSize: 26,
                background: Colors.transparent,
                foreground: Colors.white,
              ),
            ],
          ),
        );
      },
    );
  }
}
