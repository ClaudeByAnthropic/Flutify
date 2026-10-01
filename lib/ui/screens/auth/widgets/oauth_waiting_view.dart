import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../providers/auth_provider.dart';
import '../../../widgets/toast/app_toast.dart';

/// 浏览器授权的等待态：授权页已在浏览器中打开，回调到达后自动完成登录。
///
/// 视觉：MD3E 的形状变换加载指示器（带容器）+ 大标题；下方是「重新打开浏览器 / 复制链接」
/// 的按钮组与「取消」文字按钮三个出口。
class OAuthWaitingView extends StatelessWidget {
  const OAuthWaitingView({super.key});

  /// 用系统浏览器打开授权页；打不开时把链接复制到剪贴板并提示手动粘贴。
  static Future<void> launch(BuildContext context, Uri url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: url.toString()));
      AppToast.showOn(
        messenger,
        '无法自动打开浏览器，登录链接已复制，请粘贴到浏览器中打开',
        icon: Icons.content_paste_rounded,
        tone: ToastTone.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final auth = context.watch<AuthProvider>();
    final url = auth.authorizeUrl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: M3ELoadingIndicator(
            variant: M3ELoadingIndicatorVariant.contained,
            constraints: BoxConstraints.tight(const Size.square(120)),
            color: colorScheme.onPrimaryContainer,
            containerColor: colorScheme.primaryContainer,
          ),
        ),
        const SizedBox(height: 40),
        Text(
          '在浏览器中完成登录',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        ),
        const SizedBox(height: 12),
        Text(
          '登录并同意授权后，这里会自动继续',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 40),
        if (url != null)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.tonalIcon(
                    onPressed: () => launch(context, url),
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: const Text('重新打开'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      await Clipboard.setData(ClipboardData(text: url.toString()));
                      AppToast.showOn(messenger, '登录链接已复制', icon: Icons.link_rounded, tone: ToastTone.success);
                    },
                    style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                    icon: const Icon(Icons.link_rounded, size: 20),
                    label: const Text('复制链接'),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        TextButton(onPressed: auth.cancelOAuth, child: const Text('取消')),
      ],
    );
  }
}
