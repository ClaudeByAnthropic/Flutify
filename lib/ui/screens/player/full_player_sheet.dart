import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../core/theme/md3e_theme.dart';
import '../../../core/theme/system_bars.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/model_labels.dart';
import '../../../models/playback_context.dart';
import '../../../models/track.dart';
import '../../../providers/appearance_provider.dart';
import '../../../providers/playback_provider.dart';
import '../../../providers/connect_provider.dart';
import '../../navigation/app_routes.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/connect/connect_actions.dart';
import '../../widgets/connect/remote_progress.dart';
import '../../widgets/connect/remote_transport_controls.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/playback_scrubber.dart';
import '../../widgets/player_controls.dart';
import '../../widgets/text_metrics.dart';
import '../../widgets/track_menu.dart';
import 'device_picker_sheet.dart';
import 'android_player_scene.dart';
import 'immersive_lyrics_screen.dart';
import 'lyrics/glass_icon_button.dart';
import 'lyrics/lyrics_backdrop.dart';
import 'lyrics/lyrics_view.dart';
import 'lyrics/lyrics_translation_controls.dart';
import 'queue_list.dart';
import 'player_modal.dart';
import 'player_destinations_sheet.dart';
import 'player_expansion.dart';
import 'player_lyrics_motion.dart';
import 'widgets/swipeable_artwork.dart';
import 'widgets/canvas_artwork.dart';

/// 全屏播放器中间区域的内容。
enum _PlayerView { artwork, lyrics, queue }

/// 全屏播放器（移动端底部全屏面板 / 桌面端居中对话框）。
///
/// - 中间区域在「封面 / 歌词 / 播放队列」之间切换（底部两个按钮，再点一次回到封面），
///   标题、进度条与播放控件始终保留在下方；
/// - 封面可左右拖动切歌（[SwipeableArtwork]）；
/// - 背景为封面主色 → 近黑的渐变；切到歌词视图时交叉淡入为流动封面，控件收进液态玻璃；
/// - 深浅色主题下都按用户外观设置的深色主题绘制（白色系控件）；
/// - **远程模式**（Connect 遥控其他设备）：显示远程曲目，进度与控制发给远程设备。
///
/// 本组件只在切歌或播放上下文变化时重建；进度条、播放按钮、随机/循环、
/// 点赞按钮均为独立订阅的子组件。
class FullPlayerSheet extends StatefulWidget {
  const FullPlayerSheet({
    super.key,
    this.fullscreen = false,
    this.expansionAnimation,
  });

  /// Presentation is selected when opening the route; resizing does not change it.
  final bool fullscreen;
  final Animation<double>? expansionAnimation;

