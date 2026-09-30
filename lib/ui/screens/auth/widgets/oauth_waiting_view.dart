import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../providers/auth_provider.dart';

/// 浏览器授权的等待态：授权页已在浏览器中打开，回调到达后自动完成登录。
///
/// 提供重新打开浏览器、复制授权链接与取消三个出口。桌面版授权与开发者应用授权共用。
class OAuthWaitingView extends StatelessWidget {
  const OAuthWaitingView({super.key});

  /// 用系统浏览器打开授权页；打不开时把链接复制到剪贴板并提示手动粘贴。
  static Future<void> launch(BuildContext context, Uri url) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: url.toString()));
      messenger.showSnackBar(const SnackBar(content: Text('无法自动打开浏览器，授权链接已复制，请手动粘贴到浏览器')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final url = auth.authorizeUrl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 3)),
        ),
        const SizedBox(height: 32),
        Text(
          '等待浏览器授权',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          '在浏览器中完成登录并同意授权后，这里会自动继续',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 36),
        if (url != null) ...[
          FilledButton.tonal(
            onPressed: () => launch(context, url),
            child: const Text('重新打开浏览器'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: url.toString()));
              messenger.showSnackBar(const SnackBar(content: Text('授权链接已复制')));
            },
            child: const Text('复制授权链接'),
          ),
        ],
        const SizedBox(height: 10),
        TextButton(onPressed: auth.cancelOAuth, child: const Text('取消')),
      ],
    );
  }
}
