import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/model_labels.dart';
import '../../../models/playback_context.dart';
import '../../../models/track.dart';
import '../../../providers/connect_provider.dart';
import '../../navigation/app_routes.dart';
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
import 'player_destinations_sheet.dart';
import 'player_expansion.dart';
import 'player_lyrics_motion.dart';
import 'widgets/swipeable_artwork.dart';
import 'widgets/canvas_artwork.dart';

/// 中间区域显示的内容。
enum PlayerView { artwork, lyrics, queue }

/// 全端共用的播放器场景：封面 / 歌词 / 播放队列在同一套布局与动画里切换。
///
/// 竖屏（窄窗）与横屏（宽窗）由 [AndroidPlayerScene] 按尺寸选择布局，
/// 全屏播放器路由、桌面对话框与桌面沉浸式歌词页都使用它，只在外壳（顶栏、音量等）上有差异。
class PlayerSceneView extends StatefulWidget {
  const PlayerSceneView({
    super.key,
    required this.track,
    this.playbackContext,
    required this.remote,
    this.expansionAnimation,
    this.initialView = PlayerView.artwork,
    this.topBar,
    this.controlsFooter,
    this.maxLandscapeWidth = 960,
    this.immersiveEntry = true,
    this.fullBackdrop = false,
    this.lyricsLineCursor,
  }) : assert(topBar != null || playbackContext != null);

  final SpotifyTrack track;

  /// 默认顶栏显示的播放来源；提供自定义 [topBar] 时可省略。
  final PlaybackContext? playbackContext;
  final bool remote;
  final Animation<double>? expansionAnimation;
  final PlayerView initialView;

  /// 替换默认顶栏（关闭、播放来源、更多）。它的高度决定场景顶部留白。
  final Widget? topBar;

  /// 播放按钮下方的附加行（例如桌面音量条），与进度条同宽对齐。
  final Widget? controlsFooter;

  /// 横屏时场景内容的最大宽度。
  final double maxLandscapeWidth;

  /// 是否在歌词工具栏提供「沉浸式歌词」入口（沉浸式页面自身不需要）。
  final bool immersiveEntry;

  /// 任何视图下都保持流动背景的完整效果（沉浸式页面始终展示歌词）。
  final bool fullBackdrop;

  /// 歌词行的鼠标光标；沉浸式页面传 [MouseCursor.defer] 以保留闲置隐藏光标。
  final MouseCursor? lyricsLineCursor;

  @override
  State<PlayerSceneView> createState() => _PlayerSceneViewState();
}

class _PlayerSceneViewState extends State<PlayerSceneView> {
  late PlayerView _view = widget.initialView;
  bool _destinationsOpen = false;

  void _toggle(PlayerView view) =>
      setState(() => _view = _view == view ? PlayerView.artwork : view);

  Future<void> _showDestinations(BuildContext context) async {
    if (_destinationsOpen) return;
    setState(() => _destinationsOpen = true);
    try {
      await PlayerDestinationsSheet.show(context, widget.track);
    } finally {
      if (mounted) setState(() => _destinationsOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final remote = widget.remote;
    final expansion = widget.expansionAnimation;
    return LyricsTranslationScope(
      child: AndroidPlayerScene(
        lyricsMode: _view == PlayerView.lyrics,
        queueMode: _view == PlayerView.queue,
        maxLandscapeWidth: widget.maxLandscapeWidth,
        onArtworkTap: () => setState(() => _view = PlayerView.artwork),
        interactionSuspended: _destinationsOpen,
        background: PlayerExpansionReveal(
          animation: expansion,
          start: 0,
          rise: 0,
          child: LyricsBackdrop(
            imageUrl: track.coverUrl,
            reducedEffects: !widget.fullBackdrop && _view != PlayerView.lyrics,
          ),
        ),
        // The same native texture keeps flowing across artwork/lyrics/queue.
        lyricsBackground: const SizedBox.expand(),
        topBar:
            widget.topBar ??
            PlayerExpansionReveal(
              animation: expansion,
              start: 0.04,
              rise: 0.25,
              child: _TopBar(
                track: track,
                playbackContext: widget.playbackContext!,
              ),
            ),
        titleBuilder: (context, progress) => PlayerExpansionReveal(
          animation: expansion,
          child: _TitleRow(
            track: track,
            compact: true,
            lyricsProgress: progress,
            onTap: _view != PlayerView.artwork
                ? () => _showDestinations(context)
                : null,
          ),
        ),
        controlsHeightReduction: remote
            ? 0
            : PlaybackScrubber.expandedLabelHeight(context) + 8,
        footerHeightReduction: 12,
        controlsBuilder: (context, progress) => PlayerExpansionReveal(
          animation: expansion,
          opacityKey: const ValueKey('player-expansion-controls'),
          child: _ControlsGroup(
            track: track,
            glass: false,
            remote: remote,
            showTitle: false,
            lyricsProgress: progress,
            footer: widget.controlsFooter,
          ),
        ),
        footerBuilder: (context, progress) => PlayerExpansionReveal(
          animation: expansion,
          child: _BottomBar(
            view: _view,
            onToggle: _toggle,
            lyricsProgress: progress,
          ),
        ),
        artworkBuilder: (context, size, progress) => PlayerArtworkHero(
          imageUrl: track.coverUrl,
          child: TickerMode(
            enabled: progress == 0 && _view == PlayerView.artwork,
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
          lineCursor: widget.lyricsLineCursor ?? SystemMouseCursors.click,
        ),
        translation: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LyricsTranslationButton(),
            // 桌面对话框里额外提供沉浸式全屏歌词入口。
            if (widget.immersiveEntry &&
                MediaQuery.sizeOf(context).width >= 800) ...[
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
}

/// 歌名 + 进度条 + 播放控件；歌词视图下收进一块液态玻璃，歌词可从其上方滚过时仍清晰可读。
class _ControlsGroup extends StatelessWidget {
  final SpotifyTrack track;
  final bool glass;
  final bool remote;
  final bool showTitle;
  final double? lyricsProgress;
  final Widget? footer;

  const _ControlsGroup({
    required this.track,
    required this.glass,
    required this.remote,
    this.showTitle = true,
    this.lyricsProgress,
    this.footer,
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
        if (footer != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: lerpDouble(16, 4, compactness)!,
            ),
            child: footer,
          ),
        ],
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

/// 底栏：Connect 设备 + 歌词 / 队列视图切换（当前视图高亮并带小圆点）。
class _BottomBar extends StatelessWidget {
  final PlayerView view;
  final ValueChanged<PlayerView> onToggle;
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

    Widget toggle(PlayerView target, IconData icon, String tooltip) {
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
            PlayerView.lyrics,
            Icons.lyrics_outlined,
            context.l10n.lyricsTitle,
          ),
          toggle(
            PlayerView.queue,
            Icons.queue_music_rounded,
            context.l10n.queueTitle,
          ),
        ],
      ),
    );
  }
}
