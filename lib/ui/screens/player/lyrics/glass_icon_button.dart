import 'package:flutter/material.dart';

import '../../../widgets/liquid_glass.dart';

/// 圆形液态玻璃图标按钮：歌词界面上的「全屏 / 关闭 / 退出」等浮动操作。
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool glass;
  final bool selected;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
    this.glass = true,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox.square(
      dimension: size,
      child: IconButton(
        icon: Icon(icon, size: size * 0.45),
        color: Colors.white,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? Colors.white.withValues(alpha: 0.16)
              : null,
        ),
        isSelected: selected,
        onPressed: onPressed,
      ),
    );
    return glass
        ? LiquidGlass(
            borderRadius: BorderRadius.circular(size / 2),
            child: button,
          )
        : button;
  }
}
