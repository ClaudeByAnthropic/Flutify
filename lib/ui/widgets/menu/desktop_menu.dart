import 'package:flutter/material.dart';

/// 桌面端弹出菜单（曲目菜单、睡眠定时器、右栏 ⋯ 菜单共用），观感对齐 Spotify 桌面端：
/// 图标 + 文字 + 右侧快捷键提示 / 二级菜单箭头。
class DesktopMenu {
  DesktopMenu._();

  /// 在全局坐标 [position] 处弹出；返回选中的值。
  static Future<T?> show<T>(BuildContext context, Offset position, List<PopupMenuEntry<T>> items) {
    // 菜单显示在根 Navigator 的 Overlay 里：全局坐标需换算到它的本地坐标
    // （桌面窄窗口时它在标题条之下，并不从窗口原点开始）
    final overlay = Navigator.of(context, rootNavigator: true).overlay!.context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    final colorScheme = Theme.of(context).colorScheme;
    return showMenu<T>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
      color: colorScheme.surfaceContainerHigh,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 340),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: items,
    );
  }

  /// 组件左下角的全局坐标（按钮触发的菜单从这里弹出）。
  static Offset anchorOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(box.size.bottomLeft(Offset.zero));
  }

  /// 菜单项。[shortcut] 为右侧灰色快捷键提示；[submenu] 为 true 时右侧显示 ▸。
  static PopupMenuItem<T> item<T>(
    T value,
    IconData icon,
    String label, {
    Color? iconColor,
    String? shortcut,
    bool submenu = false,
    bool enabled = true,
  }) {
    return PopupMenuItem<T>(
      value: value,
      height: 40,
      enabled: enabled,
      child: Builder(
        builder: (context) {
          final muted = Theme.of(context).colorScheme.onSurfaceVariant;
          return Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 12),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (shortcut != null) ...[
                const SizedBox(width: 16),
                Text(shortcut, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
              ],
              if (submenu) ...[const SizedBox(width: 8), Icon(Icons.arrow_right_rounded, size: 20, color: muted)],
            ],
          );
        },
      ),
    );
  }

  /// 带勾选标记的选项（例如当前生效的定时器预设）。
  static PopupMenuItem<T> check<T>(T value, String label, {required bool checked}) {
    return PopupMenuItem<T>(
      value: value,
      height: 40,
      child: Builder(
        builder: (context) => Row(
          children: [
            SizedBox(
              width: 20,
              child: checked ? Icon(Icons.check_rounded, size: 20, color: Theme.of(context).colorScheme.primary) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  static const PopupMenuDivider divider = PopupMenuDivider(height: 8);
}
