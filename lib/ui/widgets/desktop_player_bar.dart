import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/mock_spotify_data.dart';
import '../../l10n/l10n.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/spotify_provider.dart';
import '../navigation/app_routes.dart';
import '../screens/player/device_picker_sheet.dart';
import '../screens/player/full_player_sheet.dart';
import '../screens/player/lyrics_sheet.dart';
import '../screens/player/queue_sheet.dart';
import 'cover_image.dart';
import 'playback_scrubber.dart';
import 'player_controls.dart';

/// 桌面端底部通栏播放器（Spotify PC 风格）。
///
/// 本组件只在切歌时重建；控制按钮、进度条、音量各自局部订阅。
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final track = context.select<PlaybackProvider, SpotifyTrack?>((p) => p.currentTrack);
    final decoration = BoxDecoration(
      color: colorScheme.surfaceContainerLowest,
      border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(80), width: 1)),
    );

    // 无曲目时保留 90dp 通栏高度并显示占位，避免内容区高度跳变
    if (track == null) {
      return Container(
        height: 90,
        decoration: decoration,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: const _IdleBar(),
      );
    }

    return Container(
      height: 90,
      decoration: decoration,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final sideWidth = (totalWidth * 0.28).clamp(160.0, 300.0);

          return Row(
            children: [
              SizedBox(width: sideWidth, child: _NowPlayingInfo(track: track)),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ShuffleButton(size: 18, inactiveColor: colorScheme.onSurfaceVariant, constraints: _small),
                            const SizedBox(width: 8),
                            SkipButton(next: false, size: 22, color: colorScheme.onSurface, constraints: _small),
                            const SizedBox(width: 10),
                            const PlayPauseButton(size: 36, iconSize: 22),
                            const SizedBox(width: 10),
                            SkipButton(next: true, size: 22, color: colorScheme.onSurface, constraints: _small),
                            const SizedBox(width: 8),
                            RepeatButton(size: 18, inactiveColor: colorScheme.onSurfaceVariant, constraints: _small),
                          ],
                        ),
                        const PlaybackScrubber(compact: true),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: sideWidth,
                child: _RightControls(showVolume: totalWidth >= 700, showVolumeSlider: totalWidth >= 900),
              ),
            ],
          );
        },
      ),
    );
  }

  static const BoxConstraints _small = BoxConstraints(minWidth: 32, minHeight: 32);
}

/// 空闲状态：灰色封面占位 + 提示文字 + 禁用的播放键。
class _IdleBar extends StatelessWidget {
  const _IdleBar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.music_note_rounded, color: colorScheme.onSurfaceVariant.withAlpha(140)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l10n.playerIdleHint,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(Icons.play_circle_fill_rounded, size: 40, color: colorScheme.onSurfaceVariant.withAlpha(80)),
        const Spacer(),
      ],
    );
  }
}

class _NowPlayingInfo extends StatelessWidget {
  final SpotifyTrack track;

  const _NowPlayingInfo({required this.track});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Tooltip(
          message: context.l10n.openNowPlaying,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => FullPlayerSheet.show(context),
            child: CoverImage(url: track.coverUrl, size: 56, borderRadius: BorderRadius.circular(8.0)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HoverLink(
                text: track.name,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: colorScheme.onSurface),
                onTap: track.album == null ? null : () => AppRoutes.openAlbum(context, track.album!),
              ),
              const SizedBox(height: 2),
              _HoverLink(
                text: track.artistNames,
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                onTap: track.artists.isEmpty
                    ? null
                    : () {
                        final a = track.artists.first;
                        AppRoutes.openArtist(context, MockSpotifyData.findArtist(a.id) ?? a);
                      },
              ),
            ],
          ),
        ),
        LikeButton(track: track, size: 20, inactiveColor: colorScheme.onSurfaceVariant),
      ],
    );
  }
}

/// 悬停时显示下划线的文字链接（桌面端交互习惯）。
class _HoverLink extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final VoidCallback? onTap;

  const _HoverLink({required this.text, this.style, this.onTap});

  @override
  State<_HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<_HoverLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.text,
          style: widget.style?.copyWith(
            decoration: _hover && widget.onTap != null ? TextDecoration.underline : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _RightControls extends StatelessWidget {
  final bool showVolume;
  final bool showVolumeSlider;

  const _RightControls({required this.showVolume, required this.showVolumeSlider});

  static const BoxConstraints _small = BoxConstraints(minWidth: 32, minHeight: 32);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDevice = context.select<SpotifyProvider, bool>((s) => s.activeDevice != null);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          icon: const Icon(Icons.lyrics_outlined, size: 20),
          color: colorScheme.onSurfaceVariant,
          tooltip: context.l10n.lyricsTitle,
          padding: EdgeInsets.zero,
          constraints: _small,
          onPressed: () => LyricsSheet.show(context),
        ),
        IconButton(
          icon: const Icon(Icons.queue_music_rounded, size: 20),
          color: colorScheme.onSurfaceVariant,
          tooltip: context.l10n.queueTitle,
          padding: EdgeInsets.zero,
          constraints: _small,
          onPressed: () => QueueSheet.show(context),
        ),
        IconButton(
          icon: Icon(
            Icons.devices_rounded,
            size: 20,
            color: hasDevice ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          tooltip: context.l10n.deviceConnectTitle,
          padding: EdgeInsets.zero,
          constraints: _small,
          onPressed: () => DevicePickerSheet.show(context),
        ),
        if (showVolume) _VolumeControl(showSlider: showVolumeSlider),
      ],
    );
  }
}

/// 音量：点击图标静音 / 恢复；拖动时实时生效，松手后持久化。
class _VolumeControl extends StatelessWidget {
  final bool showSlider;

  const _VolumeControl({required this.showSlider});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final volume = context.select<PlaybackProvider, double>((p) => p.volume);
    final playback = context.read<PlaybackProvider>();

    final icon = volume == 0
        ? Icons.volume_off_rounded
        : volume < 0.5
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, size: 18),
          color: colorScheme.onSurfaceVariant,
          tooltip: volume == 0 ? context.l10n.playerUnmute : context.l10n.playerMute,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: playback.toggleMute,
        ),
        if (showSlider)
          SizedBox(
            width: 92,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              ),
              child: Slider(
                value: volume,
                onChanged: (v) => playback.setVolume(v),
                onChangeEnd: (v) => playback.setVolume(v, persist: true),
              ),
            ),
          ),
      ],
    );
  }
}
