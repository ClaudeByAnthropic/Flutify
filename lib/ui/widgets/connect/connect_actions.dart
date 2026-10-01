import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/connect_cluster.dart';
import '../../../providers/connect_provider.dart';
import '../../../providers/playback_provider.dart';

/// 本机播放与远程设备之间的协调（涉及两个 Provider，放在 UI 层）。
///
/// 所有方法都在第一个 await 之前取完 Provider 与 ScaffoldMessenger：
/// 调用方（设备面板）往往随即关闭，之后不能再用它的 context。
class ConnectActions {
  ConnectActions._();

  /// 播放栏是否切换为远程模式：
  /// - 本机正在出声 → 本机优先；
  /// - 远程正在出声 → 远程；
  /// - 远程已暂停、本机没有曲目 → 远程（显示远程上次的曲目，可一键继续）。
  static bool showRemote(BuildContext context) {
    final remote = context.select<ConnectProvider?, (bool, bool)>(
      (c) => (c?.hasRemoteSession ?? false, c?.player.isAudible ?? false),
    );
    if (!remote.$1) return false;
    final local = context.select<PlaybackProvider, (bool, bool)>((p) => (p.isPlaying, p.currentTrack != null));
    if (local.$1) return false;
    return remote.$2 || !local.$2;
  }

  /// 转移到远程设备：先暂停本机，避免两边同时出声。
  static Future<void> transferTo(BuildContext context, ConnectDevice device) {
    final playback = context.read<PlaybackProvider>();
    final connect = context.read<ConnectProvider>();
    final report = _reporter(context);
    return _guard(report, () async {
      if (playback.isPlaying) await playback.togglePlayPause();
      await connect.transferTo(device);
    });
  }

  /// 在此设备继续：暂停远程设备，本机从同一首、同一进度开始播放。
  static Future<void> takeOver(BuildContext context) {
    final connect = context.read<ConnectProvider>();
    final playback = context.read<PlaybackProvider>();
    final report = _reporter(context);
    final track = connect.remoteTrack;
    final position = connect.player.positionAt(connect.serverNowMs);
    return _guard(report, () async {
      await connect.pause();
      if (track == null) return;
      await playback.playTrack(track);
      if (position > 0) await playback.seekTo(Duration(milliseconds: position));
    });
  }

  /// 执行远程命令；失败时弹出提示（免费账号部分操作会被拒绝）。
  static Future<void> run(BuildContext context, Future<void> Function() action) => _guard(_reporter(context), action);

  static VoidCallback _reporter(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = context.l10n.connectCommandFailed;
    return () => messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> _guard(VoidCallback report, Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      report();
    }
  }
}
