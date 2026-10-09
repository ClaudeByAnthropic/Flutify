import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../widgets/liquid_glass.dart';
import 'player_lyrics_layout.dart';
import 'player_lyrics_motion.dart';

/// Android-only composition. Each slot keeps its identity as its bounds move;
/// playback and translation remain owned by the existing player widgets.
class AndroidPlayerScene extends StatefulWidget {
  const AndroidPlayerScene({
    super.key,
    required this.lyricsMode,
    required this.queueMode,
    required this.background,
    required this.lyricsBackground,
    required this.topBar,
    this.title,
    this.titleBuilder,
    required this.controls,
    required this.footer,
    required this.artworkBuilder,
    required this.lyrics,
    required this.translation,
    required this.queue,
    this.onArtworkTap,
    this.interactionSuspended = false,
  }) : assert((title == null) != (titleBuilder == null));

  final bool lyricsMode;
  final bool queueMode;
  final Widget background;
  final Widget lyricsBackground;
  final Widget topBar;

  final Widget? title;

  /// Alternative to [title], using the artwork's already-eased progress (0–1).
  final Widget Function(BuildContext context, double progress)? titleBuilder;
  final Widget controls;
  final Widget footer;
  final Widget Function(BuildContext context, double size, double progress)
  artworkBuilder;
  final Widget lyrics;
  final Widget translation;
  final Widget queue;
  final VoidCallback? onArtworkTap;
  final bool interactionSuspended;

  @override
  State<AndroidPlayerScene> createState() => _AndroidPlayerSceneState();
}

