import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/md3e_shapes.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/settings_provider.dart';
import 'widgets/account_card.dart';

/// 设置页：账号卡片 + 手动凭据（令牌 / 自定义 API 基址 / SpClient 令牌）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _tokenController;
  late TextEditingController _baseUrlController;
  late TextEditingController _spClientController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _tokenController = TextEditingController(text: settings.accessToken);
    _baseUrlController = TextEditingController(text: settings.apiBaseUrl);
    _spClientController = TextEditingController(text: settings.spClientToken);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _baseUrlController.dispose();
    _spClientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.read<SettingsProvider>();
    // 已登录时 access_token 由 Login5 自动管理，手动输入框只读，保存时不覆盖
    final signedIn = context.select<AuthProvider, bool>((a) => a.isSignedIn);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commonSettings),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: l10n.settingsSave,
            onPressed: () {
              settings.updateConfig(
                accessToken: signedIn ? null : _tokenController.text.trim(),
                apiBaseUrl: _baseUrlController.text.trim(),
                spClientToken: _spClientController.text.trim(),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.settingsSaved)),
              );
            },
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          const AccountCard(),
          const SizedBox(height: 16),

          // Banner Info
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: MD3EShapes.roundedLarge,
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.biotech_rounded, color: colorScheme.primary, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsBannerTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.settingsBannerMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // API Configuration
          Text(
            l10n.settingsCredentialsSection,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),

          // Base URL
          TextField(
            controller: _baseUrlController,
            decoration: InputDecoration(
              labelText: l10n.settingsBaseUrlLabel,
              hintText: l10n.settingsBaseUrlHint,
              prefixIcon: const Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 12),

          // Access Token
          TextField(
            controller: _tokenController,
            obscureText: true,
            enabled: !signedIn,
            decoration: InputDecoration(
              labelText: l10n.settingsTokenLabel,
              hintText: l10n.settingsTokenHint,
              helperText: signedIn ? l10n.settingsTokenManaged : null,
              prefixIcon: const Icon(Icons.vpn_key_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste_rounded),
                tooltip: l10n.settingsPasteToken,
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    _tokenController.text = data!.text!;
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // SpClient Token (Internal)
          TextField(
            controller: _spClientController,
            decoration: InputDecoration(
              labelText: l10n.settingsSpClientLabel,
              hintText: l10n.settingsSpClientHint,
              prefixIcon: const Icon(Icons.cookie_rounded),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
