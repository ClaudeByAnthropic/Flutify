import 'package:flutter/material.dart';

import '../../../../core/theme/md3e_colors.dart';
import '../../../../core/theme/md3e_shapes.dart';
import '../login_method.dart';

/// "更多方式"底部面板：列出 [LoginMethod.more] 中的备用登录方式。
class LoginMethodSheet extends StatelessWidget {
  const LoginMethodSheet({super.key});

  static Future<LoginMethod?> show(BuildContext context) => showModalBottomSheet<LoginMethod>(
        context: context,
        showDragHandle: true,
        // 按内容高度展开，小屏放不下时在面板内滚动
        isScrollControlled: true,
        builder: (_) => const LoginMethodSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text('其他登录方式', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final method in LoginMethod.more) ...[
              _MethodTile(method: method),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final LoginMethod method;

  const _MethodTile({required this.method});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: MD3EShapes.roundedMedium,
      child: InkWell(
        borderRadius: MD3EShapes.roundedMedium,
        onTap: () => Navigator.pop(context, method),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MD3EColors.spotifyGreen.withAlpha(36),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(method.icon, color: MD3EColors.spotifyGreen, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(method.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      method.description,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
