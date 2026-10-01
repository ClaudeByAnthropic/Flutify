import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/byte_size.dart';
import '../../../../l10n/l10n.dart';
import '../../../../services/protocol/audio_cache_store.dart';
import '../../../../services/storage_service.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_segmented.dart';

/// 存储：音频缓存占用、缓存上限、一键清除。
///
/// - 占用在进入设置页、改上限、清除后重新统计（目录遍历放在异步里，不卡界面）；
/// - 上限改小后立即按「最久没播放先删」淘汰；正在播放与预取的下一首始终保留；
/// - 没有接入协议链路（[AudioCacheStore] 为 null，例如部分测试）时只显示上限。
class StorageSection extends StatefulWidget {
  const StorageSection({super.key});

  /// 可选上限（MB）：256 MB 约 30 首，5 GB 约 600 首（按 160 kbps、4 分钟一首估算）。
  static const List<int> limitsMb = [256, 512, 1024, 2048, 5120];

  @override
  State<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<StorageSection> {
  AudioCacheStore? _store;
  late int _limitMb;
  int? _usedBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _store = Provider.of<AudioCacheStore?>(context, listen: false);
    final saved = context.read<StorageService>().audioCacheLimitMb;
    // 存储里的值不在可选档位中（旧版本 / 手改）时取最接近的一档
    _limitMb = StorageSection.limitsMb.reduce((a, b) => (a - saved).abs() <= (b - saved).abs() ? a : b);
    _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    final store = _store;
    if (store == null) return;
    final used = await store.sizeBytes();
    if (mounted) setState(() => _usedBytes = used);
  }

  void _setLimit(int mb) {
    setState(() => _limitMb = mb);
    context.read<StorageService>().setAudioCacheLimitMb(mb);
    _store?.maxCacheBytes = mb * ByteSize.mb;
    _refreshUsage();
  }

  Future<void> _confirmClear() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsClearAudioCacheTitle),
        content: Text(l10n.settingsClearAudioCacheMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(l10n.commonClear)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    final freed = await _store!.clear();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(l10n.settingsAudioCacheCleared(ByteSize.format(freed)))));
    _refreshUsage();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final limitBytes = _limitMb * ByteSize.mb;
    final used = _usedBytes;

    return SettingsSection(
      title: l10n.settingsStorageSection,
      children: [
        if (_store != null)
          SettingsTile(
            title: l10n.settingsAudioCache,
            subtitle: used == null
                ? l10n.settingsAudioCacheCalculating
                : l10n.settingsAudioCacheUsage(ByteSize.format(used), ByteSize.format(limitBytes)),
            below: _UsageBar(fraction: used == null ? 0 : (used / limitBytes).clamp(0.0, 1.0)),
          ),
        SettingsTile(
          title: l10n.settingsAudioCacheLimit,
          subtitle: l10n.settingsAudioCacheLimitSubtitle,
          below: SettingsSegmented<int>(
            values: StorageSection.limitsMb,
            labelOf: (mb) => ByteSize.format(mb * ByteSize.mb),
            selected: _limitMb,
            onChanged: _setLimit,
          ),
        ),
        if (_store != null)
          SettingsTile(
            title: l10n.settingsClearAudioCache,
            trailing: _clearing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.delete_sweep_rounded, color: colorScheme.onSurfaceVariant),
            onTap: _clearing || (used ?? 0) == 0 ? null : _confirmClear,
          ),
      ],
    );
  }
}

/// 占用条：细长胶囊，接近上限时转为警示色。
class _UsageBar extends StatelessWidget {
  final double fraction;

  const _UsageBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 6,
        backgroundColor: colorScheme.surfaceContainerHighest,
        color: fraction > 0.9 ? colorScheme.error : colorScheme.primary,
      ),
    );
  }
}
