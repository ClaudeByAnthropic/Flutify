import 'package:flutter/foundation.dart';

import '../core/constants/mock_spotify_data.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/image.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/storage_service.dart';

/// Your Library：已点赞歌曲、收藏歌单、关注艺人、收藏专辑与自建歌单。
///
/// 对应 Spotify 端点：/me/tracks、/me/playlists、/me/following、/me/albums。
/// 目前以本地持久化实现（JSON 存入 SharedPreferences），接入真实 Token 后
/// 可在各 toggle 方法中同步调用 Web API。
///
/// 所有列表采用「写时复制」：每次修改都生成新的 List 实例，getter 在两次修改之间
/// 返回同一实例。这样组件可以安全地 `context.select` 整个列表，
/// 只有真正发生变化时才重建。调用方不得原地修改返回的列表。
class LibraryProvider extends ChangeNotifier {
  static const String likedSongsId = 'liked_songs_collection';
  static const String likedSongsUri = 'spotify:collection:tracks';

  final StorageService _storage;

  /// 最新点赞在前（与 Spotify "Liked Songs" 排序一致）。
  List<SpotifyTrack> _likedTracks = const [];
  Set<String> _likedIds = const {};

  List<SpotifyPlaylist> _playlists = const [];
  List<SpotifyArtist> _artists = const [];
  List<SpotifyAlbum> _albums = const [];

  SpotifyPlaylist? _likedSongsCache;

