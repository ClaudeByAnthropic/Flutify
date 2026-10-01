import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/connect_provider.dart';
import '../../screens/player/device_picker_sheet.dart';
import '../../screens/player/lyrics_sheet.dart';
import '../../shell/shell_layout_controller.dart';
import '../cover_image.dart';
import '../playback_status_button.dart';
import 'connect_device_icon.dart';
import 'remote_progress.dart';
import 'remote_transport_controls.dart';

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
    final layout = context.read<ShellLayoutController?>();
    return Row(
      children: [
        // 点封面：右栏切到「正在播放」（与本机播放栏点封面打开正在播放一致）
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => layout == null ? LyricsSheet.show(context) : layout.showTab(NowPlayingTab.details),
          child: CoverImage(url: track?.coverUrl ?? player.imageUrl, size: 56, borderRadius: BorderRadius.circular(8)),
        ),
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

/// 右侧：正在播放 / 歌词（右栏标签，远程曲目同样可看）+ 设备键（强调色，表示正在遥控）+ 远程音量。
class _RemoteRightControls extends StatelessWidget {
  const _RemoteRightControls();

  static const double _sliderWidth = 92;
  static const double _buttonSize = 36;
  static final ButtonStyle _style = IconButton.styleFrom(
    fixedSize: const Size.square(_buttonSize),
    minimumSize: const Size.square(_buttonSize),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final connect = context.watch<ConnectProvider>();
    final device = connect.activeDevice;
    // 「播放状态」键：三栏框架下开关右栏；没有框架（单独使用播放栏）时回退为底部歌词面板
    final layout = context.watch<ShellLayoutController?>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final showPanels = constraints.maxWidth >= 2 * _buttonSize;
        final used = (showPanels ? 2 : 1) * _buttonSize;
        final showSlider = device != null && device.supportsVolume && constraints.maxWidth >= used + _sliderWidth + 8;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showPanels) PlaybackStatusButton(layout: layout, style: _style),
            IconButton(
              icon: Icon(device == null ? Icons.devices_rounded : connectDeviceIcon(device.type), size: 20),
              color: tokens.accent,
              tooltip: context.l10n.deviceConnectTitle,
              style: _style,
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
