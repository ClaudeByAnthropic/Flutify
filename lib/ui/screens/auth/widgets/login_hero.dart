import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'flutify_mark.dart';

/// 登录页主视觉：品牌标坐落在一枚缓慢自转的 MD3E 表现力形状（十二瓣曲奇）上，
/// 外圈再叠一枚反向转动、更淡的柔和爆裂形，形成有层次的「呼吸」感。
///
/// 减弱动效时两层形状静止。
class LoginHero extends StatefulWidget {
  final double size;

  const LoginHero({super.key, this.size = 168});

  @override
  State<LoginHero> createState() => _LoginHeroState();
}

class _LoginHeroState extends State<LoginHero>
    with SingleTickerProviderStateMixin {
  /// 一整圈 40 秒：慢到几乎察觉不到，只让画面「活着」。
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: ReverseAnimation(_spin),
            child: M3EShapeContainer(
              kind: M3EShapeKind.softBurst,
              width: s,
              height: s,
              color: colorScheme.primary.withAlpha(22),
            ),
          ),
          RotationTransition(
            turns: _spin,
            child: M3EShapeContainer(
              kind: M3EShapeKind.cookie12Sided,
              width: s * 0.78,
              height: s * 0.78,
              color: colorScheme.primaryContainer,
            ),
          ),
          FlutifyMark(size: s * 0.42),
        ],
      ),
    );
  }
}
