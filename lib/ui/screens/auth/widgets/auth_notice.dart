import 'package:flutter/material.dart';

/// 登录页底部说明：登录链路做了什么，以及非官方客户端登录的风控风险。
class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.shield_outlined, size: 16, color: muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '通过 Login5 协议直连 Spotify 官方服务，自动完成设备令牌申请与工作量证明。'
            '密码仅用于本次登录，不会被保存；设备上只保留可续期的加密凭据。\n'
            '以非官方客户端登录可能触发账号风控，建议使用测试账号。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
          ),
        ),
      ],
    );
  }
}