  /// 根据窗口宽度选择以底部面板或对话框形式打开。
  static Future<void> show(BuildContext context) => PlayerModal.show(context, (
    captureRoute,
  ) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    if (isDesktop) {
      return showDialog(
        context: context,
        builder: (dialogContext) {
          captureRoute(dialogContext);
          return const Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.all(24),
            child: SizedBox(width: 420, height: 720, child: FullPlayerSheet()),
          );
        },
      );
    }
    // 窄窗口（手机、Windows 竖屏窄窗）在所有平台上共用同一套从迷你播放器展开的全屏路由。
    final origin = PlayerExpansionSource.capture(context);
    final reduceMotion = context.reduceMotion;
    final themes = InheritedTheme.capture(
      from: context,
      to: Navigator.of(context, rootNavigator: true).context,
    );
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: AppRoutes.fullPlayerRouteName),
        opaque: false,
        fullscreenDialog: true,
        barrierColor: Colors.black26,
        transitionDuration: context.motion(PlayerExpansionMotion.duration),
        reverseTransitionDuration: context.motion(
          PlayerExpansionMotion.reverseDuration,
        ),
        pageBuilder: (sheetContext, animation, secondaryAnimation) {
          captureRoute(sheetContext);
          final media = MediaQuery.of(sheetContext);
          return themes.wrap(
            MediaQuery(
              data: media.copyWith(
                padding: media.viewPadding,
                disableAnimations: reduceMotion,
              ),
              child: FullPlayerSheet(
                fullscreen: true,
                expansionAnimation: animation,
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            Material(
              type: MaterialType.transparency,
              child: PlayerExpansionTransition(
                animation: animation,
                origin: origin,
                child: child,
              ),
            ),
      ),
    );
  });

  @override
  State<FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends State<FullPlayerSheet> {
  _PlayerView _view = _PlayerView.artwork;
  double _dismissDragDistance = 0;
  bool _destinationsOpen = false;

  void _toggle(_PlayerView view) =>
      setState(() => _view = _view == view ? _PlayerView.artwork : view);

  Future<void> _showDestinations(
    BuildContext context,
    SpotifyTrack track,
  ) async {
    if (_destinationsOpen) return;
    setState(() => _destinationsOpen = true);
    try {
      await PlayerDestinationsSheet.show(context, track);
    } finally {
      if (mounted) setState(() => _destinationsOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 始终按用户外观设置的「深色」主题绘制（强调色、圆角、玻璃强度同步生效）
    final theme =
        context.watch<AppearanceProvider?>()?.theme(Brightness.dark) ??
        MD3ETheme.dark;
    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemBarsStyle(Brightness.dark),
        child: Builder(builder: _buildContent),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    // 远程模式：显示远程曲目、标题行标出设备名（控制权规则与播放栏一致）
    final remote = ConnectActions.showRemote(context);
    final track = remote
        ? context.select<ConnectProvider?, SpotifyTrack?>(
            (c) => c?.displayTrack,
          )
        : context.select<PlaybackProvider, SpotifyTrack?>(
            (p) => p.currentTrack,
          );
    final deviceName = remote
        ? context.select<ConnectProvider?, String?>(
            (c) => c?.activeDevice?.name,
          )
        : null;
    final playbackContext = remote
        ? PlaybackContext(type: 'device', name: deviceName ?? '')
        : context.select<PlaybackProvider, PlaybackContext>(
            (p) => p.playbackContext,
          );
    final colorScheme = Theme.of(context).colorScheme;
    final fullscreen = widget.fullscreen;
    final radius = fullscreen
        ? BorderRadius.zero
        : BorderRadius.circular(context.tokens.corner(32));
    if (track == null) {
      return _closeOnEscape(
        context,
        _NothingPlaying(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: radius,
        ),
      );
    }

    final content = ClipRRect(
      borderRadius: radius,
      child: _scene(context, track, playbackContext, remote),
    );
    return _closeOnEscape(
      context,
      fullscreen
          ? GestureDetector(
              onVerticalDragStart: (_) => _dismissDragDistance = 0,
              onVerticalDragUpdate: (details) =>
                  _dismissDragDistance += details.delta.dy,
              onVerticalDragCancel: () => _dismissDragDistance = 0,
              onVerticalDragEnd: (details) {
                if (_dismissDragDistance > 100 ||
                    (details.primaryVelocity ?? 0) > 600) {
                  Navigator.maybePop(context);
                }
                _dismissDragDistance = 0;
              },
              child: content,
            )
          : content,
    );
  }

  /// Esc 关闭播放器（桌面键盘）。放在最外层：焦点在内部任意按钮上时按键同样冒泡到这里，
  /// 目的地菜单、设备选择等上层路由有自己的焦点域，会先处理 Esc。
  Widget _closeOnEscape(BuildContext context, Widget child) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.maybePop(context),
    },
    child: Focus(autofocus: true, skipTraversal: true, child: child),
  );

  Widget _scene(
    BuildContext context,
    SpotifyTrack track,
    PlaybackContext playbackContext,
    bool remote,
  ) => LyricsTranslationScope(
    child: AndroidPlayerScene(
      lyricsMode: _view == _PlayerView.lyrics,
      queueMode: _view == _PlayerView.queue,
      onArtworkTap: () => setState(() => _view = _PlayerView.artwork),
      interactionSuspended: _destinationsOpen,
      background: PlayerExpansionReveal(
        animation: widget.expansionAnimation,
        start: 0,
        rise: 0,
        child: LyricsBackdrop(
          imageUrl: track.coverUrl,
          reducedEffects: _view != _PlayerView.lyrics,
        ),
      ),
      // The same native texture keeps flowing across artwork/lyrics/queue.
      lyricsBackground: const SizedBox.expand(),
      topBar: PlayerExpansionReveal(
        animation: widget.expansionAnimation,
        start: 0.04,
        rise: 0.25,
        child: _TopBar(track: track, playbackContext: playbackContext),
      ),
      titleBuilder: (context, progress) => PlayerExpansionReveal(
        animation: widget.expansionAnimation,
        child: _TitleRow(
          track: track,
          compact: true,
          lyricsProgress: progress,
          onTap: _view != _PlayerView.artwork
              ? () => _showDestinations(context, track)
              : null,
        ),
      ),
      controlsHeightReduction: remote
          ? 0
          : PlaybackScrubber.expandedLabelHeight(context) + 8,
      footerHeightReduction: 12,
      controlsBuilder: (context, progress) => PlayerExpansionReveal(
        animation: widget.expansionAnimation,
        opacityKey: const ValueKey('player-expansion-controls'),
        child: _ControlsGroup(
          track: track,
          glass: false,
          remote: remote,
          showTitle: false,
          lyricsProgress: progress,
        ),
      ),
      footerBuilder: (context, progress) => PlayerExpansionReveal(
        animation: widget.expansionAnimation,
        child: _BottomBar(
          view: _view,
          onToggle: _toggle,
          lyricsProgress: progress,
        ),
      ),
      artworkBuilder: (context, size, progress) => PlayerArtworkHero(
        imageUrl: track.coverUrl,
        child: TickerMode(
          enabled: progress == 0 && _view == _PlayerView.artwork,
          child: ClipRRect(
            borderRadius: context.tokens.radius(28 - 18 * progress),
            child: SizedBox.square(
              dimension: size,
              // Keep one decoded image throughout the flight. Changing the
              // decode size every frame causes placeholder flashes and churn.
              child: FittedBox(
                child: SwipeableArtwork(
                  url: track.coverUrl,
                  size: 400,
                  child: CanvasArtwork(
                    track: track,
                    size: 400,
                    remote: remote,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      lyrics: LyricsView(
        appleMusicStyle: true,
        key: ValueKey((track.id, remote)),
        track: track,
        remote: remote,
        bottomInset: 24,
      ),
      translation: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LyricsTranslationButton(),
          // 桌面对话框里额外提供沉浸式全屏歌词入口。
          if (MediaQuery.sizeOf(context).width >= 800) ...[
            const SizedBox(width: 8),
            GlassIconButton(
              icon: Icons.open_in_full_rounded,
              size: 36,
              tooltip: context.l10n.lyricsImmersive,
              onPressed: () => ImmersiveLyricsScreen.open(context),
            ),
          ],
        ],
      ),
      queue: const QueueList(horizontalPadding: 16),
    ),
  );
}

/// 歌名 + 进度条 + 播放控件；歌词视图下收进一块液态玻璃，歌词可从其上方滚过时仍清晰可读。
class _ControlsGroup extends StatelessWidget {
  final SpotifyTrack track;
  final bool glass;
  final bool remote;
  final bool showTitle;
  final double? lyricsProgress;

  const _ControlsGroup({
    required this.track,
    required this.glass,
    required this.remote,
    this.showTitle = true,
    this.lyricsProgress,
  });

  @override
  Widget build(BuildContext context) {
    final compactness = lyricsProgress ?? 0.0;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle) _TitleRow(track: track),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: lerpDouble(16, 4, compactness)!,
          ),
          child: remote
              ? RemoteScrubber(
                  compact: false,
                  compactProgress: lyricsProgress,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  labelColor: Colors.white60,
                )
              : PlaybackScrubber(
                  compactProgress: lyricsProgress,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  labelColor: Colors.white60,
                ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: lerpDouble(20, 8, compactness)!,
          ),
          child: remote
              ? const RemoteTransportControls(
                  showModes: true,
                  style: RemoteControlsStyle.glassFull,
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const ShuffleButton(),
                    const SkipButton(next: false),
                    PlayPauseButton(
                      size: lerpDouble(60, 52, compactness)!,
                      iconSize: lerpDouble(34, 44, compactness)!,
                      background: Colors.white.withValues(
                        alpha: 1 - compactness,
                      ),
                      foreground: Color.lerp(
                        Colors.black,
                        Colors.white,
                        compactness,
                      )!,
                      backgroundAnimationDuration: lyricsProgress == null
                          ? kThemeChangeDuration
                          : Duration.zero,
                    ),
                    const SkipButton(next: true),
                    const RepeatButton(),
                  ],
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
    if (!glass) return content;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: LiquidGlass(
        borderRadius: context.tokens.radius(28),
        child: content,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final SpotifyTrack track;
  final PlaybackContext playbackContext;

  const _TopBar({required this.track, required this.playbackContext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            color: Colors.white,
            tooltip: context.l10n.commonClose,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  context.l10n.playingFrom(playbackContext),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Colors.white.withAlpha(180),
                  ),
                ),
                if (!playbackContext.isNone) ...[
                  const SizedBox(height: 2),
                  Text(
                    playbackContext.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Builder(
            // 独立 context：桌面对话框中菜单锚定在按钮下方
            builder: (buttonContext) => IconButton(
              icon: const Icon(Icons.more_vert_rounded, size: 22),
              color: Colors.white,
              tooltip: context.l10n.commonMoreOptions,
              onPressed: () => TrackMenu.show(buttonContext, track),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final SpotifyTrack track;
  final bool compact;
  final double lyricsProgress;
  final VoidCallback? onTap;

  const _TitleRow({
    required this.track,
    this.compact = false,
    this.lyricsProgress = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle =
        theme.textTheme.titleLarge ?? const TextStyle(fontSize: 22);
    final baseSize = titleStyle.fontSize ?? 22;
    final titleSize = baseSize * (1 - 0.35 * lyricsProgress);
    final artist = Text(
      track.artistNames,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: Colors.white70,
        fontWeight: FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final title = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reserve the unscaled line's measured height. Static text and the
        // marquee can use different line boxes, especially with large text.
        SizedBox(
          height: compact
              ? TextMetrics.lineHeight(
                  context,
                  titleStyle.copyWith(fontWeight: FontWeight.w800),
                )
              : null,
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: compact ? PlayerLyricsMotion.curve : Curves.linear,
              switchOutCurve: compact
                  ? PlayerLyricsMotion.curve
                  : Curves.linear,
              child: MarqueeText(
                text: track.name,
                key: ValueKey(track.id),
                style: titleStyle.copyWith(
                  fontSize: compact ? titleSize : null,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        MouseRegion(
          cursor: onTap == null && track.artists.isNotEmpty
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          child: GestureDetector(
            onTap: onTap != null || track.artists.isEmpty
                ? null
                : () => AppRoutes.openArtist(context, track.artists.first),
            child: artist,
          ),
        ),
      ],
    );
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(24, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: compact
                ? Semantics(
                    button: onTap != null,
                    child: InkWell(
                      key: const ValueKey('player-card-title'),
                      onTap: onTap,
                      canRequestFocus: onTap != null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          heightFactor: 1,
                          child: title,
                        ),
                      ),
                    ),
                  )
                : title,
          ),
          LikeButton(track: track, size: 28),
        ],
      ),
    );
  }
}

/// 没有当前曲目时的占位（例如队列被清空后面板仍打开）。
class _NothingPlaying extends StatelessWidget {
  final Color color;
  final BorderRadius borderRadius;

  const _NothingPlaying({required this.color, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      child: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                tooltip: context.l10n.commonClose,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Center(
              child: EmptyState(
                icon: Icons.music_note_rounded,
                title: context.l10n.playerNothingPlayingTitle,
                message: context.l10n.playerNothingPlayingMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏：Connect 设备 + 歌词 / 队列视图切换（当前视图高亮并带小圆点）。
class _BottomBar extends StatelessWidget {
  final _PlayerView view;
  final ValueChanged<_PlayerView> onToggle;
  final double? lyricsProgress;

  const _BottomBar({
    required this.view,
    required this.onToggle,
    this.lyricsProgress,
  });

  @override
  Widget build(BuildContext context) {
    final deviceName = context.select<ConnectProvider?, String?>(
      (c) => (c?.hasRemoteSession ?? false) ? c?.activeDevice?.name : null,
    );
    final primary = Theme.of(context).colorScheme.primary;
    final deviceColor = deviceName != null ? primary : Colors.white70;

    Widget toggle(_PlayerView target, IconData icon, String tooltip) {
      final active = view == target;
      return IconButton(
        tooltip: tooltip,
        isSelected: active,
        onPressed: () => onToggle(target),
        icon: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, color: active ? primary : Colors.white70, size: 22),
            if (active)
              Positioned(
                bottom: -7,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.lerp(
        const EdgeInsets.fromLTRB(20, 4, 12, 8),
        const EdgeInsets.symmetric(horizontal: 8),
        lyricsProgress ?? 0,
      )!,
      child: Row(
        children: [
          Expanded(
            // Only the icon/label is a device action. The remaining footer
            // space belongs to the scene's card-reveal gesture.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: InkWell(
                borderRadius: context.tokens.pill,
                mouseCursor: SystemMouseCursors.click,
                onTap: () => DevicePickerSheet.show(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 4.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.devices_rounded,
                          size: 16,
                          color: deviceColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            deviceName ?? context.l10n.playerThisDevice,
                            style: TextStyle(
                              color: deviceColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          toggle(
            _PlayerView.lyrics,
            Icons.lyrics_outlined,
            context.l10n.lyricsTitle,
          ),
          toggle(
            _PlayerView.queue,
            Icons.queue_music_rounded,
            context.l10n.queueTitle,
          ),
        ],
      ),
    );
  }
}
