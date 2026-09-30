import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/playback_provider.dart';
import '../navigation/app_routes.dart';
import '../navigation/tab_navigator.dart';
import '../widgets/desktop_player_bar.dart';
import '../widgets/mini_player.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'search/search_screen.dart';
import 'settings/settings_screen.dart';

/// 响应式主框架：移动端底部导航 + 悬浮迷你播放器；桌面端侧边导航 + 底部播放栏。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(3, (_) => GlobalKey<NavigatorState>());

  // 各 Tab 根页面只创建一次，切换 Tab 与窗口尺寸变化时不再重新构造
  late final List<Widget> _roots = [
    HomeScreen(onOpenSettings: _openSettings),
    const SearchScreen(),
    LibraryScreen(onOpenSettings: _openSettings),
  ];

  @override
  void initState() {
    super.initState();
    AppRoutes.contentNavigator = () => _navigatorKeys[_currentIndex].currentState;
  }

  @override
  void dispose() {
    AppRoutes.contentNavigator = null;
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  /// 再次点击当前 Tab：回到该 Tab 根页面（Spotify 行为）。
  void _select(int index) {
    if (index == _currentIndex) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _currentIndex = index);
  }

  /// 桌面快捷键（与 Spotify 桌面端一致）。输入框聚焦时空格会被 TextField 拦截，不会误触。
  Map<ShortcutActivator, VoidCallback> _shortcuts(PlaybackProvider playback) => {
        const SingleActivator(LogicalKeyboardKey.space): playback.togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): playback.nextTrack,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): playback.previousTrack,
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () =>
            playback.setVolume(playback.volume + 0.1, persist: true),
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () =>
            playback.setVolume(playback.volume - 0.1, persist: true),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): playback.toggleShuffle,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): playback.cycleRepeatMode,
      };

  @override
  Widget build(BuildContext context) {
    // sizeOf 只在尺寸变化时触发重建（MediaQuery.of 会随键盘动画每帧重建）
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    final l10n = context.l10n;
    final pages = IndexedStack(
      index: _currentIndex,
      children: [
        for (var i = 0; i < _roots.length; i++)
          TabNavigator(navigatorKey: _navigatorKeys[i], root: _roots[i], active: i == _currentIndex),
      ],
    );

    if (isDesktop) {
      return CallbackShortcuts(
        bindings: _shortcuts(context.read<PlaybackProvider>()),
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _currentIndex,
                        onDestinationSelected: _select,
                        labelType: NavigationRailLabelType.all,
                        leading: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20.0),
                          child: Icon(Icons.music_note_rounded, color: Color(0xFF1ED760), size: 36),
                        ),
                        trailing: Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 20.0),
                              child: IconButton(
                                icon: const Icon(Icons.tune_rounded),
                                tooltip: l10n.commonSettings,
                                onPressed: _openSettings,
                              ),
                            ),
                          ),
                        ),
                        destinations: [
                          NavigationRailDestination(
                            icon: const Icon(Icons.home_outlined),
                            selectedIcon: const Icon(Icons.home_filled),
                            label: Text(l10n.navHome),
                          ),
                          NavigationRailDestination(
                            icon: const Icon(Icons.search_rounded),
                            selectedIcon: const Icon(Icons.search_rounded),
                            label: Text(l10n.navSearch),
                          ),
                          NavigationRailDestination(
                            icon: const Icon(Icons.library_music_outlined),
                            selectedIcon: const Icon(Icons.library_music_rounded),
                            label: Text(l10n.navLibrary),
                          ),
                        ],
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: pages),
                    ],
                  ),
                ),
                const DesktopPlayerBar(),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          pages,
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _select,
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
    );
  }
}
