import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/flutify_tokens.dart';
import '../../../../services/auth/web_token_service.dart';
import '../../../widgets/toast/app_toast.dart';
import '../../auth/web_login_screen.dart';

/// 设置页「全曲播放（Web 登录）」卡片。
///
/// 全曲播放（Widevine DRM）的真密钥只发给 Web 播放器 token，而 Web token 由
/// sp_dc cookie 铸造；本卡片展示 Web 登录态并引导完成一次内嵌 Web 登录来捕获 sp_dc。
/// 与桌面 OAuth（账号卡片）互补：一个管媒体库 / API，一个管全曲解密密钥。
///
/// 文案与账号卡片一致直接书写中文（未迁入 ARB，见 README 语言与字体一节）。
class WebLoginCard extends StatefulWidget {
  const WebLoginCard({super.key});

  @override
  State<WebLoginCard> createState() => _WebLoginCardState();
}

class _WebLoginCardState extends State<WebLoginCard> {
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      // 统一登录页：Web 登录成功后会顺带无感完成桌面 OAuth（若尚未登录）
      final result = await WebLoginScreen.open(context);
      if (!mounted) return;
      if (result?.webSignedIn ?? false) {
        AppToast.show(
          context,
          'Web 登录成功，全曲播放已就绪',
          icon: Icons.check_circle_rounded,
          tone: ToastTone.success,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final tokens = context.read<WebTokenService>();
    await tokens.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final signedIn = context.read<WebTokenService>().hasSpDc;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: context.tokens.radius(20),
      ),
      child: Row(
        children: [
          // 钥匙图标块：与账号卡片的品牌标位置对应，表意「解密密钥」
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: signedIn
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              borderRadius: context.tokens.radius(14),
            ),
            child: Icon(
              signedIn ? Icons.key_rounded : Icons.key_off_rounded,
              color: signedIn
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '全曲播放（Web 登录）',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  signedIn ? '已就绪，可以播放完整曲目' : '登录一次以解锁完整曲目播放',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (signedIn)
            TextButton(
              onPressed: _busy ? null : _clear,
              child: const Text('清除'),
            ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            onPressed: _busy ? null : _login,
            child: Text(signedIn ? '重新登录' : 'Web 登录'),
          ),
        ],
      ),
    );
  }
}
