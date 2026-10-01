import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口外观：隐藏系统标题栏，由顶栏自绘（拖动区 + 最小化 / 最大化 / 关闭）。
///
/// 只在 Windows / macOS / Linux 的真实运行中启用；Widget 测试和移动端
/// [enabled] 为 false，顶栏不渲染窗口按钮、不调用任何原生通道。
class DesktopWindow {
  DesktopWindow._();

  static bool _enabled = false;

  /// 自绘标题栏是否生效。
  static bool get enabled => _enabled;

  /// 窗口最小尺寸：可缩到手机宽度，窄于 `ShellBreakpoints.desktop` 时切换为移动端布局，
  /// 便于在桌面上直接调试手机界面。
  static const Size minimumSize = Size(360, 600);

  /// 当前是否处于系统全屏（沉浸式歌词）；全屏时 `WindowFrame` 隐藏窗口按钮与标题条。
  static final ValueNotifier<bool> fullScreen = ValueNotifier(false);

  /// 在 runApp 之前调用。
  static Future<void> init() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1360, 860),
      minimumSize: minimumSize,
      center: true,
      title: 'Flutify',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    _enabled = true;
  }

  static Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 进入 / 退出系统全屏（沉浸式歌词使用）。未启用自绘标题栏（测试、移动端）时不做任何事。
  static Future<void> setFullScreen(bool value) async {
    if (!_enabled) return;
    fullScreen.value = value;
    if (await windowManager.isFullScreen() == value) return;
    await windowManager.setFullScreen(value);
  }
}

/// 窗口拖动区：按住拖动移动窗口，双击最大化 / 还原（Windows 标题栏行为）。
/// 未启用自绘标题栏时原样返回子组件。
class WindowDragArea extends StatelessWidget {
  final Widget child;

  const WindowDragArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.enabled) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: DesktopWindow.toggleMaximize,
      child: child,
    );
  }
}
