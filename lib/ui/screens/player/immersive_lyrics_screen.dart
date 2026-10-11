import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../core/theme/system_bars.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/connect_provider.dart';
import '../../../providers/playback_provider.dart';
import '../../../services/storage_service.dart';
import '../../navigation/app_routes.dart';
import '../../shell/desktop/desktop_window.dart';
import '../../shell/desktop/window_caption_buttons.dart';
import '../../widgets/connect/now_playing_source.dart';
import '../../widgets/connect/playback_shortcuts.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/menu/desktop_menu.dart';
import '../../widgets/toast/app_toast.dart';
import '../../widgets/track_menu.dart';
import 'lyrics/lyrics_backdrop.dart';
import 'lyrics/lyrics_translation_controls.dart';
import 'player_scene_view.dart';

/// 桌面沉浸式歌词：窗口外壳 + 全端共用的播放器场景（[PlayerSceneView]）。
///
/// - 两种铺满方式（左上角按钮或 F11 切换，记住上次选择）：默认只铺满窗口（保留窗口按钮，顶部可拖动窗口），
///   或进入系统全屏铺满整个屏幕；关闭时恢复；Esc / 左上角关闭按钮退出；
/// - 内容与手机、桌面竖屏同一套：封面缩进玻璃卡片、歌词在卡片后滚动、封面 / 歌词 / 队列切换动画一致；
///   窗口够宽时场景自动切到横屏布局（歌词在左、卡片在右），窄窗口为竖屏布局；
/// - 桌面独有：左上角玻璃胶囊（关闭 + 切换铺满方式 + 更多操作，macOS 窗口模式避开交通灯），
///   播放按钮下方的音量条（遥控远程设备时调节远程音量）；
/// - 遥控远程设备时展示远程曲目，歌词按远程进度滚动，控制台、音量与快捷键作用于远程设备；
/// - 鼠标静止 3 秒后隐藏光标与浮动按钮，移动即恢复；
/// - 空格播放 / 暂停，Ctrl+← / →（macOS 为 ⌘+← / →）切歌。
class ImmersiveLyricsScreen extends StatefulWidget {
  const ImmersiveLyricsScreen({super.key});

  /// 以淡入方式推入根导航（盖住三栏框架与播放栏）。
  /// 已经打开着（入口有 F11、⌘⇧F 菜单、播放栏按钮）：重复触发不再叠一层。
  static bool _open = false;

  static Future<void> open(BuildContext context) async {
    if (_open) return;
    _open = true;
    try {
      await _push(context);
    } finally {
      _open = false;
    }
  }

