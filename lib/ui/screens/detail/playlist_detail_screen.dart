import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../models/playback_context.dart';
import '../../../models/playlist.dart';
import '../../../models/track.dart';
import '../../../providers/library_provider.dart';
import '../../../services/spotify_api_service.dart';
import '../../widgets/track_tile.dart';
import 'widgets/collection_widgets.dart';

/// 歌单详情页（含 Liked Songs 与自建歌单）。
///
/// - 媒体库中的歌单通过 select 实时反映增删歌曲。
/// - 从 Browse API 拿到的歌单通常不含曲目，打开时再请求 /playlists/{id}。
class PlaylistDetailScreen extends StatefulWidget {
  final SpotifyPlaylist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  SpotifyPlaylist? _fetched;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.playlist;
    final isLibraryOwned = p.id == LibraryProvider.likedSongsId || context.read<LibraryProvider>().isOwnPlaylist(p.id);
    if (!isLibraryOwned && p.tracks.isEmpty && p.totalTracks > 0) {
      _loading = true;
      context.read<SpotifyApiService>().getPlaylist(p.id).then((full) {
        if (!mounted) return;
        setState(() {
          _fetched = full;
          _loading = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final library = context.read<LibraryProvider>();

    final libraryVersion = context.select<LibraryProvider, SpotifyPlaylist?>((l) => l.findPlaylist(widget.playlist.id));
    final isSaved = context.select<LibraryProvider, bool>((l) => l.isPlaylistSaved(widget.playlist.id));

    final playlist = _fetched ?? libraryVersion ?? widget.playlist;
    final tracks = playlist.tracks;
    final isLikedSongs = playlist.id == LibraryProvider.likedSongsId;
    final isOwn = library.isOwnPlaylist(playlist.id);
    final l10n = context.l10n;
    // 「已点赞的歌曲」由 LibraryProvider 生成，名称与简介按界面语言展示
    final title = isLikedSongs ? l10n.likedSongs : playlist.name;
    final description = isLikedSongs ? l10n.likedSongsDescription : playlist.description;
    final playbackContext = isLikedSongs
        ? PlaybackContext.collection(title, uri: LibraryProvider.likedSongsUri)
        : PlaybackContext.playlist(playlist.name, uri: playlist.contextUri);
    final totalMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    // 「12 首歌曲，45 分 12 秒」；时长未知时只显示歌曲数
    final songs = l10n.songCount(tracks.length);
    final summary = totalMs > 0 ? l10n.countAndDuration(songs, Formatters.formatLongDuration(l10n, totalMs)) : songs;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CollectionAppBar(
            title: title,
            coverUrl: playlist.coverUrl,
            coverOverride: isLikedSongs ? const _LikedSongsCover() : null,
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (description.isNotEmpty) ...[
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 12,
                        backgroundColor: Color(0xFF1ED760),
                        child: Icon(Icons.music_note_rounded, color: Colors.black, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          playlist.ownerName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '· $summary',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CollectionActionRow(
                    tracks: tracks,
                    playbackContext: playbackContext,
                    leading: [
                      if (!isLikedSongs && !isOwn)
                        SaveToggleButton(saved: isSaved, onPressed: () => library.togglePlaylistSaved(playlist)),
                      if (isOwn)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 28),
                          onSelected: (value) {
                            if (value == 'delete') {
                              library.deletePlaylist(playlist.id);
                              Navigator.pop(context);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'delete', child: Text(l10n.playlistDelete)),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (_loading)
            const CollectionPlaceholder(loading: true)
          else if (tracks.isEmpty)
            CollectionPlaceholder(
              message: isLikedSongs
                  ? l10n.playlistLikedEmpty
                  : isOwn
                      ? l10n.playlistOwnEmpty
                      : l10n.playlistEmpty,
              icon: isLikedSongs ? Icons.favorite_border_rounded : Icons.queue_music_rounded,
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildTile(tracks, index, playbackContext, isOwn ? playlist.id : null),
                childCount: tracks.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _buildTile(List<SpotifyTrack> tracks, int index, PlaybackContext ctx, String? ownPlaylistId) {
    final track = tracks[index];
    final tile = TrackTile(
      key: ValueKey(track.id),
      track: track,
      index: index + 1,
      showCover: true,
      contextQueue: tracks,
      playbackContext: ctx,
    );
    if (ownPlaylistId == null) return tile;

    // 自建歌单支持左滑移除曲目
    return Dismissible(
      key: ValueKey('own_${track.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.redAccent,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => context.read<LibraryProvider>().removeTrackFromPlaylist(ownPlaylistId, track.id),
      child: tile,
    );
  }
}

/// Liked Songs 的渐变爱心封面（不依赖网络图片）。
class _LikedSongsCover extends StatelessWidget {
  const _LikedSongsCover();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF450AF5), Color(0xFF8E8EE5), Color(0xFFC4EFD9)],
        ),
      ),
      child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 72),
    );
  }
}
