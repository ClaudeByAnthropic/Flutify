import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/track.dart';
import '../../providers/connect_provider.dart';
import '../../providers/playback_provider.dart';
import '../navigation/app_routes.dart';
import '../screens/player/device_picker_sheet.dart';
import '../screens/player/full_player_sheet.dart';
import '../screens/player/immersive_lyrics_screen.dart';
import '../screens/player/queue_sheet.dart';
import '../shell/shell_layout_controller.dart';
import 'connect/connect_actions.dart';
import 'connect/remote_player_bar.dart';
import 'cover_image.dart';
import 'playback_scrubber.dart';
import 'playback_status_button.dart';
import 'player_controls.dart';

/// 桌面端底部通栏播放器（Spotify PC 风格）。
///
/// 本组件只在切歌时重建；控制按钮、进度条、音量各自局部订阅。
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    // 正在遥控其他设备时整条换成远程播放栏
    if (ConnectActions.showRemote(context)) return const RemotePlayerBar();
    final colorScheme = Theme.of(context).colorScheme;
    final track = context.select<PlaybackProvider, SpotifyTrack?>((p) => p.currentTrack);
    // 与窗口底色相同、无分隔线：播放栏与三栏面板靠色阶区分（Spotify 新版桌面端）
    final decoration = BoxDecoration(color: colorScheme.surfaceContainerLowest);

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
              SizedBox(
                width: sideWidth,
                child: _NowPlayingInfo(track: track),
              ),
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
                            // 深色：白底黑图标；浅色：黑底白图标
                            PlayPauseButton(
                              size: 36,
                              iconSize: 22,
                              background: colorScheme.onSurface,
                              foreground: colorScheme.surface,
                            ),
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
              SizedBox(width: sideWidth, child: const _RightControls()),
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
          decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
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
                        AppRoutes.openArtist(context, a);
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
          style: widget.style?.copyWith(decoration: _hover && widget.onTap != null ? TextDecoration.underline : null),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// 播放栏右侧的 32px 小图标按钮样式。
///
/// M3 的 IconButton 默认把点击区域补到 48px，`constraints` 无法缩小它，
/// 这里显式收紧，否则 5 个按钮 + 音量条在 300px 内放不下。
final ButtonStyle _barIconStyle = IconButton.styleFrom(
  fixedSize: const Size.square(_RightControls.buttonSize),
  minimumSize: const Size.square(_RightControls.buttonSize),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

class _RightControls extends StatelessWidget {
  const _RightControls();

  static const double buttonSize = 32;
  static const double _sliderWidth = 92;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 远程设备有会话（已暂停）时设备键高亮，提示可以转回去
    final hasDevice = context.select<ConnectProvider?, bool>((c) => c?.hasRemoteSession ?? false);
    // 三栏框架下：「播放状态」开关右栏（正在播放 / 歌词在右栏里切换），队列直达队列标签；
    // 没有框架（单独使用播放栏）时回退为底部面板
    final layout = context.watch<ShellLayoutController?>();

    final buttons = <Widget>[
      PlaybackStatusButton(layout: layout, style: _barIconStyle),
      IconButton(
        icon: const Icon(Icons.queue_music_rounded, size: 20),
        color: layout != null && layout.rightPanelVisible && layout.tab == NowPlayingTab.queue
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
        tooltip: context.l10n.queueTitle,
        style: _barIconStyle,
        onPressed: layout == null ? () => QueueSheet.show(context) : () => layout.showTab(NowPlayingTab.queue),
      ),
      IconButton(
        icon: Icon(
          Icons.devices_rounded,
          size: 20,
          color: hasDevice ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        tooltip: context.l10n.deviceConnectTitle,
        style: _barIconStyle,
        onPressed: () => DevicePickerSheet.show(context),
      ),
      IconButton(
        icon: const Icon(Icons.open_in_full_rounded, size: 18),
        color: colorScheme.onSurfaceVariant,
        tooltip: context.l10n.lyricsImmersive,
        style: _barIconStyle,
        onPressed: () => ImmersiveLyricsScreen.open(context),
      ),
    ];

    // 按实际可用宽度逐级隐藏：先去掉音量滑块，再去掉音量键
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = buttons.length * (buttonSize + 4);
        final showVolume = constraints.maxWidth >= base + buttonSize;
        final showSlider = constraints.maxWidth >= base + buttonSize + _sliderWidth + 8;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (final b in buttons) Padding(padding: const EdgeInsets.only(left: 4), child: b),
            if (showVolume) _VolumeControl(showSlider: showSlider, sliderWidth: _sliderWidth),
          ],
        );
      },
    );
  }
}

/// 音量：点击图标静音 / 恢复；拖动时实时生效，松手后持久化。
class _VolumeControl extends StatelessWidget {
  final bool showSlider;
  final double sliderWidth;

  const _VolumeControl({required this.showSlider, required this.sliderWidth});

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
          style: _barIconStyle,
          onPressed: playback.toggleMute,
        ),
        if (showSlider)
          SizedBox(
            width: sliderWidth,
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
