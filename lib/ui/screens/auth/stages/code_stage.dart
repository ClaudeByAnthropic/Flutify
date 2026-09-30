import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../widgets/auth_form_parts.dart';
import '../widgets/code_input_field.dart';

/// 阶段：短信验证码（密码 / 手机号登录触发 CodeChallenge 后出现）。
///
/// 输满自动提交；验证码错误时清空重输；冷却 60 秒后可重新发送。
class CodeStage extends StatefulWidget {
  final VoidCallback onUseAnotherAccount;

  const CodeStage({super.key, required this.onUseAnotherAccount});

  @override
  State<CodeStage> createState() => _CodeStageState();
}

class _CodeStageState extends State<CodeStage> {
  final _controller = TextEditingController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 每秒刷新一次，驱动"重新发送"倒计时
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit([String? code]) async {
    final auth = context.read<AuthProvider>();
    await auth.submitCode(code ?? _controller.text);
    if (mounted && auth.error != null) _controller.clear();
  }

  Future<void> _resend() async {
    _controller.clear();
    await context.read<AuthProvider>().resendCode();
  }

  /// 距可重新发送的剩余秒数；0 表示可以发送。
  int _secondsLeft(AuthProvider auth) {
    final sentAt = auth.codeSentAt;
    if (sentAt == null) return 0;
    final left = AuthProvider.resendCooldown - DateTime.now().difference(sentAt);
    return left.isNegative ? 0 : left.inSeconds + 1;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final challenge = auth.challenge;
    final busy = auth.status == AuthStatus.verifyingCode;
    final length = (challenge?.codeLength ?? 6).clamp(4, 8);
    final phone = challenge?.canonicalPhoneNumber ?? '';
    final secondsLeft = _secondsLeft(auth);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StageHeader(
          leading: StageHeader.icon(Icons.sms_outlined),
          title: '输入验证码',
          subtitle: phone.isEmpty ? '$length 位验证码已发送至你绑定的手机' : '$length 位验证码已发送至 $phone',
        ),
        CodeInputField(
          length: length,
          controller: _controller,
          enabled: !busy,
          hasError: auth.error != null,
          onCompleted: _submit,
        ),
        AuthErrorBanner(message: auth.error),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: '验证', busyLabel: '请稍候…', busy: busy, onPressed: () => _submit()),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: busy || !auth.canResendCode ? null : _resend,
              child: Text(secondsLeft > 0 ? '重新发送（${secondsLeft}s）' : '重新发送'),
            ),
            Text('·', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            TextButton(
              onPressed: busy ? null : widget.onUseAnotherAccount,
              child: const Text('换个方式登录'),
            ),
          ],
        ),
      ],
    );
  }
}
