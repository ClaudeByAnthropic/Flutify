import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../models/artist.dart';
import '../../../models/track.dart';
import '../../../providers/playback_provider.dart';
import '../../../services/spotify_api_service.dart';
import '../../navigation/app_routes.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/player_controls.dart';
import '../shell_layout_controller.dart';

/// 右栏「正在播放」标签：大封面 → 歌名 / 艺人 / 点赞 → 关于艺人 → 接下来播放。
///
/// 艺人详情（头像、粉丝数）按需请求，同一艺人只请求一次（Future 按 id 记忆）。
class NowPlayingDetails extends StatelessWidget {
  final SpotifyTrack track;

  /// 「接下来播放」取自本机队列；展示远程曲目时关闭。
  final bool showNextUp;

  const NowPlayingDetails({super.key, required this.track, this.showNextUp = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // 大封面：正方形，随面板宽度缩放
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: CoverImage(url: track.coverUrl, borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: track.album == null ? null : () => AppRoutes.openAlbum(context, track.album!),
                    child: Text(
                      track.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artistNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            LikeButton(track: track, size: 22, inactiveColor: colorScheme.onSurfaceVariant),
          ],
        ),
        if (track.artists.isNotEmpty) ...[const SizedBox(height: 20), _AboutArtistCard(artist: track.artists.first)],
        if (showNextUp) ...[const SizedBox(height: 16), const _NextUpCard()],
      ],
    );
  }
}

/// 「关于艺人」卡片：艺人头像铺满顶部 + 名字 + 粉丝数，点击进入艺人页。
class _AboutArtistCard extends StatefulWidget {
  final SpotifyArtist artist;

  const _AboutArtistCard({required this.artist});

  @override
  State<_AboutArtistCard> createState() => _AboutArtistCardState();
}

class _AboutArtistCardState extends State<_AboutArtistCard> {
  static final Map<String, Future<SpotifyArtist>> _cache = {};

  late Future<SpotifyArtist> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_AboutArtistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artist.id != widget.artist.id) _future = _load();
  }

  Future<SpotifyArtist> _load() {
    final id = widget.artist.id;
    final api = context.read<SpotifyApiService>();
    // 失败的请求不缓存，下次切到该艺人时重试
    return _cache[id] ??= api.getArtist(id).catchError((Object e) {
      _cache.remove(id);
      return widget.artist;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;

    return FutureBuilder<SpotifyArtist>(
      future: _future,
      initialData: widget.artist,
      builder: (context, snapshot) {
        final artist = snapshot.data ?? widget.artist;
        final followers = artist.followers;
        return Material(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => AppRoutes.openArtist(context, artist),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 10,
                      child: CoverImage(url: artist.avatarUrl, placeholderIcon: Icons.person_rounded),
                    ),
                    // 顶部渐暗，保证白色标题在任何头像上都清晰
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [Colors.black.withAlpha(140), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      top: 12,
                      child: Text(
                        l10n.shellAboutArtist,
                        style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (followers != null && followers > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.shellMonthlyFollowers(Formatters.formatCompactNumber(l10n, followers)),
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 「接下来播放」卡片：队列中的下一首（优先用户队列），附「打开队列」入口。
class _NextUpCard extends StatelessWidget {
  const _NextUpCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final next = context.select<PlaybackProvider, SpotifyTrack?>((p) {
      if (p.userQueue.isNotEmpty) return p.userQueue.first.track;
      if (p.upNext.isNotEmpty) return p.upNext.first.track;
      return null;
    });
    if (next == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.queueNextUp, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () => context.read<ShellLayoutController>().selectTab(NowPlayingTab.queue),
                child: Text(l10n.queueTitle),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              CoverImage(url: next.coverUrl, size: 44, borderRadius: BorderRadius.circular(6)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      next.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      next.artistNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
