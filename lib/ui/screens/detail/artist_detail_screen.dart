import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/model_labels.dart';
import '../../../models/album.dart';
import '../../../models/artist.dart';
import '../../../models/playback_context.dart';
import '../../../models/track.dart';
import '../../../providers/library_provider.dart';
import '../../../services/spotify_api_service.dart';
import '../../navigation/app_routes.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/expressive_card.dart';
import '../../widgets/player_controls.dart';
import '../../widgets/track_tile.dart';
import 'widgets/collection_widgets.dart';

/// 艺人主页：热门曲目、关注、作品集（Discography）。
class ArtistDetailScreen extends StatefulWidget {
  final SpotifyArtist artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  static const int _collapsedCount = 5;

  late final Future<List<SpotifyTrack>> _topTracksFuture;
  late final Future<List<SpotifyAlbum>> _albumsFuture;
  late SpotifyArtist _artist = widget.artist;
  bool _showAllTracks = false;

  @override
  void initState() {
    super.initState();
    final api = context.read<SpotifyApiService>();
    _topTracksFuture = api.getArtistTopTracks(widget.artist.id);
    _albumsFuture = api.getArtistAlbums(widget.artist.id);

    // 从曲目跳转过来的 simplified artist 没有头像与粉丝数，补全完整信息
    if (widget.artist.images.isEmpty) {
      api.getArtist(widget.artist.id).then((full) {
        if (mounted && full.id == widget.artist.id) setState(() => _artist = full);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final artist = _artist;
    final isFollowing = context.select<LibraryProvider, bool>((l) => l.isFollowing(artist.id));
    final playbackContext = PlaybackContext.artist(artist.name, uri: artist.contextUri);

    return Scaffold(
      body: FutureBuilder<List<SpotifyTrack>>(
        future: _topTracksFuture,
        builder: (context, snapshot) {
          final topTracks = snapshot.data ?? const <SpotifyTrack>[];
          final loading = snapshot.connectionState != ConnectionState.done;
          final visibleCount = _showAllTracks ? topTracks.length : topTracks.length.clamp(0, _collapsedCount);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300.0,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(artist.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CoverImage(url: artist.avatarUrl, placeholderIcon: Icons.person_rounded),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, colorScheme.surface.withAlpha(220), colorScheme.surface],
                            stops: const [0.4, 0.85, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (artist.followers != null)
                        Text(
                          l10n.followerCount(Formatters.formatCompactNumber(l10n, artist.followers)),
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _FollowButton(
                            following: isFollowing,
                            onPressed: () => context.read<LibraryProvider>().toggleFollowArtist(artist),
                          ),
                          const Spacer(),
                          ShuffleButton(size: 26, inactiveColor: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          ContextPlayButton(tracks: topTracks, playbackContext: playbackContext, size: 54),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(l10n.artistPopular, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),

              if (loading)
                const CollectionPlaceholder(loading: true)
              else if (topTracks.isEmpty)
                CollectionPlaceholder(message: l10n.artistNoPopular)
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => TrackTile(
                      key: ValueKey(topTracks[index].id),
                      track: topTracks[index],
                      index: index + 1,
                      showCover: true,
                      contextQueue: topTracks,
                      playbackContext: playbackContext,
                    ),
                    childCount: visibleCount,
                  ),
                ),

              if (topTracks.length > _collapsedCount)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _showAllTracks = !_showAllTracks),
                        child: Text(_showAllTracks ? l10n.commonShowLess : l10n.commonSeeMore),
                      ),
                    ),
                  ),
                ),

              SliverToBoxAdapter(
                child: FutureBuilder<List<SpotifyAlbum>>(
                  future: _albumsFuture,
                  builder: (context, snap) {
                    final albums = snap.data ?? const <SpotifyAlbum>[];
                    if (albums.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            l10n.artistDiscography,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        SizedBox(
                          height: 220,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            itemCount: albums.length,
                            itemBuilder: (context, i) => ExpressiveCard(
                              title: albums[i].name,
                              subtitle: l10n.subtitleJoin(l10n.albumType(albums[i]), albums[i].releaseYear),
                              imageUrl: albums[i].coverUrl,
                              onTap: () => AppRoutes.openAlbum(context, albums[i]),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool following;
  final VoidCallback onPressed;

  const _FollowButton({required this.following, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: following ? colorScheme.onSurface : colorScheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Text(
          following ? context.l10n.artistFollowing : context.l10n.artistFollow,
          key: ValueKey(following),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
