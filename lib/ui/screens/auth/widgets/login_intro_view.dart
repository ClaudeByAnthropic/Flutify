import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import 'auth_error_banner.dart';
import 'login_hero.dart';
import 'oauth_waiting_view.dart';

/// 登录页的初始态：主视觉 + 标题 + 三条安心说明 + 「在浏览器中登录」主按钮。
///
/// 唯一的桌面登录方式：系统浏览器打开 accounts.spotify.com 官方登录页（Google 等
/// 第三方登录在浏览器里完成，凭据不经过应用内 WebView），登录完成后经本机回环回到 App。
/// 登录成功后会接着引导一次应用内 Web 登录（sp_dc，全曲播放用），见 LoginScreen。
class LoginIntroView extends StatelessWidget {
  const LoginIntroView({super.key});

  Future<void> _begin(BuildContext context) async {
    final url = await context.read<AuthProvider>().beginOAuth();
    if (url != null && context.mounted) await OAuthWaitingView.launch(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final error = context.select<AuthProvider, String?>((a) => a.error);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: LoginHero()),
        const SizedBox(height: 36),
        Text(
          '登录 Spotify',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.1),
        ),
        const SizedBox(height: 12),
        Text(
          '在浏览器中打开 Spotify 官方登录页，\n登录完成后自动回到 Flutify',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 28),
        const _ReassuranceCard(),
        const SizedBox(height: 28),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            onPressed: () => _begin(context),
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.open_in_browser_rounded, size: 22),
            label: const Text('在浏览器中登录'),
          ),
        ),
        AuthErrorBanner(message: error),
        const SizedBox(height: 20),
        Text(
          '以官方客户端身份登录不符合 Spotify 服务条款，建议使用小号。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withAlpha(170)),
        ),
      ],
    );
  }
}

/// 三条安心说明，放在一张大圆角浅色调卡片里（MD3E 的容器层级）。
class _ReassuranceCard extends StatelessWidget {
  const _ReassuranceCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          children: [
            _Point(icon: Icons.verified_user_rounded, text: 'Flutify 不接触你的密码'),
            _Point(icon: Icons.key_rounded, text: '支持 Passkey、两步验证与第三方账号登录'),
            _Point(icon: Icons.devices_rounded, text: '登录后可遥控你的其他 Spotify 设备'),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Point({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 18, color: colorScheme.onSecondaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
