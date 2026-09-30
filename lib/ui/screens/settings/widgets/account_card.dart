import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/md3e_colors.dart';
import '../../../../core/theme/md3e_shapes.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/storage_service.dart';
import '../../../widgets/cover_image.dart';
import '../../auth/login_screen.dart';
import '../../auth/widgets/flutify_mark.dart';

/// 设置页顶部的 Spotify 账号卡片。
///
/// - 未登录：品牌标 + 说明 + 「登录」；
/// - 已登录：用户名、access_token 有效期、「刷新令牌」与「退出登录」。
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: MD3EShapes.roundedLarge,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: auth.isSignedIn ? _SignedIn(auth: auth) : const _SignedOut(),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const FlutifyMark(size: 48, glow: false),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spotify 账号', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                '登录后使用真实数据，令牌自动续期',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: () => LoginScreen.open(context),
          child: const Text('登录'),
        ),
      ],
    );
  }
}

class _SignedIn extends StatelessWidget {
  final AuthProvider auth;

  const _SignedIn({required this.auth});

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('将清除本机保存的凭据与令牌及本机媒体库缓存，退出后需重新登录才能播放和查看媒体库。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await auth.signOut();
  }

  /// 令牌有效期文案：仍有效显示到期时刻，已过期提示会自动续期。
  String _expiryText() {
    final expiry = auth.accessTokenExpiry;
    if (expiry == null) return '尚未获取令牌';
    if (expiry.isBefore(DateTime.now())) return '令牌已过期，将自动续期';
    final hh = expiry.hour.toString().padLeft(2, '0');
    final mm = expiry.minute.toString().padLeft(2, '0');
    return '令牌有效至 $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = auth.displayName;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final methodLabel = switch (auth.method) {
      AuthMethod.desktop => 'OAuth · 桌面版',
      AuthMethod.oauth => 'OAuth · 开发者应用',
      AuthMethod.login5 => 'Login5 · 官方协议',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            auth.avatarUrl.isNotEmpty
                ? CoverImage(url: auth.avatarUrl, size: 48, circular: true, placeholderIcon: Icons.person_rounded)
                : CircleAvatar(
                    radius: 24,
                    backgroundColor: MD3EColors.spotifyGreen,
                    child: Text(
                      initial,
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 20),
                    ),
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded, size: 16, color: MD3EColors.spotifyGreen),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$methodLabel  ·  ${_expiryText()}',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (auth.error != null) ...[
          const SizedBox(height: 12),
          Text(auth.error!, style: TextStyle(color: colorScheme.error, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: auth.isRefreshing ? null : auth.refreshToken,
                child: auth.isRefreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('刷新令牌'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _confirmSignOut(context),
                style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                child: const Text('退出登录'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
