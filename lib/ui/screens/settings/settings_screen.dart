import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../shell/shell_breakpoints.dart';
import 'sections/accent_section.dart';
import 'sections/appearance_section.dart';
import 'sections/glass_section.dart';
import 'sections/motion_section.dart';
import 'sections/playback_section.dart';
import 'sections/text_shape_section.dart';
import 'widgets/account_card.dart';

/// 设置页：账号 → 播放 → 外观 → 强调色 → 液态玻璃 → 文字与形状 → 动效。
///
/// 所有设置项修改后即时生效、自动保存，无需「保存」按钮。按窗口形态分两套布局：
/// - 移动端：iOS「设置」式单列分组，顶部 AppBar 带返回；
/// - 桌面端：嵌在主框架内容区（顶栏负责后退），大标题 + 横向设置行
///   （标题在左、控件在右）；内容区足够宽时分为左右两栏。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// 桌面端推入内容区时的路由名，用于避免重复打开。
  static const String routeName = '/settings';

  @override
  Widget build(BuildContext context) {
    final desktop = ShellBreakpoints.isDesktop(MediaQuery.sizeOf(context).width);
    return desktop ? const _DesktopSettings() : const _MobileSettings();
  }
}

/// 移动端：单列、限宽 720（平板横屏时不拉得过长）。
class _MobileSettings extends StatelessWidget {
  const _MobileSettings();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.commonSettings)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: const [
              AccountCard(),
              SizedBox(height: 28),
              PlaybackSection(),
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

/// 桌面端：内容区内左对齐的大标题页面。
///
/// - 内容区宽 ≥ [_twoColumnWidth]：左栏「账号 / 外观 / 文字与形状 / 动效」，
///   右栏「播放 / 强调色 / 液态玻璃」（玻璃带预览，较高），两栏高度大致平衡；
/// - 更窄时单列，限宽 [_singleColumnMaxWidth]。
class _DesktopSettings extends StatelessWidget {
  const _DesktopSettings();

  static const double _twoColumnWidth = 1040;
  static const double _singleColumnMaxWidth = 760;
  static const double _twoColumnMaxWidth = 1240;
  static const double _columnGap = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= _twoColumnWidth;
          final body = twoColumns
              ? const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AccountCard(),
                          SizedBox(height: 28),
                          AppearanceSection(),
                          TextShapeSection(),
                          MotionSection(),
                        ],
                      ),
                    ),
                    SizedBox(width: _columnGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [PlaybackSection(), AccentSection(), GlassSection()],
                      ),
                    ),
                  ],
                )
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AccountCard(),
                    SizedBox(height: 28),
                    PlaybackSection(),
                    AppearanceSection(),
                    AccentSection(),
                    GlassSection(),
                    TextShapeSection(),
                    MotionSection(),
                  ],
                );

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: twoColumns ? _twoColumnMaxWidth : _singleColumnMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.commonSettings,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 24),
                    body,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
