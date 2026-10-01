import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/connect_provider.dart';
import '../../screens/player/device_picker_sheet.dart';
import '../cover_image.dart';
import 'connect_actions.dart';
import 'connect_device_icon.dart';
import 'remote_progress.dart';

/// 桌面端播放栏的远程模式：内容与按钮作用于正在使用的远程设备。
///
/// 布局与本机播放栏一致（左曲目 / 中控制 + 进度 / 右设备与音量），
/// 下方多一条强调色细条「正在 {设备} 上播放」，与官方桌面端相同；点细条或设备键打开设备面板。
class RemotePlayerBar extends StatelessWidget {
  const RemotePlayerBar({super.key});

  /// 主体高度与本机播放栏相同；细条另计。
  static const double barHeight = 90;
  static const double stripHeight = 26;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sideWidth = (constraints.maxWidth * 0.28).clamp(160.0, 300.0);
                  return Row(
                    children: [
                      SizedBox(width: sideWidth, child: const _RemoteTrackInfo()),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [RemoteTransportControls(), RemoteScrubber()],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: sideWidth, child: const _RemoteRightControls()),
                    ],
                  );
                },
              ),
            ),
          ),
          const RemotePlayingStrip(height: stripHeight),
        ],
      ),
    );
  }
}

/// 远程曲目：封面 + 标题 + 艺人（补全前回退为专辑名）。
class _RemoteTrackInfo extends StatelessWidget {
  const _RemoteTrackInfo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connect = context.watch<ConnectProvider>();
    final player = connect.player;
    final track = connect.remoteTrack;
    final title = track?.name ?? player.title;
    final subtitle = track?.artistNames ?? player.albumTitle;
    return Row(
      children: [
        CoverImage(url: track?.coverUrl ?? player.imageUrl, size: 56, borderRadius: BorderRadius.circular(8)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 远程播放控制：随机 / 上一首 / 播放暂停 / 下一首 / 循环。
class RemoteTransportControls extends StatelessWidget {
  /// 手机等窄处可以去掉随机与循环。
  final bool showModes;

  const RemoteTransportControls({super.key, this.showModes = true});

  /// M3 IconButton 默认补到 48px 点击区，这里收紧到 32px（与本机播放栏一致）。
  static final ButtonStyle _compact = IconButton.styleFrom(
    fixedSize: const Size.square(32),
    minimumSize: const Size.square(32),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connect = context.watch<ConnectProvider>();
    final player = connect.player;
    final l10n = context.l10n;

    Widget button(IconData icon, String tooltip, Future<void> Function() action, {Color? color, double size = 22}) {
      return IconButton(
        icon: Icon(icon, size: size),
        color: color ?? colorScheme.onSurface,
        tooltip: tooltip,
        style: _compact,
        onPressed: () => ConnectActions.run(context, action),
      );
    }

    final repeatIcon = player.repeatTrack ? Icons.repeat_one_rounded : Icons.repeat_rounded;
    final repeatOn = player.repeatContext || player.repeatTrack;
    // 提示文字描述「点按后会怎样」，与本机播放控件一致
    final repeatTooltip = player.repeatTrack
        ? l10n.playerRepeatOff
        : (player.repeatContext ? l10n.playerRepeatOneOn : l10n.playerRepeatOn);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showModes) ...[
          button(
            Icons.shuffle_rounded,
            player.shuffle ? l10n.playerShuffleOff : l10n.playerShuffleOn,
            connect.toggleShuffle,
            color: player.shuffle ? colorScheme.primary : colorScheme.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 8),
        ],
        button(Icons.skip_previous_rounded, l10n.playerPrevious, connect.skipPrevious),
        const SizedBox(width: 10),
        // 深色：白底黑图标；浅色：黑底白图标（与本机播放栏一致）
        Material(
          color: colorScheme.onSurface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => ConnectActions.run(context, connect.togglePlayPause),
            child: SizedBox.square(
              dimension: 36,
              child: Icon(
                player.isAudible ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 22,
                color: colorScheme.surface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        button(Icons.skip_next_rounded, l10n.playerNext, connect.skipNext),
        if (showModes) ...[
          const SizedBox(width: 8),
          button(
            repeatIcon,
            repeatTooltip,
            connect.cycleRepeat,
            color: repeatOn ? colorScheme.primary : colorScheme.onSurfaceVariant,
            size: 18,
          ),
        ],
      ],
    );
  }
}

/// 右侧：设备键（强调色，表示正在遥控）+ 远程音量。
class _RemoteRightControls extends StatelessWidget {
  const _RemoteRightControls();

  static const double _sliderWidth = 92;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final connect = context.watch<ConnectProvider>();
    final device = connect.activeDevice;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSlider = device != null && device.supportsVolume && constraints.maxWidth >= 40 + _sliderWidth + 40;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(device == null ? Icons.devices_rounded : connectDeviceIcon(device.type), size: 20),
              color: tokens.accent,
              tooltip: context.l10n.deviceConnectTitle,
              onPressed: () => DevicePickerSheet.show(context),
            ),
            if (showSlider)
              SizedBox(
                width: _sliderWidth,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                  ),
                  child: Slider(value: connect.volume, onChanged: connect.setVolume),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 「正在 {设备} 上播放」强调色细条；点按打开设备面板。
class RemotePlayingStrip extends StatelessWidget {
  final double height;

  const RemotePlayingStrip({super.key, this.height = 26});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final device = context.select<ConnectProvider, (String, IconData)?>((c) {
      final d = c.activeDevice;
      return d == null ? null : (d.name, connectDeviceIcon(d.type));
    });
    if (device == null) return const SizedBox.shrink();
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: tokens.onAccent, fontWeight: FontWeight.w700);
    return Material(
      color: tokens.accent,
      child: InkWell(
        onTap: () => DevicePickerSheet.show(context),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(device.$2, size: 14, color: tokens.onAccent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.l10n.connectPlayingOn(device.$1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