  LibraryProvider(this._storage) {
    _load();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  List<SpotifyTrack> get likedTracks => _likedTracks;
  List<SpotifyPlaylist> get playlists => _playlists;
  List<SpotifyArtist> get artists => _artists;
  List<SpotifyAlbum> get albums => _albums;

  /// 用户自建（可编辑）的歌单。
  List<SpotifyPlaylist> get ownPlaylists => _playlists.where((p) => isOwnPlaylist(p.id)).toList();

  bool isOwnPlaylist(String id) => id.startsWith('local_');

  bool isLiked(String trackId) => _likedIds.contains(trackId);
  bool isPlaylistSaved(String id) => _playlists.any((p) => p.id == id);
  bool isFollowing(String artistId) => _artists.any((a) => a.id == artistId);
  bool isAlbumSaved(String id) => _albums.any((a) => a.id == id);

  /// 以歌单形式呈现的 Liked Songs，供详情页复用。
  SpotifyPlaylist get likedSongsPlaylist {
    return _likedSongsCache ??= SpotifyPlaylist(
      id: likedSongsId,
      name: 'Liked Songs',
      uri: likedSongsUri,
      description: 'All your favorite songs in one place.',
      ownerName: MockSpotifyData.currentUser.displayName,
      images: const [SpotifyImage(url: 'https://misc.scdn.co/liked-songs/liked-songs-640.png')],
      tracks: _likedTracks,
      totalTracks: _likedTracks.length,
      primaryColor: '#450af5',
    );
  }

  /// 按 id 查找媒体库中的歌单（含 Liked Songs），用于详情页实时反映修改。
  SpotifyPlaylist? findPlaylist(String id) {
    if (id == likedSongsId) return likedSongsPlaylist;
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------
  void toggleLike(SpotifyTrack track) {
    if (_likedIds.contains(track.id)) {
      _likedTracks = _likedTracks.where((t) => t.id != track.id).toList();
    } else {
      _likedTracks = [track, ..._likedTracks];
    }
    _likedIds = _likedTracks.map((t) => t.id).toSet();
    _likedSongsCache = null;
    _storage.writeJsonList(StorageService.keyLibraryLikedTracks, _likedTracks.map((t) => t.toJson()));
    notifyListeners();
  }

  void togglePlaylistSaved(SpotifyPlaylist playlist) {
    _playlists = isPlaylistSaved(playlist.id)
        ? _playlists.where((p) => p.id != playlist.id).toList()
        : [playlist, ..._playlists];
    _persistPlaylists();
    notifyListeners();
  }

  void toggleFollowArtist(SpotifyArtist artist) {
    _artists = isFollowing(artist.id)
        ? _artists.where((a) => a.id != artist.id).toList()
        : [artist, ..._artists];
    _storage.writeJsonList(StorageService.keyLibraryArtists, _artists.map((a) => a.toJson()));
    notifyListeners();
  }

  void toggleAlbumSaved(SpotifyAlbum album) {
    _albums = isAlbumSaved(album.id)
        ? _albums.where((a) => a.id != album.id).toList()
        : [album, ..._albums];
    _storage.writeJsonList(StorageService.keyLibraryAlbums, _albums.map((a) => a.toJson()));
    notifyListeners();
  }

  /// 新建歌单，返回创建结果。
  SpotifyPlaylist createPlaylist(String name) {
    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final playlist = SpotifyPlaylist(
      id: id,
      name: name.trim().isEmpty ? 'My Playlist #${ownPlaylists.length + 1}' : name.trim(),
      uri: 'spotify:playlist:$id',
      ownerName: MockSpotifyData.currentUser.displayName,
    );
    _playlists = [playlist, ..._playlists];
    _persistPlaylists();
    notifyListeners();
    return playlist;
  }

  /// 添加到自建歌单；已存在或歌单不存在时返回 false。
  bool addTrackToPlaylist(String playlistId, SpotifyTrack track) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return false;
    final playlist = _playlists[index];
    if (playlist.tracks.any((t) => t.id == track.id)) return false;

    final tracks = [...playlist.tracks, track];
    final updated = playlist.copyWith(
      tracks: tracks,
      totalTracks: tracks.length,
      // 自建歌单无封面时，使用第一首歌的专辑封面（Spotify 行为）
      images: playlist.images.isEmpty ? track.album?.images : null,
    );
    _playlists = [..._playlists]..[index] = updated;
    _persistPlaylists();
    notifyListeners();
    return true;
  }

  void removeTrackFromPlaylist(String playlistId, String trackId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;
    final playlist = _playlists[index];
    final tracks = playlist.tracks.where((t) => t.id != trackId).toList();
    _playlists = [..._playlists]..[index] = playlist.copyWith(tracks: tracks, totalTracks: tracks.length);
    _persistPlaylists();
    notifyListeners();
  }

  void deletePlaylist(String playlistId) {
    _playlists = _playlists.where((p) => p.id != playlistId).toList();
    _persistPlaylists();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------
  void _persistPlaylists() {
    _storage.writeJsonList(StorageService.keyLibraryPlaylists, _playlists.map((p) => p.toJson()));
  }

  void _load() {
    // 首次启动：用示例数据填充，并迁移旧版只存 ID 的点赞记录
    if (!_storage.hasKey(StorageService.keyLibraryLikedTracks)) {
      final legacy = _storage.legacyLikedTrackIds;
      _likedTracks = legacy.isNotEmpty
          ? MockSpotifyData.allTracks.where((t) => legacy.contains(t.id)).toList()
          : List.of(MockSpotifyData.playlistLikedSongs.tracks);
      _storage.writeJsonList(StorageService.keyLibraryLikedTracks, _likedTracks.map((t) => t.toJson()));
    } else {
      _likedTracks = _storage
          .readJsonList(StorageService.keyLibraryLikedTracks)
          .map(SpotifyTrack.fromJson)
          .toList();
    }
    _likedIds = _likedTracks.map((t) => t.id).toSet();

    if (!_storage.hasKey(StorageService.keyLibraryPlaylists)) {
      _playlists = MockSpotifyData.allPlaylists.where((p) => p.id != likedSongsId).toList();
      _persistPlaylists();
    } else {
      _playlists = _storage
          .readJsonList(StorageService.keyLibraryPlaylists)
          .map(SpotifyPlaylist.fromJson)
          .toList();
    }

    if (!_storage.hasKey(StorageService.keyLibraryArtists)) {
      _artists = [
        MockSpotifyData.artistTheWeeknd,
        MockSpotifyData.artistTaylorSwift,
        MockSpotifyData.artistBillieEilish,
      ];
      _storage.writeJsonList(StorageService.keyLibraryArtists, _artists.map((a) => a.toJson()));
    } else {
      _artists = _storage.readJsonList(StorageService.keyLibraryArtists).map(SpotifyArtist.fromJson).toList();
    }

    if (!_storage.hasKey(StorageService.keyLibraryAlbums)) {
      _albums = [MockSpotifyData.albumAfterHours, MockSpotifyData.albumHitMeHard];
      _storage.writeJsonList(StorageService.keyLibraryAlbums, _albums.map((a) => a.toJson()));
    } else {
      _albums = _storage.readJsonList(StorageService.keyLibraryAlbums).map(SpotifyAlbum.fromJson).toList();
    }
  }
}
