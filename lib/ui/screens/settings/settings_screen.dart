import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import 'sections/accent_section.dart';
import 'sections/appearance_section.dart';
import 'sections/glass_section.dart';
import 'sections/motion_section.dart';
import 'sections/text_shape_section.dart';
import 'widgets/account_card.dart';

/// 设置页（iOS「设置」式分组布局）：
/// 账号 → 外观 → 强调色 → 液态玻璃 → 文字与形状 → 动效。
///
/// 所有外观项修改后即时生效、自动保存，无需「保存」按钮。
/// 桌面宽窗口下内容居中、限宽 720，避免整行拉得过长。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const double _maxContentWidth = 720;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.commonSettings)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: const [
              AccountCard(),
              SizedBox(height: 28),
              AppearanceSection(),
              AccentSection(),
              GlassSection(),
              TextShapeSection(),
              MotionSection(),
            ],
          ),
        ),
      ),
    );
  }
}
