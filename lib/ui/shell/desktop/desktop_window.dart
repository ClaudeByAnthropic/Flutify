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
    if (!value) await _refreshFrame();
  }

  /// 退出全屏后强制原生窗口重算边框、重排 Flutter 视图。
  ///
  /// window_manager 在 Windows 上只有收到 SIZE_MAXIMIZED 才记为「已进入全屏」；
  /// 从普通窗口进入全屏时收到的是 SIZE_RESTORED，状态没记上，退出时就跳过了
  /// 子视图刷新，客户区残留全屏时的尺寸，露出大片黑边。
  /// 宽度临时 +1 再改回，触发两次 WM_SIZE，让子视图贴合新的客户区。
  static Future<void> _refreshFrame() async {
    if (!Platform.isWindows) return;
    // 等原生还原落定：进入全屏前若是最大化，插件会异步再发一次 SC_MAXIMIZE
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (await windowManager.isFullScreen() || await windowManager.isMaximized()) return;
    final size = await windowManager.getSize();
    await windowManager.setSize(Size(size.width + 1, size.height));
    await windowManager.setSize(size);
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
