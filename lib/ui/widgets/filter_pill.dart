import 'package:flutter/material.dart';

import '../../core/theme/flutify_tokens.dart';
import 'hover_builder.dart';

/// 胶囊筛选标签（音乐库类型、主页分类、右栏标签）。
///
/// 选中：强调色底 + 自动黑 / 白字（深浅色主题一致；浅色主题的 primary 是加深色，不用它做填充）；
/// 未选中：容器色底，悬停时提亮一级。圆角随「圆角风格」变化。
class FilterPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const FilterPill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 200)),
          curve: Curves.easeOutCubic,
          // MiSans 的字身框偏上（汉字视觉重心高于行框中心），上下内边距不对称补偿 1.5px，使文字视觉居中
          padding: const EdgeInsets.fromLTRB(16.0, 9.5, 16.0, 6.5),
          decoration: BoxDecoration(
            color: isSelected
                ? tokens.accent
                : (hovered ? colorScheme.surfaceContainerHighest : colorScheme.surfaceContainerHigh),
            borderRadius: tokens.pill,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: tokens.accent.withAlpha(70),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isSelected ? tokens.onAccent : colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
