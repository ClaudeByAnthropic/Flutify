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
/// - 不可播放：说明哪首歌不能播放、是否已自动跳过；
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

    final (message, action) = switch (error.kind) {
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
          SnackBarAction(label: l10n.commonRetry, onPressed: context.read<PlaybackProvider>().togglePlayPause),
        ),
    };

    // 连续跳过多首时只保留最新一条，不排队刷屏
    messenger.hideCurrentSnackBar();
    final wide = MediaQuery.sizeOf(context).width >= 600;
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      action: action,
      behavior: SnackBarBehavior.floating,
      width: wide ? 420 : null,
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
