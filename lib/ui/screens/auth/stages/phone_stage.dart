import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/phone_regions.dart';
import '../../../../providers/auth_provider.dart';
import '../widgets/auth_form_parts.dart';

/// 阶段：手机号登录。提交后服务端下发短信，页面自动切到验证码阶段。
class PhoneStage extends StatefulWidget {
  const PhoneStage({super.key});

  @override
  State<PhoneStage> createState() => _PhoneStageState();
}

class _PhoneStageState extends State<PhoneStage> {
  final _numberController = TextEditingController();
  PhoneRegion _region = PhoneRegions.defaultRegion;

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<AuthProvider>().signInWithPhone(
          number: _numberController.text,
          isoCountryCode: _region.isoCode,
          callingCode: _region.callingCode,
        );
  }

  Future<void> _pickRegion() async {
    final picked = await showModalBottomSheet<PhoneRegion>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          children: [
            for (final r in PhoneRegions.all)
              ListTile(
                leading: Text(r.flag, style: const TextStyle(fontSize: 22)),
                title: Text(r.name),
                trailing: Text('+${r.callingCode}'),
                selected: r == _region,
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _region = picked);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.status == AuthStatus.signingIn;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StageHeader(
          leading: StageHeader.icon(Icons.phone_iphone_rounded),
          title: '手机号登录',
          subtitle: '我们会向该号码发送一条短信验证码',
        ),
        Row(
          children: [
            Material(
              color: colorScheme.surfaceContainerHigh,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: busy ? null : _pickRegion,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      Text(_region.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _numberController,
                enabled: !busy,
                autofocus: true,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                  LengthLimitingTextInputFormatter(18),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(hintText: '手机号码'),
              ),
            ),
          ],
        ),
        AuthErrorBanner(message: auth.error),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: '获取验证码', busyLabel: '正在发送…', busy: busy, onPressed: _submit),
        const SizedBox(height: 28),
        const AuthHint(
          icon: Icons.info_outline_rounded,
          text: '仅支持已在 Spotify 账号中绑定手机号的用户。短信可能有 1 分钟左右的延迟。',
        ),
      ],
    );
  }
}
