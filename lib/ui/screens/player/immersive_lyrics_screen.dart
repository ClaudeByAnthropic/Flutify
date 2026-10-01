import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../core/theme/system_bars.dart';
import '../../../l10n/l10n.dart';
import '../../../models/track.dart';
import '../../../providers/playback_provider.dart';
import '../../shell/desktop/desktop_window.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/empty_state.dart';
import 'lyrics/glass_icon_button.dart';
import 'lyrics/lyrics_backdrop.dart';
import 'lyrics/lyrics_glass_controls.dart';
import 'lyrics/lyrics_view.dart';

/// 桌面沉浸式歌词（Apple Music macOS 全屏歌词风格）。
///
/// - 打开时窗口进入系统全屏，关闭时恢复；Esc / 右上角玻璃按钮退出；
/// - 宽屏：左侧大封面 + 歌名 + 玻璃控制台，右侧大字号歌词；
///   窄窗口：歌词铺满，底部玻璃控制台；
/// - 鼠标静止 3 秒后隐藏光标与退出按钮，移动即恢复；
/// - 空格播放 / 暂停，Ctrl+← / → 切歌。
class ImmersiveLyricsScreen extends StatefulWidget {
  const ImmersiveLyricsScreen({super.key});

  /// 以淡入方式推入根导航（盖住三栏框架与播放栏）。
  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: context.motion(const Duration(milliseconds: 380)),
        reverseTransitionDuration: context.motion(const Duration(milliseconds: 260)),
        pageBuilder: (_, _, _) => const ImmersiveLyricsScreen(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: Tween(begin: 1.03, end: 1.0).animate(curved), child: child),
          );
        },
      ),
    );
  }

  @override
  State<ImmersiveLyricsScreen> createState() => _ImmersiveLyricsScreenState();
}

class _ImmersiveLyricsScreenState extends State<ImmersiveLyricsScreen> {
  static const Duration _idleDelay = Duration(seconds: 3);

  /// 宽屏双栏布局的最小宽度。
  static const double _wideBreakpoint = 900;

  Timer? _idleTimer;
  bool _idle = false;

  @override
  void initState() {
    super.initState();
    DesktopWindow.setFullScreen(true);
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    DesktopWindow.setFullScreen(false);
    super.dispose();
  }

  /// 鼠标移动：显示光标与退出按钮，并重新计时。
  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (_idle) setState(() => _idle = false);
    _idleTimer = Timer(_idleDelay, () {
      if (mounted) setState(() => _idle = true);
    });
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlaybackProvider, SpotifyTrack?>((p) => p.currentTrack);
    final playback = context.read<PlaybackProvider>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemBarsStyle(Brightness.dark),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.f11): _close,
          const SingleActivator(LogicalKeyboardKey.space): playback.togglePlayPause,
          const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): playback.nextTrack,
          const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): playback.previousTrack,
        },
        child: Focus(
          autofocus: true,
          child: MouseRegion(
            cursor: _idle ? SystemMouseCursors.none : MouseCursor.defer,
            onHover: (_) => _restartIdleTimer(),
            child: Material(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LyricsBackdrop(imageUrl: track?.coverUrl ?? ''),
                  if (track == null)
                    Center(
                      child: EmptyState(
                        icon: Icons.music_off_rounded,
                        title: context.l10n.playerNothingPlayingTitle,
                        message: context.l10n.lyricsNothingPlayingMessage,
                        onDark: true,
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, box) => box.maxWidth >= _wideBreakpoint
                          ? _WideLayout(track: track, size: box.biggest)
                          : _NarrowLayout(track: track, size: box.biggest),
                    ),
                  Positioned(
                    top: 24,
                    right: 24,
                    child: AnimatedOpacity(
                      opacity: _idle ? 0 : 1,
                      duration: context.motion(const Duration(milliseconds: 300)),
                      child: GlassIconButton(
                        icon: Icons.close_fullscreen_rounded,
                        tooltip: context.l10n.lyricsExitImmersive,
                        onPressed: _close,
                        size: 44,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 宽屏：左封面信息列 + 右歌词列。
class _WideLayout extends StatelessWidget {
  final SpotifyTrack track;
  final Size size;

  const _WideLayout({required this.track, required this.size});

  @override
  Widget build(BuildContext context) {
    // 封面随窗口缩放：既不压过歌词，也不在 4K 全屏下显得局促
    final artSize = (size.height * 0.46).clamp(220.0, 480.0).clamp(0.0, size.width * 0.32);
    final lyricSize = (size.height / 22).clamp(32.0, 48.0);

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              child: SizedBox(
                width: artSize,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Artwork(track: track, size: artSize),
                    const SizedBox(height: 28),
                    _TrackTitle(track: track, large: true),
                    const SizedBox(height: 22),
                    LyricsGlassControls(full: true, maxWidth: artSize),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.only(right: 56),
            child: LyricsView(
              key: ValueKey(track.id),
              trackId: track.id,
              topInset: 80,
              bottomInset: 80,
              fontSize: lyricSize,
              horizontalPadding: 16,
            ),
          ),
        ),
      ],
    );
  }
}

/// 窄窗口：左上角小封面与歌名，歌词铺满，底部玻璃控制台。
class _NarrowLayout extends StatelessWidget {
  final SpotifyTrack track;
  final Size size;

  const _NarrowLayout({required this.track, required this.size});

  static const double _headerHeight = 112;
  static const double _controlsHeight = 170;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        LyricsView(
          key: ValueKey(track.id),
          trackId: track.id,
          topInset: _headerHeight,
          bottomInset: _controlsHeight,
          fontSize: 34,
          horizontalPadding: 36,
        ),
        Positioned(
          top: 28,
          left: 32,
          right: 96,
          child: Row(
            children: [
              _Artwork(track: track, size: 56),
              const SizedBox(width: 14),
              Expanded(child: _TrackTitle(track: track, large: false)),
            ],
          ),
        ),
        const Positioned(
          left: 32,
          right: 32,
          bottom: 28,
          child: LyricsGlassControls(full: true, maxWidth: 560),
        ),
      ],
    );
  }
}

/// 封面：切歌时交叉淡入，底部柔和投影。
class _Artwork extends StatelessWidget {
  final SpotifyTrack track;
  final double size;

  const _Artwork({required this.track, required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = context.tokens.radius(size >= 200 ? 16 : 10);
    return AnimatedSwitcher(
      duration: context.motion(const Duration(milliseconds: 420)),
      child: DecoratedBox(
        key: ValueKey(track.id),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: size * 0.12,
              offset: Offset(0, size * 0.04),
            ),
          ],
        ),
        child: CoverImage(url: track.coverUrl, size: size, borderRadius: radius),
      ),
    );
  }
}

/// 歌名 + 艺人。
class _TrackTitle extends StatelessWidget {
  final SpotifyTrack track;
  final bool large;

  const _TrackTitle({required this.track, required this.large});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track.name,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: large ? 26 : 17,
            letterSpacing: -0.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          track.artistNames,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
            fontSize: large ? 17 : 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
