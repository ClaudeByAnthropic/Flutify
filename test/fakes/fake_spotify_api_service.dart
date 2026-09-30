import 'package:flutify_app/models/album.dart';
import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/models/track.dart';
import 'package:flutify_app/services/library/library_source.dart';
import 'package:flutify_app/services/spotify_api_service.dart';

/// UI 测试用的数据服务：媒体库、歌词与专辑曲目来自内存，其余方法沿用真实实现
/// （未登录时返回空列表 / 抛 [SpotifyDataException.notSignedIn]，不会发网络请求）。
class FakeSpotifyApiService extends SpotifyApiService {
  /// 为空时沿用真实的会话媒体库（未登录即为空）。
  final LibrarySource? librarySource;

  /// 曲目 id → 歌词。
  final Map<String, SpotifyLyrics> lyricsById;

  /// 专辑 id → 曲目。
  final Map<String, List<SpotifyTrack>> albumTracks;

  FakeSpotifyApiService(
    super.storage, {
    this.librarySource,
    this.lyricsById = const {},
    this.albumTracks = const {},
  });

  @override
  LibrarySource get library => librarySource ?? super.library;

  @override
  Future<SpotifyLyrics> getLyrics(String trackId) async => lyricsById[trackId] ?? const SpotifyLyrics();

  @override
  Future<List<SpotifyTrack>> getAlbumTracks(SpotifyAlbum album) async => albumTracks[album.id] ?? const [];
}
