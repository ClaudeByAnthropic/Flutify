import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../models/playback_context.dart';
import '../../../models/playlist.dart';
import '../../../models/track.dart';
import '../../../providers/library_provider.dart';
import '../../../services/spotify_api_service.dart';
import '../../widgets/content_bottom_spacer.dart';
import '../../widgets/track_tile.dart';
import 'widgets/collection_hero.dart';
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
  Object? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.playlist;
    final isLibraryOwned = p.id == LibraryProvider.likedSongsId || context.read<LibraryProvider>().isOwnPlaylist(p.id);
    if (!isLibraryOwned && p.tracks.isEmpty && p.totalTracks > 0) _fetch();
  }

  /// 拉取完整歌单；失败时记录错误，由占位提供登录 / 重试。
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final full = await context.read<SpotifyApiService>().getPlaylist(widget.playlist.id);
      if (mounted) setState(() => _fetched = full);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: CollectionTintScope(
        imageUrl: isLikedSongs ? '' : playlist.coverUrl,
        fallback: isLikedSongs ? const Color(0xFF4A2FB8) : const Color(0xFF3A3A48),
        child: CustomScrollView(
        slivers: [
          CollectionHero(
            typeLabel: l10n.typePlaylist,
            title: title,
            imageUrl: playlist.coverUrl,
            coverOverride: isLikedSongs ? const _LikedSongsCover() : null,
            meta: _PlaylistMeta(description: description, ownerName: playlist.ownerName, summary: summary),
            collapsedAction: ContextPlayButton(
              tracks: tracks,
              playbackContext: playbackContext,
              size: 44,
              elevated: false,
            ),
          ),

          SliverToBoxAdapter(
            child: CollectionHeroFade(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: CollectionActionRow(
                  tracks: tracks,
                  playbackContext: playbackContext,
                  leading: [
                    if (!isLikedSongs && !isOwn)
                      SaveToggleButton(saved: isSaved, onPressed: () => library.togglePlaylistSaved(playlist)),
                    if (isOwn)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz_rounded, size: 28),
                        tooltip: l10n.commonMoreOptions,
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
              ),
            ),
          ),

          if (_loading)
            const CollectionPlaceholder(loading: true)
          else if (_error != null)
            CollectionErrorPlaceholder(
              signedOut: identical(_error, SpotifyDataException.notSignedIn),
              onRetry: _fetch,
            )
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

          const ContentBottomSpacer(),
        ],
        ),
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

/// 头部元信息：简介（一行）+ 作者 · 歌曲数与总时长。
class _PlaylistMeta extends StatelessWidget {
  final String description;
  final String ownerName;
  final String summary;

  const _PlaylistMeta({required this.description, required this.ownerName, required this.summary});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description.isNotEmpty) ...[
          Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: context.tokens.accent,
              child: Icon(Icons.music_note_rounded, color: context.tokens.onAccent, size: 14),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                ownerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: Text(
                ' · $summary',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
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