class _AndroidPlayerSceneState extends State<AndroidPlayerScene>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final PlayerLyricsController _motion;
  final PlayerLyricsGeometry _geometry = PlayerLyricsGeometry();
  bool _tickerEnabled = true;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    _motion = PlayerLyricsController(vsync: this);
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_releasePointer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.configure(
      reduceMotion: context.reduceMotion,
      accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
    );
    _motion.setLyrics(widget.lyricsMode);
    _motion.setInteractionSuspended(widget.interactionSuspended);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _motion.setActive(_appActive && _tickerEnabled);
  }

  @override
  void didUpdateWidget(AndroidPlayerScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _motion.setLyrics(widget.lyricsMode);
    _motion.setInteractionSuspended(widget.interactionSuspended);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _motion.setActive(_appActive && _tickerEnabled);
  }

  void _releasePointer(PointerEvent event) {
    // A reveal, modal, or route transition may change the original hit tree.
    // Complete only pointers this scene enrolled, even if local up is lost.
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _motion.pointerUp(event.pointer);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_releasePointer);
    _motion.dispose();
    super.dispose();
  }

  Widget _chrome(Widget child, {double factor = 1}) => ExcludeFocus(
    excluding: !_motion.controlsVisible || factor == 0,
    child: ExcludeSemantics(
      excluding: !_motion.controlsVisible || factor == 0,
      child: IgnorePointer(
        ignoring: !_motion.controlsVisible || factor == 0,
        child: Opacity(opacity: _motion.chrome.value * factor, child: child),
      ),
    ),
  );

  Widget _cardHitRegion(Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTap: widget.lyricsMode ? () {} : null,
    onVerticalDragUpdate: widget.lyricsMode ? (_) {} : null,
    child: child,
  );

  Widget _body(PlayerSceneSlot slot, Widget child) => ExcludeFocus(
    excluding: !_motion.controlsVisible,
    child: ExcludeSemantics(
      excluding: !_motion.controlsVisible,
      child: IgnorePointer(
        ignoring: !_motion.controlsVisible,
        child: ClipRect(
          clipper: PlayerCardBodyClipper(geometry: _geometry, slot: slot),
          child: child,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) => _motion.pointerDown(event.pointer),
    onPointerMove: (_) => _motion.activity(),
    onPointerUp: (event) => _motion.pointerUp(event.pointer),
    onPointerCancel: (event) => _motion.pointerUp(event.pointer),
    onPointerSignal: (_) => _motion.activity(),
    child: MouseRegion(
      onHover: (_) => _motion.activity(),
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          final progress = _motion.transition.value;
          final hasLyrics = widget.lyricsMode || progress > 0;
          Widget slot(PlayerSceneSlot id, Widget child) =>
              LayoutId(id: id, child: child);
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.background,
              if (hasLyrics)
                IgnorePointer(
                  child: Opacity(
                    key: const ValueKey('lyrics-background-blend'),
                    opacity: progress,
                    child: widget.lyricsBackground,
                  ),
                ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.orientationOf(context) ==
                              Orientation.landscape
                          ? 960
                          : 480,
                    ),
                    child: ClipRect(
                      child: CustomMultiChildLayout(
                        delegate: PlayerLyricsLayout(
                          progress: progress,
                          chrome: _motion.chrome.value,
                          geometry: _geometry,
                        ),
                        children: [
                          if (hasLyrics)
                            slot(
                              PlayerSceneSlot.lyrics,
                              IgnorePointer(
                                ignoring: !widget.lyricsMode,
                                child: Opacity(
                                  opacity: progress,
                                  child: widget.lyrics,
                                ),
                              ),
                            ),
                          slot(
                            PlayerSceneSlot.queue,
                            IgnorePointer(
                              ignoring: !widget.queueMode,
                              child: AnimatedOpacity(
                                duration: context.motion(
                                  PlayerLyricsMotion.duration,
                                ),
                                curve: PlayerLyricsMotion.curve,
                                opacity: widget.queueMode ? 1 : 0,
                                child: widget.queueMode
                                    ? widget.queue
                                    : const SizedBox.expand(),
                              ),
                            ),
                          ),
                          slot(
                            PlayerSceneSlot.surface,
                            IgnorePointer(
                              ignoring: progress == 0,
                              child: Opacity(
                                opacity: progress,
                                child: _cardHitRegion(
                                  LiquidGlass(
                                    key: const ValueKey('lyrics-control-card'),
                                    borderRadius: context.tokens.radius(28),
                                    child: const ColoredBox(
                                      color: Color(0x59101216),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          slot(
                            PlayerSceneSlot.title,
                            _body(
                              PlayerSceneSlot.title,
                              _cardHitRegion(
                                widget.titleBuilder?.call(context, progress) ??
                                    widget.title!,
                              ),
                            ),
                          ),
                          slot(
                            PlayerSceneSlot.controls,
                            _body(
                              PlayerSceneSlot.controls,
                              _cardHitRegion(widget.controls),
                            ),
                          ),
                          slot(
                            PlayerSceneSlot.footer,
                            _cardHitRegion(widget.footer),
                          ),
                          slot(
                            PlayerSceneSlot.artwork,
                            _body(
                              PlayerSceneSlot.artwork,
                              Semantics(
                                label: widget.lyricsMode
                                    ? MaterialLocalizations.of(
                                        context,
                                      ).backButtonTooltip
                                    : null,
                                button:
                                    widget.lyricsMode &&
                                    widget.onArtworkTap != null,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: widget.lyricsMode
                                      ? widget.onArtworkTap
                                      : null,
                                  onVerticalDragUpdate: widget.lyricsMode
                                      ? (_) {}
                                      : null,
                                  child: IgnorePointer(
                                    ignoring:
                                        widget.lyricsMode || widget.queueMode,
                                    child: ExcludeSemantics(
                                      excluding:
                                          widget.lyricsMode || widget.queueMode,
                                      child: Opacity(
                                        opacity: widget.queueMode
                                            ? progress
                                            : 1,
                                        child: LayoutBuilder(
                                          builder: (context, box) =>
                                              widget.queueMode && progress == 0
                                              ? const SizedBox.shrink()
                                              : widget.artworkBuilder(
                                                  context,
                                                  box.maxWidth,
                                                  progress,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          slot(
                            PlayerSceneSlot.toolbar,
                            IgnorePointer(
                              ignoring: !widget.lyricsMode,
                              child: _chrome(
                                widget.translation,
                                factor: progress,
                              ),
                            ),
                          ),
                          slot(PlayerSceneSlot.top, widget.topBar),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
