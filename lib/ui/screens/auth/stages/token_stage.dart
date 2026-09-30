import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../widgets/auth_form_parts.dart';

/// 阶段：登录链接 / 一次性令牌（Login5 OneTimeToken）。
///
/// 可粘贴 Spotify 邮件中的登录链接，或设备联动得到的令牌本身，自动提取 token。
class TokenStage extends StatefulWidget {
  const TokenStage({super.key});

  @override
  State<TokenStage> createState() => _TokenStageState();
}

class _TokenStageState extends State<TokenStage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _controller.text = data!.text!.trim();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<AuthProvider>().signInWithOneTimeToken(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.status == AuthStatus.signingIn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StageHeader(
          leading: StageHeader.icon(Icons.link_rounded),
          title: '使用登录链接',
          subtitle: '粘贴 Spotify 发给你的登录链接，或一次性令牌',
        ),
        TextField(
          controller: _controller,
          enabled: !busy,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://accounts.spotify.com/…?token=…',
            prefixIcon: const Icon(Icons.link_rounded),
            suffixIcon: IconButton(icon: const Icon(Icons.content_paste_rounded), tooltip: '粘贴', onPressed: _paste),
          ),
        ),
        AuthErrorBanner(message: auth.error),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: '登录', busyLabel: '正在验证令牌…', busy: busy, onPressed: _submit),
        const SizedBox(height: 28),
        const AuthHint(
          icon: Icons.info_outline_rounded,
          text: '在 Spotify 官网登录页选择「通过电子邮件发送登录链接」，把邮件中的链接复制到这里。'
              '一次性令牌有效期很短，且只能使用一次。',
        ),
      ],
    );
  }
}
