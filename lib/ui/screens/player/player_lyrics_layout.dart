import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

enum PlayerSceneSlot {
  top,
  title,
  controls,
  footer,
  artwork,
  lyrics,
  toolbar,
  surface,
  queue,
}

/// Layout and clipping share the same measurements, including scaled text.
class PlayerLyricsGeometry {
  final Map<PlayerSceneSlot, Offset> _positions = {};
  double _footerTop = double.infinity;
  bool _retracting = false;

  Rect bodyClip(PlayerSceneSlot slot, Size size) => _retracting
      ? Rect.fromLTWH(
          0,
          0,
          size.width,
          (_footerTop - (_positions[slot]?.dy ?? 0)).clamp(0, size.height),
        )
      : Offset.zero & size;
}

/// The body slides below the fixed footer, clipped in paint AND hit testing.
class PlayerCardBodyClipper extends CustomClipper<Rect> {
  const PlayerCardBodyClipper({required this.geometry, required this.slot});

  final PlayerLyricsGeometry geometry;
  final PlayerSceneSlot slot;

  @override
  Rect getClip(Size size) => geometry.bodyClip(slot, size);

  // Geometry is filled during this frame's parent layout, after widget build.
  @override
  bool shouldReclip(PlayerCardBodyClipper oldClipper) => true;
}

/// Measures the controls first so text scaling never relies on a guessed height.
class PlayerLyricsLayout extends MultiChildLayoutDelegate {
  PlayerLyricsLayout({
    required this.progress,
    required this.chrome,
    required this.geometry,
  });

  final double progress;
  final double chrome;
  final PlayerLyricsGeometry geometry;

  void _position(PlayerSceneSlot slot, Offset position) {
    geometry._positions[slot] = position;
    positionChild(slot, position);
  }

  @override
  void performLayout(Size size) {
    const margin = 16.0;
    const inset = 12.0;
    final width = size.width;
    final landscape = width >= 600 && width > size.height;
    final cardWidth = landscape
        ? math.min(360.0, width * 0.46)
        : math.max(0.0, width - margin * 2);
    final cardLeft = width - margin - cardWidth;
    final contentWidth = landscape ? cardLeft - margin : width;
    // Rows containing a Column must receive an unbounded vertical constraint
    // while measuring, just as they did inside the original player Column.
    const loose = BoxConstraints();
    final top = layoutChild(PlayerSceneSlot.top, loose.tighten(width: width));
    _position(PlayerSceneSlot.top, Offset.zero);
    final footer = layoutChild(
      PlayerSceneSlot.footer,
      loose.tighten(width: cardWidth),
    );
    final controls = layoutChild(
      PlayerSceneSlot.controls,
      loose.tighten(width: cardWidth),
    );
    final coverSize = width < 360 ? 56.0 : 64.0;
    final footerY = size.height - 8 - footer.height;
    final controlsY = footerY - controls.height;
    final contentTop = top.height + 8;
    double contentHeightFor(double headerHeight) => math.max(
      0.0,
      (landscape ? size.height - 16 : controlsY - 8 - headerHeight - 24) -
          contentTop,
    );
    final largeSizeLimit = math.min(
      math.min(contentWidth * 0.86, 400.0),
      contentHeightFor(coverSize) * 0.9,
    );
    // Metadata shares the cover's eased progress without a second timing curve
    // or a moving destination. It must never overshoot and then slide back.
    final titleStart = landscape ? cardLeft + inset : 24.0;
    final titleLeft = lerpDouble(
      titleStart,
      cardLeft + inset + coverSize + 12,
      progress,
    )!;
    final title = layoutChild(
      PlayerSceneSlot.title,
      loose.tighten(width: math.max(0, width - titleLeft - 24)),
    );
    final headerHeight = math.max(coverSize, title.height);
    geometry._footerTop = footerY;
    final headerY = controlsY - 8 - headerHeight;
    final surfaceY = headerY - inset;
    final hiddenOffset = (footerY - surfaceY) * progress * (1 - chrome);
    geometry._retracting = hiddenOffset > 0;
    final surface = Rect.fromLTWH(
      cardLeft,
      surfaceY + hiddenOffset,
      cardWidth,
      size.height - 8 - surfaceY - hiddenOffset,
    );
    layoutChild(PlayerSceneSlot.surface, BoxConstraints.tight(surface.size));
    _position(PlayerSceneSlot.surface, surface.topLeft);
    _position(PlayerSceneSlot.footer, Offset(cardLeft, footerY));
    _position(
      PlayerSceneSlot.controls,
      Offset(cardLeft, controlsY + hiddenOffset),
    );
    _position(
      PlayerSceneSlot.title,
      Offset(
        titleLeft,
        headerY + (headerHeight - title.height) / 2 + hiddenOffset,
      ),
    );

    final contentHeight = contentHeightFor(headerHeight);
    final largeSize = math.min(largeSizeLimit, contentHeight * 0.9);
    final large = Rect.fromLTWH(
      (contentWidth - largeSize) / 2,
      contentTop + (contentHeight - largeSize) / 2,
      largeSize,
      largeSize,
    );
    final small = Rect.fromLTWH(
      cardLeft + inset,
      headerY + (headerHeight - coverSize) / 2 + hiddenOffset,
      coverSize,
      coverSize,
    );
    // The controller already applies Apple easing. Interpolate the whole rect
    // once so its center follows a straight line while size changes in sync.
    final artwork = Rect.lerp(large, small, progress)!;
    layoutChild(PlayerSceneSlot.artwork, BoxConstraints.tight(artwork.size));
    _position(PlayerSceneSlot.artwork, artwork.topLeft);

    final toolbar = layoutChild(
      PlayerSceneSlot.toolbar,
      BoxConstraints.loose(Size(cardWidth, 48)),
    );
    final toolbarInHeader =
        landscape && surfaceY < top.height + toolbar.height + 8;
    _position(
      PlayerSceneSlot.toolbar,
      Offset(
        width - margin - toolbar.width - (toolbarInHeader ? 56 : 0),
        (toolbarInHeader ? 6 : surfaceY - 8 - toolbar.height) +
            16 * (1 - chrome),
      ),
    );

    if (hasChild(PlayerSceneSlot.lyrics)) {
      // Tall screens can scroll behind the floating card. Compact screens keep
      // the focused line above the controls. Folding never changes this size.
      final lyricsHeight = size.height < 600 && !landscape
          ? math.max(0.0, surfaceY - toolbar.height - 16 - contentTop)
          : math.max(0.0, size.height - contentTop);
      layoutChild(
        PlayerSceneSlot.lyrics,
        BoxConstraints.tight(Size(contentWidth, lyricsHeight)),
      );
      _position(
        PlayerSceneSlot.lyrics,
        Offset(0, contentTop + (1 - progress) * lyricsHeight),
      );
    }
    layoutChild(
      PlayerSceneSlot.queue,
      BoxConstraints.tight(Size(contentWidth, contentHeight)),
    );
    _position(PlayerSceneSlot.queue, Offset(0, contentTop));
  }

  @override
  bool shouldRelayout(PlayerLyricsLayout oldDelegate) =>
      progress != oldDelegate.progress ||
      chrome != oldDelegate.chrome ||
      geometry != oldDelegate.geometry;
}
