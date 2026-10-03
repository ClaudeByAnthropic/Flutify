import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../providers/preferences_provider.dart';
import '../../../../services/network/spotify_gateway.dart';
import 'settings_section.dart';

class GatewaySettings extends StatelessWidget {
  final VoidCallback onChanged;
  const GatewaySettings({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final gateway = context.select<PreferencesProvider, SpotifyGateway>(
      (p) => p.prefs.gateway,
    );
    final l10n = context.l10n;
    return SettingsTile(
      title: l10n.settingsGateway,
      subtitle: gateway.enabled
          ? gateway.baseUrl
          : l10n.settingsGatewayDescription,
      trailing: Switch(
        value: gateway.enabled,
        onChanged: (enabled) async {
          if (enabled && !gateway.isValid) {
            await _edit(context, gateway.copyWith(enabled: true));
          } else {
            _save(context, gateway.copyWith(enabled: enabled));
          }
        },
      ),
      onTap: () => _edit(context, gateway),
    );
  }

  void _save(BuildContext context, SpotifyGateway gateway) {
    final provider = context.read<PreferencesProvider>();
    provider.update(provider.prefs.copyWith(gateway: gateway));
    onChanged();
  }

  Future<void> _edit(BuildContext context, SpotifyGateway gateway) async {
    final result = await showDialog<SpotifyGateway>(
      context: context,
      builder: (_) => _GatewayDialog(gateway: gateway),
    );
    if (result != null && context.mounted) _save(context, result);
  }
}

class _GatewayDialog extends StatefulWidget {
  final SpotifyGateway gateway;
  const _GatewayDialog({required this.gateway});
  @override
  State<_GatewayDialog> createState() => _GatewayDialogState();
}

class _GatewayDialogState extends State<_GatewayDialog> {
  late final _url = TextEditingController(text: widget.gateway.baseUrl);
  late final _user = TextEditingController(text: widget.gateway.username);
  late final _pass = TextEditingController(text: widget.gateway.password);
  bool _invalid = false;
  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.settingsGateway),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.settingsGatewayDescription),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('gateway-url'),
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.settingsGatewayUrl,
                  hintText: 'https://host/path',
                ),
              ),
              TextField(
                key: const ValueKey('gateway-user'),
                controller: _user,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.settingsGatewayUser,
                ),
              ),
              TextField(
                key: const ValueKey('gateway-password'),
                controller: _pass,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.settingsGatewayPassword,
                ),
              ),
              if (_invalid)
                Text(
                  l10n.settingsGatewayInvalid,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final next = widget.gateway.copyWith(
              baseUrl: _url.text.trim(),
              username: _user.text.trim(),
              password: _pass.text,
            );
            if (!next.isValid) {
              setState(() => _invalid = true);
              return;
            }
            Navigator.pop(context, next);
          },
          child: Text(l10n.settingsApply),
        ),
      ],
    );
  }
}
