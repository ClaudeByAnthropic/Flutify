import 'package:flutter/material.dart';

import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/playlist.dart';
import '../screens/detail/album_detail_screen.dart';
import '../screens/detail/artist_detail_screen.dart';
import '../screens/detail/playlist_detail_screen.dart';

/// 详情页导航入口。
///
/// - 详情页压入「当前 Tab 的嵌套 Navigator」（由 MainShell 注册），播放器常驻可见。
/// - 从全屏播放器、底部面板等根级弹层中跳转时，先关闭所有弹层（PopupRoute），
///   与 Spotify 的「Go to album / Go to artist」行为一致。
class AppRoutes {
  AppRoutes._();

  /// MainShell 注册：返回当前 Tab 的 NavigatorState。
  static NavigatorState? Function()? contentNavigator;

  static void openPlaylist(BuildContext context, SpotifyPlaylist playlist) =>
      _push(context, PlaylistDetailScreen(playlist: playlist));

  static void openAlbum(BuildContext context, SpotifyAlbum album) =>
      _push(context, AlbumDetailScreen(album: album));

  static void openArtist(BuildContext context, SpotifyArtist artist) =>
      _push(context, ArtistDetailScreen(artist: artist));

  static void _push(BuildContext context, Widget page) {
    // 先取出两个 Navigator：关闭弹层后 context 可能已失效
    final root = Navigator.of(context, rootNavigator: true);
    final target = contentNavigator?.call() ?? Navigator.of(context);
    root.popUntil((route) => route is! PopupRoute);
    target.push(MaterialPageRoute(builder: (_) => page));
  }
}
