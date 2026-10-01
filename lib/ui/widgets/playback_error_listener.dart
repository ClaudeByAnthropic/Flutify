import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/playback_provider.dart';
import '../../services/protocol/track_playback_exception.dart';
import '../screens/auth/login_screen.dart';

/// 订阅 [PlaybackProvider.playbackErrors]，每次播放失败弹一条浮动提示。
///
/// - 未登录：提示登录，并带「登录」按钮；
/// - 不可播放：说明哪首歌不能播放、是否已自动跳过；连续多首失败已自动暂停时带「下一首」；
/// - 网络错误：提示检查网络，带「重试」按钮（重新播放当前曲目）。
///
/// 放在 [MainShell] 的 Scaffold 之内，桌面与移动端共用。
class PlaybackErrorListener extends StatefulWidget {
  final Widget child;

  const PlaybackErrorListener({super.key, required this.child});

  @override
  State<PlaybackErrorListener> createState() => _PlaybackErrorListenerState();
}

class _PlaybackErrorListenerState extends State<PlaybackErrorListener> {
  StreamSubscription<PlaybackError>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<PlaybackProvider>().playbackErrors.listen(_show);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _show(PlaybackError error) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!mounted || messenger == null) return;
    final l10n = context.l10n;
    final track = error.track.name;

    final playback = context.read<PlaybackProvider>();
    final (message, action) = switch (error.kind) {
      // 连续多首不可播放、已按设置暂停：给「下一首」让用户手动继续
      TrackPlaybackFailure.unavailable when error.autoPaused => (
        l10n.playbackErrorAutoPaused(error.consecutiveFailures),
        SnackBarAction(label: l10n.playerNext, onPressed: playback.nextTrack),
      ),
      TrackPlaybackFailure.notSignedIn => (
        l10n.playbackErrorSignIn,
        SnackBarAction(label: l10n.shellSignIn, onPressed: () => LoginScreen.open(context)),
      ),
      TrackPlaybackFailure.unavailable => (
        error.skipped ? l10n.playbackErrorSkipped(track) : l10n.playbackErrorUnavailable(track),
        null,
      ),
      TrackPlaybackFailure.network => (
        l10n.playbackErrorNetwork(track),
        SnackBarAction(label: l10n.commonRetry, onPressed: playback.togglePlayPause),
      ),
    };

    final icon = switch (error.kind) {
      TrackPlaybackFailure.unavailable when error.autoPaused => Icons.pause_circle_outline_rounded,
      TrackPlaybackFailure.notSignedIn => Icons.lock_outline_rounded,
      TrackPlaybackFailure.unavailable => Icons.music_off_rounded,
      TrackPlaybackFailure.network => Icons.wifi_off_rounded,
    };

    // 连续跳过多首时只保留最新一条，不排队刷屏
    messenger.hideCurrentSnackBar();
    // 外观与位置都交给主题和当前外壳（见 DesktopShell）：这里不传 margin / width，
    // 否则弹出后再拖动窗口，按旧宽度算出的边距会把内容挤成 0 宽。
    // 带按钮的提示在新版 Flutter 默认常驻不消失，这里显式设为到时自动收起。
    messenger.showSnackBar(
      SnackBar(
        content: _ToastContent(icon: icon, message: message),
        action: action,
        persist: false,
        duration: action == null ? _duration : _durationWithAction,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
      ),
    );
  }

  /// 纯提示的停留时长；带按钮的多给几秒，留出点按的时间。
  static const Duration _duration = Duration(seconds: 4);
  static const Duration _durationWithAction = Duration(seconds: 7);

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 提示内容：左侧浅色调圆形图标（表明错误类型）+ 最多两行说明。
class _ToastContent extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ToastContent({required this.icon, required this.message});

  /// 可用宽度低于此值时收起左侧图标，把空间全部留给文字（兜底，正常布局不会触发）。
  static const double _iconMinWidth = 160;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = Text(message, maxLines: 2, overflow: TextOverflow.ellipsis);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _iconMinWidth) return text;
        return Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: colorScheme.inversePrimary.withAlpha(40), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: colorScheme.inversePrimary),
            ),
            const SizedBox(width: 12),
            Expanded(child: text),
          ],
        );
      },
    );
  }
}
