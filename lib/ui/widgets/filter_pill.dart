import 'package:flutter/material.dart';

import '../../core/theme/md3e_colors.dart';
import '../../core/theme/md3e_shapes.dart';
import 'hover_builder.dart';

/// 胶囊筛选标签（音乐库类型、主页分类、右栏标签）。
///
/// 选中：亮绿底 + 黑字，深浅色主题一致（浅色主题的 primary 是加深绿，配黑字对比度不足）；
/// 未选中：容器色底，悬停时提亮一级。
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

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isSelected
                ? MD3EColors.spotifyGreen
                : (hovered ? colorScheme.surfaceContainerHighest : colorScheme.surfaceContainerHigh),
            borderRadius: MD3EShapes.pill,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: MD3EColors.spotifyGreen.withAlpha(70),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isSelected ? Colors.black : colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
