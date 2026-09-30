import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../login_method.dart';
import '../widgets/auth_form_parts.dart';
import '../widgets/auth_notice.dart';
import '../widgets/flutify_mark.dart';

/// 阶段：账号密码登录（Login5，备用方式）。底部提供切换到手机号与"更多方式"的入口。
class PasswordStage extends StatefulWidget {
  /// 由外层持有，切换阶段后用户名不丢失。
  final TextEditingController usernameController;
  final ValueChanged<LoginMethod> onSwitchMethod;
  final VoidCallback onMoreMethods;

  const PasswordStage({
    super.key,
    required this.usernameController,
    required this.onSwitchMethod,
    required this.onMoreMethods,
  });

  @override
  State<PasswordStage> createState() => _PasswordStageState();
}

class _PasswordStageState extends State<PasswordStage> {
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<AuthProvider>().signIn(widget.usernameController.text, _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.status == AuthStatus.signingIn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StageHeader(
          leading: FlutifyMark(size: 72),
          title: '账号密码登录',
          subtitle: '直接输入 Spotify 账号密码。若提示错误或需要人机验证，请返回改用浏览器登录',
        ),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: widget.usernameController,
                enabled: !busy,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: const InputDecoration(
                  hintText: '邮箱或用户名',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                enabled: !busy,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    tooltip: _obscure ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ],
          ),
        ),
        AuthErrorBanner(message: auth.error),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: '登录', busyLabel: '正在验证身份…', busy: busy, onPressed: _submit),
        const SizedBox(height: 20),
        const AuthOrDivider(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => widget.onSwitchMethod(LoginMethod.phone),
                icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                label: const Text('手机号'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : widget.onMoreMethods,
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
                label: const Text('更多方式'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const AuthNotice(),
      ],
    );
  }
}