import 'package:flutter/material.dart';

import '../shell_breakpoints.dart';
import 'desktop_window.dart';
import 'window_caption_buttons.dart';

/// 桌面窗口外框：保证任何页面（设置、登录、全屏对话框……）都能移动、缩放、关闭窗口。
///
/// 放在 `MaterialApp.builder` 中，位于所有路由之上：
/// - 宽窗口（桌面布局）：窗口按钮浮在右上角，顶栏只为它留出空位，并负责拖动；
/// - 窄窗口（移动端布局）：顶部加一条 32px 标题条（拖动区 + 窗口按钮），内容整体下移，
///   相当于在桌面上模拟手机屏幕；
/// - 系统全屏（沉浸式歌词）时两者都隐藏；沉浸式歌词仅铺满窗口时只浮深色窗口按钮；
/// - 未启用自绘标题栏（测试、移动端）时原样返回子组件。
///
/// 自带一层 [Overlay]：Builder 位于 Navigator 之外，窗口按钮的 Tooltip 需要它。
class WindowFrame extends StatefulWidget {
  final Widget child;

  const WindowFrame({super.key, required this.child});

  /// 窄窗口标题条高度。
  static const double captionHeight = 32;

  @override
  State<WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<WindowFrame> {
  // 只创建一次；子组件变化时让入口重建，而不是重建整个 Overlay
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => _FrameBody(child: widget.child));

  @override
  void didUpdateWidget(WindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) _entry.markNeedsBuild();
  }

  // 外框与应用同生命周期，入口随 Overlay 一起销毁，无需手动 remove

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.enabled) return widget.child;
    return Overlay(initialEntries: [_entry]);
  }
}

class _FrameBody extends StatelessWidget {
  final Widget child;

  const _FrameBody({required this.child});

  @override
  Widget build(BuildContext context) {
    final wide = ShellBreakpoints.isDesktop(MediaQuery.sizeOf(context).width);
    return ListenableBuilder(
      listenable: Listenable.merge([DesktopWindow.fullScreen, DesktopWindow.immersiveWindow]),
      child: child,
      builder: (context, child) {
        if (DesktopWindow.fullScreen.value) return child!;
        // 沉浸式歌词铺满窗口：任何宽度都只浮窗口按钮，深色样式贴合深色背景
        if (DesktopWindow.immersiveWindow.value) {
          return Stack(
            children: [
              Positioned.fill(child: child!),
              Positioned(
                top: 0,
                right: 0,
                child: Theme(
                  data: ThemeData(brightness: Brightness.dark, colorScheme: const ColorScheme.dark()),
                  child: const WindowCaptionButtons(),
                ),
              ),
            ],
          );
        }
        if (wide) {
          return Stack(
            children: [
              Positioned.fill(child: child!),
              const Positioned(top: 0, right: 0, child: WindowCaptionButtons()),
            ],
          );
        }
        // 标题条之下才是「手机屏幕」：MediaQuery 尺寸同步减去标题条高度
        final media = MediaQuery.of(context);
        final screen = Size(media.size.width, media.size.height - WindowFrame.captionHeight);
        return Column(
          children: [
            const _CaptionStrip(),
            Expanded(
              child: MediaQuery(
                data: media.copyWith(size: screen, padding: EdgeInsets.zero),
                child: child!,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 窄窗口标题条：左侧应用名，其余为拖动区，右侧窗口按钮。
class _CaptionStrip extends StatelessWidget {
  const _CaptionStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SizedBox(
        height: WindowFrame.captionHeight,
        child: Row(
          children: [
            Expanded(
              child: WindowDragArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Flutify',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const WindowCaptionButtons(height: WindowFrame.captionHeight),
          ],
        ),
      ),
    );
  }
}
