import 'dart:async';

import '../../providers/connect_provider.dart';
import '../../providers/playback_provider.dart';
import 'system_media_controls.dart';

/// 系统媒体键（键盘媒体键、任务栏 / 锁屏 / 通知栏媒体卡片）的远程转发：
/// 播放栏处于远程模式（[ConnectProvider.controlsRemote]）时把按键发给正在播放的其他设备，返回 true；
/// 否则返回 false，由 [MediaControlsSync] 照常控制本机。
///
/// 媒体键没有界面可以提示，命令失败（免费账号部分操作会被拒）时静默忽略。
bool Function(MediaControlEvent) connectMediaRedirect(ConnectProvider connect, PlaybackProvider playback) {
  return (event) {
    if (!connect.controlsRemote(localPlaying: playback.isPlaying, localHasTrack: playback.currentTrack != null)) {
      return false;
    }
    final Future<void> command = switch (event) {
      MediaButtonEvent(button: MediaButton.play) =>
        connect.player.isAudible ? Future<void>.value() : connect.togglePlayPause(),
      MediaButtonEvent(button: MediaButton.pause || MediaButton.stop) => connect.pause(),
      MediaButtonEvent(button: MediaButton.toggle) => connect.togglePlayPause(),
      MediaButtonEvent(button: MediaButton.next) => connect.skipNext(),
      MediaButtonEvent(button: MediaButton.previous) => connect.skipPrevious(),
      MediaSeekEvent(:final position) => connect.seekTo(position.inMilliseconds),
    };
    unawaited(command.catchError((Object _) {}));
    return true;
  };
}
