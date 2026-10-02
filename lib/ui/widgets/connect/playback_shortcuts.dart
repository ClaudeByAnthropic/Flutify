import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../providers/connect_provider.dart';
import '../../../providers/playback_provider.dart';
import 'connect_actions.dart';
import '../toast/app_toast.dart';

/// 播放类键盘快捷键（主窗口与沉浸式歌词共用，与 Spotify 桌面端一致）。
///
/// 每次按键时才判断控制对象（[ConnectActions.isRemoteNow]）：播放栏处于远程模式（在其他设备上播放）时
/// 发给远程设备，失败弹出提示；否则控制本机。远程设备不支持调音量时音量键只弹出提示。
class PlaybackShortcuts {
  PlaybackShortcuts._();

  static const double _volumeStep = 0.1;

  /// 当前主焦点是否在可编辑文本组件内（TextField 等）。
  static bool _isTextInputFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static Map<ShortcutActivator, VoidCallback> bindings(BuildContext context) {
    VoidCallback route(void Function(PlaybackProvider p) local, Future<void> Function(ConnectProvider c) remote) => () {
      if (ConnectActions.isRemoteNow(context)) {
        final connect = context.read<ConnectProvider>();
        ConnectActions.run(context, () => remote(connect));
      } else {
        local(context.read<PlaybackProvider>());
      }
    };

    VoidCallback volume(double delta) => () {
      if (ConnectActions.isRemoteNow(context)) {
        final connect = context.read<ConnectProvider>();
        final device = connect.activeDevice;
        if (device == null) return;
        if (device.supportsVolume) {
          connect.setVolume(connect.volume + delta);
        } else {
          // 连按时只保留一条提示（AppToast 默认替换当前提示）
          AppToast.show(
            context,
            context.l10n.connectVolumeUnsupported(device.name),
            icon: Icons.volume_off_rounded,
            tone: ToastTone.warning,
          );
        }
      } else {
        final playback = context.read<PlaybackProvider>();
        playback.setVolume(playback.volume + delta, persist: true);
      }
    };

    return {
      // 空格：焦点在文本输入框时应输入空格，不触发播放/暂停
      const SingleActivator(LogicalKeyboardKey.space): () {
        if (_isTextInputFocused()) return;
        route((p) => p.togglePlayPause(), (c) => c.togglePlayPause())();
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): route(
        (p) => p.nextTrack(),
        (c) => c.skipNext(),
      ),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): route(
        (p) => p.previousTrack(),
        (c) => c.skipPrevious(),
      ),
      const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): volume(_volumeStep),
      const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): volume(-_volumeStep),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): route(
        (p) => p.toggleShuffle(),
        (c) => c.toggleShuffle(),
      ),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): route(
        (p) => p.cycleRepeatMode(),
        (c) => c.cycleRepeat(),
      ),
    };
  }
}
