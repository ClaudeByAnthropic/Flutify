import 'package:flutter/material.dart';

import '../../../widgets/liquid_glass.dart';

/// 圆形液态玻璃图标按钮：歌词界面上的「全屏 / 关闭 / 退出」等浮动操作。
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      // 圆形按钮不随「圆角风格」变化，始终为正圆
      borderRadius: BorderRadius.circular(size / 2),
      child: SizedBox.square(
        dimension: size,
        child: IconButton(
          icon: Icon(icon, size: size * 0.45),
          color: Colors.white,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
