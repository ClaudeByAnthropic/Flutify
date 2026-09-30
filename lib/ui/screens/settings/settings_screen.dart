import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/spotify_endpoints.dart';
import '../../../core/theme/md3e_shapes.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/settings_provider.dart';
import 'widgets/account_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _tokenController;
  late TextEditingController _baseUrlController;
  late TextEditingController _spClientController;
  late TextEditingController _testPathController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _tokenController = TextEditingController(text: settings.accessToken);
    _baseUrlController = TextEditingController(text: settings.apiBaseUrl);
    _spClientController = TextEditingController(text: settings.spClientToken);
    _testPathController = TextEditingController(text: settings.testEndpoint);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _baseUrlController.dispose();
    _spClientController.dispose();
    _testPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsProvider>();
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

          // Data Mode Toggle
          SwitchListTile(
            title: const Text('Use Mock / Offline Sample Data', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Provides full playback, playlists, artists & lyrics without live token'),
            value: settings.useMockData,
            activeThumbColor: colorScheme.primary,
            onChanged: (val) {
              settings.updateConfig(useMockData: val);
            },
          ),
          const Divider(),

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
          const SizedBox(height: 24),

          // Live API Inspector & Debugger
          Text(
            'Live API Debugger & Tester',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Test reverse-engineered Spotify endpoints directly from the app.',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _testPathController,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint Path',
                    hintText: '/me, /me/player, /browse/new-releases',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: settings.isTestingApi
                    ? null
                    : () {
                        settings.setTestEndpoint(_testPathController.text.trim());
                        settings.executeTestApi();
                      },
                child: settings.isTestingApi
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Send'),
              ),
            ],
          ),

          // Quick Endpoint Suggestions
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              ActionChip(
                label: const Text('/me'),
                onPressed: () {
                  _testPathController.text = SpotifyEndpoints.me;
                },
              ),
              ActionChip(
                label: const Text('/me/player'),
                onPressed: () {
                  _testPathController.text = SpotifyEndpoints.playerState;
                },
              ),
              ActionChip(
                label: const Text('/browse/new-releases'),
                onPressed: () {
                  _testPathController.text = SpotifyEndpoints.newReleases;
                },
              ),
              ActionChip(
                label: const Text('/me/playlists'),
                onPressed: () {
                  _testPathController.text = SpotifyEndpoints.myPlaylists;
                },
              ),
            ],
          ),

          // Test API Result Display
          if (settings.lastApiResponse != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14.0),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: MD3EShapes.roundedMedium,
                border: Border.all(
                  color: (settings.lastApiResponse!['success'] as bool? ?? false)
                      ? Colors.greenAccent.withAlpha(120)
                      : Colors.redAccent.withAlpha(120),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (settings.lastApiResponse!['status'] as int? ?? 0) == 200
                              ? Colors.green
                              : Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'HTTP ${settings.lastApiResponse!['status']}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      Text(
                        'Latency: ${settings.lastApiResponse!['latency_ms']} ms',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    settings.lastApiResponse!['body']?.toString() ??
                        settings.lastApiResponse!['error']?.toString() ??
                        'No response content',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
