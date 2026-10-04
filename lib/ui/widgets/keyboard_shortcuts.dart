import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../shell/desktop/desktop_window.dart';

/// 桌面快捷键的按平台策略与提示文字渲染。
///
/// macOS 桌面真实运行（[DesktopWindow.macNativeWindow]）时主修饰键用 ⌘（Cmd）替代 Ctrl，
/// 提示文字按 macOS 惯例紧凑排（⌘K / ⌥⇧B）；Windows / Linux / 测试（DesktopWindow 未
/// 初始化）一律沿用 Ctrl / Alt 版本，行为与之前逐字节一致。
///
/// 纯单键快捷键（Space、F11、Esc、悬停曲目的字母键）不走这里，各平台不变。
abstract final class PlatformShortcuts {
  /// 主修饰键是否取 macOS 的 meta（⌘）。
  static bool get useMeta => DesktopWindow.macNativeWindow;

  /// 「主修饰键 + [key]」的按平台快捷键：macOS 为 ⌘+key，其余为 Ctrl+key。
  static SingleActivator primary(
    LogicalKeyboardKey key, {
    bool shift = false,
  }) => SingleActivator(key, control: !useMeta, meta: useMeta, shift: shift);

  /// 修饰键名按平台替换为键帽标签：Ctrl → ⌘ / Ctrl，Alt → ⌥ / Alt，Shift → ⇧ / Shift。
  static String cap(String key) => switch (key) {
    'Ctrl' => useMeta ? '⌘' : key,
    'Alt' => useMeta ? '⌥' : key,
    'Shift' => useMeta ? '⇧' : key,
    _ => key,
  };

  /// 快捷键提示拆成键帽序列（快捷键一览用）：'Ctrl K'、'Alt+Shift+B' 均可，
  /// 修饰键名按平台替换（见 [cap]）。
  static List<String> keyCaps(String hint) => [
    for (final token in hint.split(RegExp(r'[+ ]')))
      if (token.isNotEmpty) cap(token),
  ];

  /// 单行快捷键提示（菜单右侧标注用）：macOS 按惯例去掉分隔符、按 ⌥⇧⌘ 顺序紧凑排
  /// （'Ctrl K' → ⌘K，'Alt+Shift+B' → ⌥⇧B）；其余平台原样返回。
  static String hintText(String hint) {
    if (!useMeta) return hint;
    final caps = keyCaps(hint);
    caps.sort(_macCapOrder);
    return caps.join();
  }

  /// macOS 修饰键显示顺序：⌥(0) ⇧(1) ⌘(2)，其余键排在最后。
  static int _macRank(String capStr) => switch (capStr) {
    '⌥' => 0,
    '⇧' => 1,
    '⌘' => 2,
    _ => 3,
  };

  static int _macCapOrder(String a, String b) => _macRank(a) - _macRank(b);
}
