import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/playback_provider.dart';
import '../navigation/app_routes.dart';
import '../shell/shell_breakpoints.dart';
import 'cover_image.dart';
import 'create_playlist_dialog.dart';
import 'track_options_sheet.dart';

/// 曲目操作统一入口。
///
/// - 桌面端：在鼠标位置（右键）或按钮下方（⋯）弹出菜单，与 Spotify 桌面端一致；
///   「添加到歌单」「前往艺人（多位）」在同一位置弹出二级菜单；
/// - 移动端：底部操作面板 [TrackOptionsSheet]。
class TrackMenu {
  TrackMenu._();

  /// [position] 为全局坐标；为空时按 [context] 对应组件的左下角弹出（用于按钮触发）。
  static Future<void> show(BuildContext context, SpotifyTrack track, {Offset? position}) {
    if (!ShellBreakpoints.isDesktop(MediaQuery.sizeOf(context).width)) {
      return TrackOptionsSheet.show(context, track);
    }
    return _showDesktop(context, track, position ?? _anchorOf(context));
  }

  static Offset _anchorOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(box.size.bottomLeft(Offset.zero));
  }

  static Future<T?> _menu<T>(BuildContext context, Offset position, List<PopupMenuEntry<T>> items) {
    final overlay = Overlay.of(context, rootOverlay: true).context.findRenderObject()! as RenderBox;
    final colorScheme = Theme.of(context).colorScheme;
    return showMenu<T>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      color: colorScheme.surfaceContainerHigh,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: items,
    );
  }

  static PopupMenuItem<T> _item<T>(T value, IconData icon, String label, {Color? iconColor}) {
    return PopupMenuItem<T>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  static void _toast(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, width: 360),
    );
  }

  static Future<void> _showDesktop(BuildContext context, SpotifyTrack track, Offset position) async {
    final l10n = context.l10n;
    final library = context.read<LibraryProvider>();
    final playback = context.read<PlaybackProvider>();
    final liked = library.isLiked(track.id);
    final album = track.album;

    final action = await _menu<_Action>(context, position, [
      _item(_Action.addToPlaylist, Icons.playlist_add_rounded, l10n.trackAddToPlaylist),
      _item(
        _Action.like,
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        liked ? l10n.likeRemove : l10n.likeAdd,
        iconColor: liked ? Theme.of(context).colorScheme.primary : null,
      ),
      _item(_Action.queue, Icons.queue_music_rounded, l10n.trackAddToQueue),
      const PopupMenuDivider(height: 8),
      if (track.artists.isNotEmpty)
        _item(_Action.artist, Icons.person_rounded, l10n.trackGoToArtist(track.artists.length)),
      if (album != null && album.id.isNotEmpty) _item(_Action.album, Icons.album_rounded, l10n.trackGoToAlbum),
      const PopupMenuDivider(height: 8),
      _item(_Action.share, Icons.link_rounded, l10n.commonShare),
    ]);
    if (action == null || !context.mounted) return;

    switch (action) {
      case _Action.like:
        library.toggleLike(track);
        _toast(context, liked ? l10n.toastLikeRemoved : l10n.toastLikeAdded);
      case _Action.queue:
        playback.addToQueue(track);
        _toast(context, l10n.toastAddedToQueue);
      case _Action.album:
        AppRoutes.openAlbum(context, album!);
      case _Action.artist:
        await _goToArtist(context, track, position);
      case _Action.addToPlaylist:
        await _addToPlaylist(context, track, position);
      case _Action.share:
        await Clipboard.setData(ClipboardData(text: 'https://open.spotify.com/track/${track.id}'));
        if (context.mounted) _toast(context, l10n.toastLinkCopied);
    }
  }

  static Future<void> _goToArtist(BuildContext context, SpotifyTrack track, Offset position) async {
    if (track.artists.length == 1) {
      AppRoutes.openArtist(context, track.artists.first);
      return;
    }
    final picked = await _menu<int>(context, position, [
      for (var i = 0; i < track.artists.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 44,
          child: Row(
            children: [
              CoverImage(
                url: track.artists[i].avatarUrl,
                size: 28,
                circular: true,
                placeholderIcon: Icons.person_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(track.artists[i].name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
    ]);
    if (picked != null && context.mounted) AppRoutes.openArtist(context, track.artists[picked]);
  }

  /// 二级菜单：「新建歌单」+ 自建歌单（已包含该曲目的打勾）。
  static Future<void> _addToPlaylist(BuildContext context, SpotifyTrack track, Offset position) async {
    final l10n = context.l10n;
    final library = context.read<LibraryProvider>();
    final primary = Theme.of(context).colorScheme.primary;
    const createId = '\u0000new';

    final id = await _menu<String>(context, position, [
      _item(createId, Icons.add_rounded, l10n.trackNewPlaylist),
      if (library.ownPlaylists.isNotEmpty) const PopupMenuDivider(height: 8),
      for (final playlist in library.ownPlaylists)
        _item(
          playlist.id,
          playlist.tracks.any((t) => t.id == track.id) ? Icons.check_circle_rounded : Icons.queue_music_rounded,
          playlist.name,
          iconColor: playlist.tracks.any((t) => t.id == track.id) ? primary : null,
        ),
    ]);
    if (id == null || !context.mounted) return;

    if (id == createId) {
      final name = await CreatePlaylistDialog.show(context);
      if (name == null || !context.mounted) return;
      final created = library.createPlaylist(name);
      library.addTrackToPlaylist(created.id, track);
      _toast(context, l10n.toastAddedTo(created.name));
      return;
    }
    final playlist = library.findPlaylist(id);
    if (playlist == null) return;
    final added = library.addTrackToPlaylist(id, track);
    _toast(context, added ? l10n.toastAddedTo(playlist.name) : l10n.toastAlreadyIn(playlist.name));
  }
}

enum _Action { like, addToPlaylist, queue, album, artist, share }
