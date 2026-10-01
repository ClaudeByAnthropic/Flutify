import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/flutify_tokens.dart';
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

/// 移动端悬浮胶囊迷你播放器（位于毛玻璃底部导航上方）。
///
/// - 胶囊形、背景色取自专辑封面并压暗（与 Spotify 一致），切歌时平滑过渡；
/// - 底部内缩的 2px 细进度线；
/// - 左右滑动切换上一首 / 下一首，点击展开全屏播放器；
/// - 只在切歌时重建；进度线与播放按钮各自局部订阅。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlaybackProvider, SpotifyTrack?>((p) => p.currentTrack);
    if (track == null) return const SizedBox.shrink();

    // 方正风格下胶囊换成 16px 圆角矩形，其余风格保持胶囊
    final tokens = context.tokens;
    final ShapeBorder shape =
        tokens.squareCorners ? RoundedRectangleBorder(borderRadius: tokens.radius(16)) : const StadiumBorder();

    return ArtworkColorBuilder(
      imageUrl: track.coverUrl,
      // 前景固定为白色，取色前 / 无封面时用深石墨色兜底（inverseSurface 在深色主题下是浅色）
      fallback: const Color(0xFF3A3A42),
      builder: (context, artColor) {
        final background = Color.lerp(artColor, Colors.black, 0.35)!;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          decoration: ShapeDecoration(
            color: background,
            shape: shape,
            shadows: [
              BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 20, offset: const Offset(0, 6)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: shape,
              onTap: () => FullPlayerSheet.show(context),
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v.abs() < 300) return;
                  final playback = context.read<PlaybackProvider>();
                  v < 0 ? playback.nextTrack() : playback.previousTrack();
                },
                child: Stack(
                  children: [
                    _MiniPlayerRow(track: track),
                    // 细进度线：左右内缩到胶囊直线段内，避开两端圆弧
                    Positioned(
                      left: 28,
                      right: 28,
                      bottom: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: PlaybackProgressLine(
                          height: 2,
                          color: Colors.white,
                          backgroundColor: Colors.white.withAlpha(40),
                        ),
                      ),
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
          padding: const EdgeInsets.fromLTRB(7, 7, 8, 9),
          child: Row(
            children: [
              CoverImage(url: track.coverUrl, size: 44, circular: true),
              const SizedBox(width: 12),

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
