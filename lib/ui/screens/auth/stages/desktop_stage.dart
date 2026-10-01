import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../login_method.dart';
import '../widgets/auth_form_parts.dart';
import '../widgets/flutify_mark.dart';
import '../widgets/oauth_waiting_view.dart';

/// 阶段：在浏览器中登录（默认，桌面版 OAuth）。
///
/// 与官方桌面版相同：打开 accounts.spotify.com 官方登录页，登录完成后经本机回环回到 App。
/// 无需填写任何内容；下方保留账号密码与"更多方式"作为备用入口。
class DesktopStage extends StatelessWidget {
  final ValueChanged<LoginMethod> onSwitchMethod;
  final VoidCallback onMoreMethods;

  const DesktopStage({super.key, required this.onSwitchMethod, required this.onMoreMethods});

  Future<void> _begin(BuildContext context) async {
    final url = await context.read<AuthProvider>().beginDesktopOAuth();
    if (url != null && context.mounted) await OAuthWaitingView.launch(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final authorizing = context.select<AuthProvider, bool>((a) => a.status == AuthStatus.authorizing);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: authorizing ? const OAuthWaitingView(key: ValueKey('waiting')) : _buildIntro(context),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Column(
      key: const ValueKey('intro'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StageHeader(
          leading: FlutifyMark(size: 72),
          title: '登录 Spotify',
          subtitle: '在浏览器中打开 Spotify 官方登录页，登录完成后自动回到 Flutify',
        ),
        AuthPrimaryButton(
          label: '在浏览器中登录',
          busyLabel: '',
          busy: false,
          onPressed: () => _begin(context),
        ),
        AuthErrorBanner(message: auth.error),
        const SizedBox(height: 20),
        const AuthOrDivider(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onSwitchMethod(LoginMethod.password),
                icon: const Icon(Icons.password_rounded, size: 18),
                label: const Text('账号密码'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onMoreMethods,
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
                label: const Text('更多方式'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