  static Future<void> _push(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: AppRoutes.immersiveLyricsRouteName),
        opaque: true,
        transitionDuration: context.motion(const Duration(milliseconds: 380)),
        reverseTransitionDuration: context.motion(
          const Duration(milliseconds: 260),
        ),
        pageBuilder: (_, _, _) => const ImmersiveLyricsScreen(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 1.03, end: 1.0).animate(curved),
              child: child,
            ),
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

  /// 横屏时场景内容的最大宽度（宽屏全屏时不让歌词行过长）。
  static const double _maxSceneWidth = 1280;

  /// 只铺满窗口时，顶部留给窗口按钮与拖动区的高度（与 WindowCaptionButtons 默认高度一致）。
  static const double _captionInset = 40;

  /// 顶部按钮保持足够大的触控区域。
  static const double _barHeight = 48;

  /// macOS 只铺满窗口：胶囊距窗口顶端的距离（比交通灯略低，不贴顶）。
  static const double _macBarTop = 8;

  /// macOS 只铺满窗口：胶囊左端到窗口左缘的距离（与交通灯之间留出呼吸感）。
  static const double _macBarLeft = DesktopWindow.macTrafficLightsInset + 8;

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
    DesktopWindow.fullScreen.addListener(_onSystemFullScreen);
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    DesktopWindow.fullScreen.removeListener(_onSystemFullScreen);
    // dispose 跑在帧收尾阶段，此时同步改 ValueNotifier 会让外层（WindowFrame、
    // LiquidGlass）在 widget 树被锁定时 setState；且路由刚移除的这一帧还没提交。
    // 推迟到本帧提交之后再恢复窗口外框 / 退出全屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DesktopWindow.immersiveWindow.value = false;
      DesktopWindow.setFullScreen(false);
    });
    super.dispose();
  }

  /// 系统直接切换了全屏（macOS 绿色按钮 / 菜单 / ⌃⌘F）：铺满方式跟着变，并记住这次选择。
  /// 自己经 [_applyMode] 切换时两边本就一致，这里不会重复处理。
  void _onSystemFullScreen() {
    final full = DesktopWindow.fullScreen.value;
    if (!mounted || full == _screen) return;
    setState(() => _screen = full);
    DesktopWindow.immersiveWindow.value = !_screen;
    _storage?.setImmersiveScreenFullscreen(_screen);
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

  /// 鼠标移动：显示光标与浮动按钮，并重新计时。
  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (_idle) setState(() => _idle = false);
    _idleTimer = Timer(_idleDelay, () {
      if (mounted) setState(() => _idle = true);
    });
  }

  bool _closing = false;

  /// 退出：先让玻璃去掉 BackdropFilter 并等其落地，再弹出路由。
  /// 路由淡出（Opacity 图层里套 BackdropFilter）与随后的退出全屏重排，
  /// 是 Windows 引擎合成器闪退的触发点，见 [DesktopWindow.fullscreenTransition]。
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await DesktopWindow.dropGlassForExit();
    if (!mounted) return;
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) _closing = false;
  }

  @override
  Widget build(BuildContext context) {
    // 遥控远程设备时展示远程曲目，快捷键也发给远程设备
    final remote = NowPlayingSource.isRemote(context);
    final track = NowPlayingSource.track(context);
    // 只铺满窗口时顶部让出窗口按钮那一行
    final topInset = _screen || !DesktopWindow.enabled ? 0.0 : _captionInset;
    // macOS 只铺满窗口：原生交通灯浮在左上角，胶囊排在其右侧、略低于交通灯
    final macWindow = DesktopWindow.macNativeWindow && !_screen;
    // Windows / Linux 只铺满窗口：拖动区避开右上角自绘窗口按钮。
    final captionRight = topInset > 0 && !DesktopWindow.macNativeWindow
        ? WindowCaptionButtons.width
        : 0.0;
    final barTop = macWindow
        ? _macBarTop
        : topInset > 0
        ? 8.0
        : 20.0;
    final l10n = context.l10n;
    final fade = context.motion(const Duration(milliseconds: 300));

    Widget idleFade(Widget child) => AnimatedOpacity(
      opacity: _idle ? 0 : 1,
      duration: fade,
      child: IgnorePointer(ignoring: _idle, child: child),
    );

    return LyricsTranslationScope(
      child: GlassMenuScope(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
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
              onKeyEvent: (_, event) =>
                  PlaybackShortcuts.onSpaceKey(context, event),
              child: MouseRegion(
                cursor: _idle ? SystemMouseCursors.none : MouseCursor.defer,
                onHover: (_) => _restartIdleTimer(),
                child: Material(
                  color: Colors.black,
                  child: BackdropGroup(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (track == null) ...[
                          const LyricsBackdrop(imageUrl: ''),
                          Center(
                            child: EmptyState(
                              icon: Icons.music_off_rounded,
                              title: context.l10n.playerNothingPlayingTitle,
                              message: context.l10n.lyricsNothingPlayingMessage,
                              onDark: true,
                            ),
                          ),
                        ] else
                          // 与手机、桌面竖屏完全同一套场景：窗口够宽时自动为横屏布局。
                          // 顶部留白给窗口按钮与左上角胶囊，音量条接在播放按钮下方。
                          PlayerSceneView(
                            track: track,
                            remote: remote,
                            initialView: PlayerView.lyrics,
                            topBar: SizedBox(
                              height: (barTop + _barHeight).clamp(
                                topInset,
                                double.infinity,
                              ),
                            ),
                            controlsFooter: _VolumeRow(remote: remote),
                            maxLandscapeWidth: _maxSceneWidth,
                            immersiveEntry: false,
                            fullBackdrop: true,
                            lyricsLineCursor: MouseCursor.defer,
                          ),
                        // 只铺满窗口时：顶部一条透明拖动区（避开右上角窗口按钮），可照常移动窗口
                        if (topInset > 0)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: captionRight,
                            height: topInset,
                            child: const WindowDragArea(
                              child: SizedBox.expand(),
                            ),
                          ),
                        Positioned(
                          top: barTop,
                          left: macWindow ? _macBarLeft : 18,
                          child: idleFade(
                            _GlassCapsule(
                              height: _barHeight,
                              children: [
                                _CapsuleIcon(
                                  icon: Icons.close_rounded,
                                  tooltip: l10n.lyricsExitImmersive,
                                  onPressed: _close,
                                ),
                                if (DesktopWindow.enabled)
                                  _CapsuleIcon(
                                    icon: _screen
                                        ? Icons.fullscreen_exit_rounded
                                        : Icons.fullscreen_rounded,
                                    tooltip: _screen
                                        ? l10n.lyricsFillWindow
                                        : l10n.lyricsFillScreen,
                                    onPressed: _toggleMode,
                                  ),
                                if (track != null)
                                  Builder(
                                    // 独立 context：菜单锚定在按钮下方
                                    builder: (buttonContext) => _CapsuleIcon(
                                      icon: Icons.more_horiz_rounded,
                                      tooltip: l10n.commonMoreOptions,
                                      onPressed: () =>
                                          TrackMenu.show(buttonContext, track),
                                    ),
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
          ),
        ),
      ),
    );
  }
}

/// 顶部玻璃胶囊容器。
class _GlassCapsule extends StatelessWidget {
  final double height;
  final List<Widget> children;

  const _GlassCapsule({required this.height, required this.children});

  @override
  Widget build(BuildContext context) {
    // 胶囊在歌词区上方的顶栏留白内（窄屏歌词从胶囊下方开始，宽屏位于左栏顶部）
    return LiquidGlass(
      backdrop: false,
      borderRadius: BorderRadius.circular(height / 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: height,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _CapsuleIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _CapsuleIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 24),
      color: Colors.white,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: onPressed,
    );
  }
}

/// 控制台玻璃内、播放按钮下方的音量条（Apple 锁屏样式）：
/// 左端小喇叭（点击静音 / 恢复），右端大音量喇叭，中间白色滑杆。
/// 滑杆与上方进度条同宽对齐：两端图标占的位置正好是进度条两端的时间标签。
/// 遥控远程设备时调节远程设备音量。
class _VolumeRow extends StatelessWidget {
  final bool remote;

  const _VolumeRow({required this.remote});

  @override
  Widget build(BuildContext context) {
    late final double volume;
    ValueChanged<double>? onChanged;
    ValueChanged<double>? onChangeEnd;
    late final VoidCallback onMute;
    if (remote) {
      final connect = context.read<ConnectProvider>();
      volume = context.select<ConnectProvider, double>((c) => c.volume);
      // 远程设备不支持调音量：滑杆置灰，点喇叭说明原因（与键盘音量快捷键一致）
      final supported = context.select<ConnectProvider, bool>(
        (c) => c.activeDevice?.supportsVolume ?? false,
      );
      if (supported) {
        onChanged = connect.setVolume;
        onMute = () => connect.setVolume(volume > 0 ? 0 : 0.5);
      } else {
        onMute = () => AppToast.show(
          context,
          context.l10n.connectVolumeUnsupported(
            connect.activeDevice?.name ?? '',
          ),
          icon: Icons.volume_off_rounded,
          tone: ToastTone.warning,
        );
      }
    } else {
      final playback = context.read<PlaybackProvider>();
      volume = context.select<PlaybackProvider, double>((p) => p.volume);
      onChanged = playback.setVolume;
      onChangeEnd = (v) => playback.setVolume(v, persist: true);
      onMute = playback.toggleMute;
    }
    final muted = volume == 0;
    // 与进度条（本机）两端「40 宽标签 + 8 间距」一致；远程进度条没有间距
    final gap = SizedBox(width: remote ? 0 : 8);

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: IconButton(
            icon: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_mute_rounded,
              size: 18,
            ),
            color: Colors.white60,
            tooltip: muted
                ? context.l10n.playerUnmute
                : context.l10n.playerMute,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 28),
            onPressed: onMute,
          ),
        ),
        gap,
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              // 与进度条相同的滑块 / 触控半径，两条轨道才能严格对齐
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        gap,
        const SizedBox(
          width: 40,
          height: 28,
          child: Icon(Icons.volume_up_rounded, size: 18, color: Colors.white60),
        ),
      ],
    );
  }
}
