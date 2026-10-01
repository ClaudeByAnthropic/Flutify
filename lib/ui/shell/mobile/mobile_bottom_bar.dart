import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../widgets/mini_player.dart';

/// 移动端底部区域：悬浮胶囊迷你播放器 + 毛玻璃底部导航。
///
/// 配合 `Scaffold(extendBody: true)` 使用：内容滚动到导航栏下方时透过毛玻璃可见；
/// 迷你播放器背后铺一层由透明渐变到页面底色的遮罩，保证其边缘的文字 / 封面不与内容混在一起。
/// 整体高度通过 MediaQuery 底部 padding 传给页面（见 ContentBottomSpacer）。
class MobileBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const MobileBottomBar({super.key, required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colorScheme.surface.withAlpha(0), colorScheme.surface.withAlpha(170)],
            ),
          ),
          child: const MiniPlayer(),
        ),
        _GlassNavigationBar(selectedIndex: selectedIndex, onSelected: onSelected),
      ],
    );
  }
}

class _GlassNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _GlassNavigationBar({required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final l10n = context.l10n;
    final tokens = context.tokens;
    // 底色不透明度随设置页「玻璃不透明度」变化（默认 0.3 → 深色 175 / 浅色 205）；
    // 浅色下需要更高的不透明度，否则白底上的深色内容会让图标难以辨认
    final alpha = (isDark ? 120 + tokens.glassOpacity * 185 : 150 + tokens.glassOpacity * 183).clamp(0, 250).round();
    final sigma = tokens.glassSigma * 0.8;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withAlpha(alpha),
            border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(110), width: 0.5)),
          ),
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_filled),
                label: l10n.navHome,
              ),
              NavigationDestination(
                icon: const Icon(Icons.search_rounded),
                selectedIcon: const Icon(Icons.search_rounded),
                label: l10n.navSearch,
              ),
              NavigationDestination(
                icon: const Icon(Icons.library_music_outlined),
                selectedIcon: const Icon(Icons.library_music_rounded),
                label: l10n.navLibrary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
