import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/md3e_shapes.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../models/album.dart';
import '../../../models/artist.dart';
import '../../../models/playback_context.dart';
import '../../../models/playlist.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/playback_provider.dart';
import '../../../providers/spotify_provider.dart';
import '../../../services/spotify_api_service.dart';
import '../../navigation/app_routes.dart';
import '../auth/login_screen.dart';
import '../../widgets/content_bottom_spacer.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/expressive_card.dart';
import '../../widgets/filter_pill.dart';
import '../../widgets/shelf_section.dart';
import '../../widgets/skeleton.dart';

/// 主页。
///
/// 只订阅用户头像、主页歌单与媒体库歌单列表；播放状态一律通过 read 调用，
/// 播放过程中主页不会重建。
class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;

  const HomeScreen({super.key, required this.onOpenSettings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 过滤药丸：0 全部 / 1 音乐 / 2 播客。
  int _selectedFilter = 0;

  /// 卡片上的播放键：取不到曲目（未登录 / 网络失败时数据层返回空列表）就打开专辑页，由详情页说明原因。
  Future<void> _playAlbum(SpotifyAlbum album) async {
    final playback = context.read<PlaybackProvider>();
    final tracks = await context.read<SpotifyApiService>().getAlbumTracks(album);
    if (!mounted) return;
    if (tracks.isEmpty) {
      AppRoutes.openAlbum(context, album);
      return;
    }
    await playback.playContext(tracks, PlaybackContext.album(album.name, uri: album.contextUri));
  }

  void _playPlaylist(SpotifyPlaylist playlist) {
    context.read<PlaybackProvider>().playContext(
          playlist.tracks,
          PlaybackContext.playlist(playlist.name, uri: playlist.contextUri),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final filters = [l10n.filterAll, l10n.filterMusic, l10n.filterPodcasts];
    final avatarUrl = context.select<SpotifyProvider, String>((s) => s.user.avatarUrl);
    final featured = context.select<SpotifyProvider, List<SpotifyPlaylist>>((s) => s.featuredPlaylists);
    final libraryPlaylists = context.select<LibraryProvider, List<SpotifyPlaylist>>((l) => l.playlists);
    final libraryAlbums = context.select<LibraryProvider, List<SpotifyAlbum>>((l) => l.albums);
    final libraryArtists = context.select<LibraryProvider, List<SpotifyArtist>>((l) => l.artists);
    final isLoading = context.select<SpotifyProvider, bool>((s) => s.isLoadingHome);
    final showMusic = _selectedFilter != 2;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 顶栏：头像 / 问候语 / 设置
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onOpenSettings,
                      child: CoverImage(url: avatarUrl, size: 38, circular: true, placeholderIcon: Icons.person_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        Formatters.getGreeting(l10n),
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded),
                      tooltip: l10n.commonSettings,
                      onPressed: widget.onOpenSettings,
                    ),
                  ],
                ),
              ),
            ),

            // 过滤药丸
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  itemCount: filters.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterPill(
                      label: filters[index],
                      isSelected: _selectedFilter == index,
                      onTap: () => setState(() => _selectedFilter = index),
                    ),
                  ),
                ),
              ),
            ),

            if (!showMusic)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyPodcasts(),
              )
            else ...[
              // 快捷入口：Liked Songs + 媒体库歌单
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                sliver: _QuickAccessGrid(playlists: libraryPlaylists.take(7).toList()),
              ),

              if (featured.isEmpty)
                SliverToBoxAdapter(
                  child: isLoading
                      ? const SkeletonShelf()
                      : !context.read<SpotifyApiService>().isConfigured
                      ? EmptyState(
                          icon: Icons.lock_outline_rounded,
                          title: l10n.detailSignInRequired,
                          actionLabel: l10n.shellSignIn,
                          compact: true,
                          onAction: () => LoginScreen.open(context),
                        )
                      : EmptyState(
                          icon: Icons.wifi_off_rounded,
                          title: l10n.homeLoadFailedTitle,
                          message: l10n.homeLoadFailedMessage,
                          actionLabel: l10n.commonRetry,
                          compact: true,
                          onAction: () => context.read<SpotifyProvider>().loadInitialData(),
                        ),
                )
              else
                SliverToBoxAdapter(
                  child: ShelfSection(
                    title: l10n.homeMadeForYou,
                    subtitle: l10n.homeMadeForYouSubtitle,
                    children: [
                      for (final playlist in featured.where((p) => p.id != LibraryProvider.likedSongsId))
                        ExpressiveCard(
                          title: playlist.name,
                          subtitle: playlist.description,
                          imageUrl: playlist.coverUrl,
                          onTap: () => AppRoutes.openPlaylist(context, playlist),
                          onPlayTap: playlist.tracks.isEmpty ? null : () => _playPlaylist(playlist),
                        ),
                    ],
                  ),
                ),

              // 示例数据已移除：这两个货架暂以用户媒体库中的专辑 / 艺人填充（为空时不显示）
              if (libraryAlbums.isNotEmpty)
                SliverToBoxAdapter(
                  child: ShelfSection(
                    title: l10n.homePopularReleases,
                    subtitle: l10n.homePopularReleasesSubtitle,
                    children: [
                      for (final album in libraryAlbums)
                        ExpressiveCard(
                          title: album.name,
                          subtitle: album.artistNames,
                          imageUrl: album.coverUrl,
                          onTap: () => AppRoutes.openAlbum(context, album),
                          onPlayTap: () => _playAlbum(album),
                        ),
                    ],
                  ),
                ),

              if (libraryArtists.isNotEmpty)
                SliverToBoxAdapter(
                  child: ShelfSection(
                    title: l10n.homePopularArtists,
                    children: [
                      for (final artist in libraryArtists)
                        ExpressiveCard(
                          title: artist.name,
                          subtitle: l10n.typeArtist,
                          imageUrl: artist.avatarUrl,
                          isCircular: true,
                          onTap: () => AppRoutes.openArtist(context, artist),
                        ),
                    ],
                  ),
                ),

              const ContentBottomSpacer(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Spotify 经典快捷入口网格（固定 56dp 高）。
class _QuickAccessGrid extends StatelessWidget {
  final List<SpotifyPlaylist> playlists;

  const _QuickAccessGrid({required this.playlists});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final likedCount = context.select<LibraryProvider, int>((l) => l.likedTracks.length);

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width >= 1100 ? 4 : (width >= 680 ? 3 : 2);
        const itemHeight = 56.0;
        final itemWidth = (width - (columns - 1) * 10) / columns;
        final ratio = (itemWidth / itemHeight).clamp(1.2, 12.0);

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: ratio,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final isLiked = index == 0;
              final playlist = isLiked ? null : playlists[index - 1];
              return Material(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: MD3EShapes.roundedSmall,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => AppRoutes.openPlaylist(
                    context,
                    playlist ?? context.read<LibraryProvider>().likedSongsPlaylist,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: itemHeight,
                        height: itemHeight,
                        child: isLiked
                            ? const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)]),
                                ),
                                child: Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
                              )
                            : CoverImage(url: playlist!.coverUrl, size: itemHeight),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLiked ? context.l10n.likedSongs : playlist!.name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                maxLines: isLiked ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (isLiked)
                                Text(
                                  context.l10n.songCount(likedCount),
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: playlists.length + 1,
          ),
        );
      },
    );
  }
}

class _EmptyPodcasts extends StatelessWidget {
  const _EmptyPodcasts();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 120),
      child: Center(
        child: EmptyState(
          icon: Icons.podcasts_rounded,
          title: context.l10n.homeNoPodcastsTitle,
          message: context.l10n.homeNoPodcastsMessage,
        ),
      ),
    );
  }
}
