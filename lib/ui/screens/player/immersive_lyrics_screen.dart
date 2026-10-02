import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../core/theme/system_bars.dart';
import '../../../l10n/l10n.dart';
import '../../../models/track.dart';
import '../../../services/storage_service.dart';
import '../../shell/desktop/desktop_window.dart';
import '../../shell/desktop/window_caption_buttons.dart';
import '../../widgets/connect/now_playing_source.dart';
import '../../widgets/connect/playback_shortcuts.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/empty_state.dart';
import 'lyrics/glass_icon_button.dart';
import 'lyrics/lyrics_backdrop.dart';
import 'lyrics/lyrics_glass_controls.dart';
import 'lyrics/lyrics_view.dart';

/// 桌面沉浸式歌词（Apple Music macOS 全屏歌词风格）。
///
/// - 两种铺满方式（右上角按钮或 F11 切换，记住上次选择）：默认只铺满窗口（保留窗口按钮，顶部可拖动窗口），
///   或进入系统全屏铺满整个屏幕；关闭时恢复；Esc / 右上角退出按钮退出；
/// - 遥控远程设备时展示远程曲目，歌词按远程进度滚动，控制台与快捷键作用于远程设备；
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

  /// 只铺满窗口时，顶部留给窗口按钮与拖动区的高度（与 WindowCaptionButtons 默认高度一致）。
  static const double _captionInset = 40;

  Timer? _idleTimer;
  bool _idle = false;

  /// true：系统全屏（铺满整个屏幕）；false：只铺满窗口（保留窗口外框与窗口按钮）。
  late bool _screen;
  StorageService? _storage;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService?>();
    _screen = _storage?.immersiveScreenFullscreen ?? false;
    _applyMode();
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    DesktopWindow.immersiveWindow.value = false;
    DesktopWindow.setFullScreen(false);
    super.dispose();
  }

  void _applyMode() {
    // 先切外框标记再切系统全屏，避免中间一帧露出窄窗口标题条
    DesktopWindow.immersiveWindow.value = !_screen;
    DesktopWindow.setFullScreen(_screen);
  }

  /// 在「铺满窗口」与「铺满整个屏幕」之间切换，并记住选择。
  void _toggleMode() {
    setState(() => _screen = !_screen);
    _applyMode();
    _storage?.setImmersiveScreenFullscreen(_screen);
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
    // 遥控远程设备时展示远程曲目，快捷键也发给远程设备
    final remote = NowPlayingSource.isRemote(context);
    final track = NowPlayingSource.track(context);
    // 只铺满窗口时顶部让出窗口按钮那一行
    final topInset = _screen || !DesktopWindow.enabled ? 0.0 : _captionInset;
    final l10n = context.l10n;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemBarsStyle(Brightness.dark),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.f11): _toggleMode,
          // 播放类按键与主窗口相同，远程模式下控制其他设备
          ...PlaybackShortcuts.bindings(context),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) => PlaybackShortcuts.onSpaceKey(context, event),
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
                          ? _WideLayout(track: track, size: box.biggest, remote: remote)
                          : _NarrowLayout(track: track, size: box.biggest, remote: remote, topInset: topInset),
                    ),
                  // 只铺满窗口时：顶部一条透明拖动区（避开右上角窗口按钮），可照常移动窗口
                  if (topInset > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: WindowCaptionButtons.width,
                      height: topInset,
                      child: const WindowDragArea(child: SizedBox.expand()),
                    ),
                  Positioned(
                    top: 24 + topInset,
                    right: 24,
                    child: AnimatedOpacity(
                      opacity: _idle ? 0 : 1,
                      duration: context.motion(const Duration(milliseconds: 300)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (DesktopWindow.enabled) ...[
                            GlassIconButton(
                              icon: _screen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                              tooltip: _screen ? l10n.lyricsFillWindow : l10n.lyricsFillScreen,
                              onPressed: _toggleMode,
                              size: 44,
                            ),
                            const SizedBox(width: 12),
                          ],
                          GlassIconButton(
                            icon: Icons.close_fullscreen_rounded,
                            tooltip: l10n.lyricsExitImmersive,
                            onPressed: _close,
                            size: 44,
                          ),
                        ],
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
  final bool remote;

  const _WideLayout({required this.track, required this.size, required this.remote});

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
              key: ValueKey((track.id, remote)),
              track: track,
              remote: remote,
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
  final bool remote;

  /// 只铺满窗口时顶部让给窗口按钮的高度。
  final double topInset;

  const _NarrowLayout({required this.track, required this.size, required this.remote, this.topInset = 0});

  static const double _headerHeight = 112;
  static const double _controlsHeight = 170;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        LyricsView(
          key: ValueKey((track.id, remote)),
          track: track,
          remote: remote,
          topInset: _headerHeight + topInset,
          bottomInset: _controlsHeight,
          fontSize: 34,
          horizontalPadding: 36,
        ),
        Positioned(
          top: 28 + topInset,
          left: 32,
          // 右侧让出「全屏切换 + 退出」两个玻璃按钮
          right: 152,
          child: Row(
            children: [
              _Artwork(track: track, size: 56),
              const SizedBox(width: 14),
              Expanded(child: _TrackTitle(track: track, large: false)),
            ],
          ),
        ),
        const Positioned(left: 32, right: 32, bottom: 28, child: LyricsGlassControls(full: true, maxWidth: 560)),
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
