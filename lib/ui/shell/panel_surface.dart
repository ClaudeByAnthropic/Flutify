import 'package:flutter/material.dart';

/// 桌面端三栏中的单块面板：圆角 16、内容裁切、底色为 `surface`。
///
/// 面板浮在更深一级的窗口底色（`surfaceContainerLowest`）之上，
/// 靠色阶差而不是描边或阴影来分隔，与 Spotify 新版桌面端一致。
/// 使用 [Material] 而非 DecoratedBox，保证子树中的水波纹可见。
class PanelSurface extends StatelessWidget {
  final Widget child;

  const PanelSurface({super.key, required this.child});

  static const BorderRadius radius = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
