import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../models/app_preferences.dart';
import '../../../services/storage_service.dart';
import 'window_bounds_memory.dart';

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

  /// 沉浸式歌词正以「仅铺满窗口」方式显示：`WindowFrame` 不加窄窗口标题条，
  /// 窗口按钮以深色样式浮在右上角（沉浸式背景始终是深色）。
  static final ValueNotifier<bool> immersiveWindow = ValueNotifier(false);

  /// 在 runApp 之前调用。开启「记住窗口大小和位置」时，在窗口显示前就放到上次的位置（不闪一下再跳）。
  static Future<void> init(StorageService storage) async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    await windowManager.ensureInitialized();
    bool remember() => AppPreferences.decode(storage.preferencesJson).rememberWindow;
    final saved = remember() ? await WindowBoundsMemory.restorable(storage, minimumSize: minimumSize) : null;
    final options = WindowOptions(
      size: saved?.rect.size ?? const Size(1360, 860),
      minimumSize: minimumSize,
      center: saved == null,
      title: 'Flutify',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (saved != null) {
        await windowManager.setPosition(saved.rect.topLeft);
        if (saved.maximized) await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });
    // 监听器由 windowManager 持有，随进程存活
    WindowBoundsMemory(
      storage,
      minimumSize: minimumSize,
      enabled: remember,
      fullScreen: () => fullScreen.value,
    ).attach();
    // 拦截关闭（窗口按钮 / Alt+F4 / 任务栏），先跑完收尾钩子再销毁窗口
    await windowManager.setPreventClose(true);
    windowManager.addListener(_CloseGuard());
    _enabled = true;
  }

  static final List<(Future<void> Function(), Duration)> _beforeClose = [];

  /// 关窗前要完成的收尾（如保存播放进度）。每个钩子最多等 [timeout]，超时也照常关闭；
  /// 所有钩子并行执行。
  static void addBeforeCloseHook(Future<void> Function() hook, {Duration timeout = _closeTimeout}) =>
      _beforeClose.add((hook, timeout));

  static const Duration _closeTimeout = Duration(milliseconds: 800);

  static Future<void> _runBeforeClose() async {
    await Future.wait([
      for (final (hook, timeout) in _beforeClose) Future.sync(hook).timeout(timeout).catchError((Object _) {}),
    ]);
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

/// 收到关闭请求时先执行 [DesktopWindow.addBeforeCloseHook] 注册的收尾，再真正销毁窗口。
class _CloseGuard with WindowListener {
  bool _closing = false;

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;
    await DesktopWindow._runBeforeClose();
    await windowManager.destroy();
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
