import 'package:flutter/material.dart';

import '../../../../core/theme/md3e_colors.dart';

/// 登录各阶段共用的页头：图标（或品牌标）+ 大标题 + 说明。
class StageHeader extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;

  const StageHeader({super.key, required this.leading, required this.title, required this.subtitle});

  /// 圆形品牌色底的功能图标。
  static Widget icon(IconData icon) => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(color: MD3EColors.spotifyGreen.withAlpha(36), shape: BoxShape.circle),
        child: Icon(icon, color: MD3EColors.spotifyGreen, size: 32),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: leading),
        const SizedBox(height: 28),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 36),
      ],
    );
  }
}

/// 全宽主按钮：忙碌时显示进度圈与说明文字。
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: busy
              ? Row(
                  key: const ValueKey('busy'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: onPrimary.withAlpha(160)),
                    ),
                    const SizedBox(width: 12),
                    Text(busyLabel),
                  ],
                )
              : Text(label, key: const ValueKey('idle')),
        ),
      ),
    );
  }
}

/// 表单下方的错误提示条；无错误时收起。
class AuthErrorBanner extends StatelessWidget {
  final String? message;

  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message!,
                        style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// 主操作与次要入口之间的"或"分隔线。
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: colorScheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('或', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
        ),
        Expanded(child: Divider(color: colorScheme.outlineVariant)),
      ],
    );
  }
}

/// 表单下方的弱提示文字（带图标）。
class AuthHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const AuthHint({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: muted)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5))),
      ],
    );
  }
}
