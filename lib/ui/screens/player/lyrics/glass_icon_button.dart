import 'package:flutter/material.dart';

import '../../../../core/theme/flutify_tokens.dart';
import '../../../widgets/liquid_glass.dart';

/// 圆形液态玻璃图标按钮：歌词界面上的「全屏 / 关闭 / 退出」等浮动操作。
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool glass;
  final bool? selected;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
    this.glass = true,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      toggled: selected,
      child: AnimatedContainer(
        duration: context.motion(const Duration(milliseconds: 220)),
        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected == true ? Colors.white : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(icon, size: size * 0.45),
          color: selected == true ? Colors.black87 : Colors.white,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          isSelected: selected,
          onPressed: onPressed,
        ),
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
