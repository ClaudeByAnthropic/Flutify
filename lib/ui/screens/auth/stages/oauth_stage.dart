import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/md3e_shapes.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/auth/oauth_client_config.dart';
import '../widgets/auth_form_parts.dart';
import '../widgets/oauth_waiting_view.dart';

/// 阶段：开发者应用授权（OAuth 授权码 + PKCE，使用用户自己的 Client ID）。
///
/// 表单：填写开发者 Client ID，提示需登记的回调地址 → 打开浏览器；
/// 等待：浏览器授权完成后自动登录（[OAuthWaitingView]）。
class OAuthStage extends StatefulWidget {
  const OAuthStage({super.key});

  @override
  State<OAuthStage> createState() => _OAuthStageState();
}

class _OAuthStageState extends State<OAuthStage> {
  late final TextEditingController _clientIdController =
      TextEditingController(text: context.read<AuthProvider>().savedOAuthClientId);

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    FocusScope.of(context).unfocus();
    final url = await context.read<AuthProvider>().beginOAuth(_clientIdController.text);
    if (url != null && mounted) await OAuthWaitingView.launch(context, url);
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: auth.status == AuthStatus.authorizing
          ? const OAuthWaitingView(key: ValueKey('waiting'))
          : _buildForm(auth),
    );
  }

  Widget _buildForm(AuthProvider auth) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      key: const ValueKey('form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StageHeader(
          leading: StageHeader.icon(Icons.developer_mode_rounded),
          title: '开发者应用授权',
          subtitle: '使用你在 Spotify 开发者平台创建的应用，通过官方授权页登录',
        ),
        TextField(
          controller: _clientIdController,
          autocorrect: false,
          style: const TextStyle(fontFamily: 'monospace'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
            LengthLimitingTextInputFormatter(32),
          ],
          onSubmitted: (_) => _begin(),
          decoration: const InputDecoration(hintText: 'Client ID', prefixIcon: Icon(Icons.apps_rounded)),
        ),
        const SizedBox(height: 16),
        // 回调地址：需在开发者后台原样登记
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: MD3EShapes.roundedMedium,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Redirect URI（需在开发者后台登记）',
                        style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    const SelectableText(
                      OAuthClientConfig.developerRedirectUri,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: '复制',
                onPressed: () => _copy(OAuthClientConfig.developerRedirectUri, '回调地址已复制'),
              ),
            ],
          ),
        ),
        AuthErrorBanner(message: auth.error),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: '在浏览器中授权', busyLabel: '', busy: false, onPressed: _begin),
        const SizedBox(height: 28),
        const AuthHint(
          icon: Icons.info_outline_rounded,
          text: '前往 developer.spotify.com → Dashboard 创建应用，复制 Client ID，并把上方地址加入 Redirect URIs。'
              '此方式不冒充官方客户端，但只能访问公开 Web API（如彩色歌词不可用）。一般情况下请直接用「在浏览器中登录」。',
        ),
      ],
    );
  }
}
