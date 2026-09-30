import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/md3e_shapes.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/spotify_provider.dart';

class DevicePickerSheet extends StatelessWidget {
  const DevicePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: false,
      builder: (_) => const DevicePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spotify = context.watch<SpotifyProvider>();

    // 背景必须是 Material 而不是带颜色的 DecoratedBox，否则 ListTile 的水波纹会被遮住
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: MD3EShapes.topSheet),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Icon(Icons.devices_rounded, color: colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.deviceConnectTitle,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.deviceConnectDescription,
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              ...spotify.devices.map((device) {
                final isCurrent = spotify.activeDevice?.id == device.id;
                IconData iconData = Icons.speaker_rounded;
                if (device.type == 'Computer') iconData = Icons.computer_rounded;
                if (device.type == 'Smartphone') iconData = Icons.phone_android_rounded;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isCurrent ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      iconData,
                      color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                  title: Text(
                    device.name,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    isCurrent ? context.l10n.deviceCurrent : context.l10n.deviceSpotifyConnect,
                    style: TextStyle(
                      color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  trailing: isCurrent ? Icon(Icons.volume_up_rounded, color: colorScheme.primary) : null,
                  onTap: () {
                    spotify.setActiveDevice(device);
                    Navigator.pop(context);
                  },
                );
              }),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
