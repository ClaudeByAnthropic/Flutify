import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants/spotify_endpoints.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/category.dart';
import '../models/device.dart';
import '../models/image.dart';
import '../models/lyrics.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user_profile.dart';
import 'auth/spotify_auth_service.dart';
import 'library/desktop_library_source.dart';
import 'library/library_source.dart';
import 'library/session_library_source.dart';
import 'library/web_api_library_source.dart';
import 'lyrics_service.dart';
import 'pathfinder/desktop_data_source.dart';
import 'storage_service.dart';

/// 取数据失败（未登录、网络错误、接口返回异常）。[message] 为简体中文说明，可直接展示。
class SpotifyDataException implements Exception {
  final String message;
  final int? statusCode;

  const SpotifyDataException(this.message, [this.statusCode]);

  /// 需要先登录。
  static const SpotifyDataException notSignedIn = SpotifyDataException('请先登录 Spotify 账号');

  @override
  String toString() => statusCode == null ? message : '$message（HTTP $statusCode）';
}

/// 数据层：只访问真实的 Spotify 接口，没有任何示例 / 离线兜底。
///
/// - 桌面版 OAuth 会话：内部接口（Pathfinder GraphQL + spclient），见 [DesktopDataSource]；
///   不再请求对该 client_id 长期限流的公开 Web API；
/// - 其他会话 / 手动 Token：公开 Web API（api.spotify.com）。
///
/// 失败约定：
/// - 未登录（没有 access_token）：列表类方法返回空列表，单个实体方法抛 [SpotifyDataException.notSignedIn]；
/// - 列表类方法在请求失败时同样抛 [SpotifyDataException]，由 Provider 决定如何展示错误；
///   曲目 / 唱片列表这类「附属列表」失败时返回空列表，不阻塞详情页主体。
class SpotifyApiService {
  final StorageService _storage;
  final http.Client _client;

  /// 鉴权服务；接入后每次请求前自动续期 access_token。未接入时仅使用手动填写的 Token。
  SpotifyAuthService? _auth;

  late final DesktopDataSource _desktop = DesktopDataSource(_client, headers: _headers);

  /// 歌词服务（color-lyrics）。
  late final LyricsService lyrics = LyricsService(_client, headers: _headers);

  /// 媒体库数据源：桌面版会话走内部接口，其余会话走 Web API；供 LibraryProvider 使用。
  late final LibrarySource library = SessionLibrarySource(
    useDesktop: () => _useDesktop,
    desktop: DesktopLibrarySource(
      client: _client,
      headers: _headers,
      data: _desktop,
      username: () => _storage.username,
      signedIn: () => isConfigured,
    ),
    web: WebApiLibrarySource(
      client: _client,
      headers: _headers,
      baseUrl: () => _baseUrl,
      username: () => _storage.username,
      signedIn: () => isConfigured,
    ),
  );

  SpotifyApiService(this._storage, [http.Client? client]) : _client = client ?? http.Client();

  void attachAuth(SpotifyAuthService auth) => _auth = auth;

  /// 当前是否走桌面端内部接口。
  bool get _useDesktop => isConfigured && _auth?.isLoggedIn == true && _auth?.method == AuthMethod.desktop;

  /// 请求头：已登录时先确保 access_token 未过期；续期失败则沿用旧值，由接口返回 401 体现。
  Future<Map<String, String>> _headers() async {
    final auth = _auth;
    if (auth != null && auth.isLoggedIn) {
      try {
        await auth.ensureAccessToken();
      } catch (_) {}
    }
    final token = _storage.accessToken;
    final clientToken = _storage.clientToken;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (clientToken.isNotEmpty) 'client-token': clientToken,
      // 与令牌所属客户端一致的 UA / app-platform / spotify-app-version（开发者应用 OAuth 为空）
      ...?auth?.clientHeaders,
    };
  }

  String get _baseUrl =>
      _storage.apiBaseUrl.trim().isEmpty ? SpotifyEndpoints.defaultWebApiBase : _storage.apiBaseUrl;

  /// 是否已有可用的 access_token（登录或手动填写）。
  bool get isConfigured => _storage.accessToken.isNotEmpty;

  /// GET Web API 并解析 JSON 对象；非 200 抛 [SpotifyDataException]。
  Future<Map<String, dynamic>> _getJson(String path) async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse('$_baseUrl$path'), headers: await _headers());
    } catch (e) {
      throw SpotifyDataException('网络请求失败，请检查网络：$e');
    }
    if (res.statusCode != 200) throw SpotifyDataException('请求失败', res.statusCode);
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is! Map<String, dynamic>) throw const SpotifyDataException('服务端返回了无法识别的数据');
    return json;
  }

  /// 桌面内部接口取数：查询返回 null（实体不存在）或抛错都转成 [SpotifyDataException]。
  Future<T> _desktopLoad<T>(Future<T?> Function() load) async {
    try {
      final value = await load();
      if (value == null) throw const SpotifyDataException('没有找到对应的内容');
      return value;
    } on SpotifyDataException {
      rethrow;
    } catch (e) {
      throw SpotifyDataException('加载失败：$e');
    }
  }

  // ---------------------------------------------------------------------------
  // 当前用户
  // ---------------------------------------------------------------------------
  Future<SpotifyUser> getCurrentUser() async {
    if (!isConfigured) return SpotifyUser.guest;
    final auth = _auth;
    if (_useDesktop && auth != null) {
      // 昵称头像已在登录时由内部资料接口获取
      return SpotifyUser(
        id: auth.username,
        displayName: auth.displayName.isEmpty ? 'Spotify User' : auth.displayName,
        images: auth.avatarUrl.isEmpty ? const [] : [SpotifyImage(url: auth.avatarUrl)],
      );
    }
    return SpotifyUser.fromJson(await _getJson(SpotifyEndpoints.me));
  }

  // ---------------------------------------------------------------------------
  // 主页 / 浏览
  // ---------------------------------------------------------------------------
  Future<List<SpotifyPlaylist>> getFeaturedPlaylists() async {
    if (!isConfigured) return const [];
    if (_useDesktop) return _desktopLoad(_desktop.homePlaylists);

    final data = await _getJson('${SpotifyEndpoints.featuredPlaylists}?limit=10');
    final items = (data['playlists'] as Map<String, dynamic>?)?['items'];
    return items is List ? items.whereType<Map<String, dynamic>>().map(SpotifyPlaylist.fromJson).toList() : const [];
  }

  Future<List<SpotifyCategory>> getCategories() async {
    if (!isConfigured) return const [];
    if (_useDesktop) return _desktopLoad(_desktop.categories);

    final data = await _getJson('${SpotifyEndpoints.categories}?limit=20');
    final items = (data['categories'] as Map<String, dynamic>?)?['items'];
    return items is List ? items.whereType<Map<String, dynamic>>().map(SpotifyCategory.fromJson).toList() : const [];
  }

  // ---------------------------------------------------------------------------
  // 歌单 / 专辑 / 艺人详情
  // ---------------------------------------------------------------------------
  Future<SpotifyPlaylist> getPlaylist(String id) async {
    if (!isConfigured) throw SpotifyDataException.notSignedIn;
    if (_useDesktop) return _desktopLoad(() => _desktop.playlist(id));
    return SpotifyPlaylist.fromJson(await _getJson('/playlists/$id'));
  }

  Future<SpotifyAlbum> getAlbum(String id) async {
    if (!isConfigured) throw SpotifyDataException.notSignedIn;
    if (_useDesktop) return _desktopLoad(() async => (await _desktop.albumPage(id))?.album);
    return SpotifyAlbum.fromJson(await _getJson('/albums/$id'));
  }

  Future<SpotifyArtist> getArtist(String id) async {
    if (!isConfigured) throw SpotifyDataException.notSignedIn;
    if (_useDesktop) return _desktopLoad(() async => (await _desktop.artistPage(id))?.artist);
    return SpotifyArtist.fromJson(await _getJson('/artists/$id'));
  }

  /// 专辑曲目。/albums/{id}/tracks 返回的是 simplified track（不含 album 字段），
  /// 这里回填专辑信息，保证封面等字段可用。失败时返回空列表。
  Future<List<SpotifyTrack>> getAlbumTracks(SpotifyAlbum album) async {
    if (!isConfigured) return const [];
    try {
      if (_useDesktop) return (await _desktop.albumPage(album.id))?.tracks ?? const [];
      final data = await _getJson('/albums/${album.id}/tracks?limit=50');
      final items = data['items'];
      return items is List
          ? items.whereType<Map<String, dynamic>>().map((t) => SpotifyTrack.fromJson(t).copyWith(album: album)).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  /// 艺人热门曲目；失败时返回空列表。
  Future<List<SpotifyTrack>> getArtistTopTracks(String id) async {
    if (!isConfigured) return const [];
    try {
      if (_useDesktop) return (await _desktop.artistPage(id))?.topTracks ?? const [];
      final data = await _getJson('/artists/$id/top-tracks?market=from_token');
      final items = data['tracks'];
      return items is List ? items.whereType<Map<String, dynamic>>().map(SpotifyTrack.fromJson).toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  /// 艺人唱片目录；失败时返回空列表。
  Future<List<SpotifyAlbum>> getArtistAlbums(String id) async {
    if (!isConfigured) return const [];
    try {
      if (_useDesktop) return await _desktop.artistAlbums(id);
      final data = await _getJson('/artists/$id/albums?include_groups=album,single&limit=20');
      final items = data['items'];
      return items is List ? items.whereType<Map<String, dynamic>>().map(SpotifyAlbum.fromJson).toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // 搜索
  // ---------------------------------------------------------------------------
  Future<Map<String, List<dynamic>>> search(String query) async {
    final clean = query.trim();
    final empty = <String, List<dynamic>>{
      'tracks': <SpotifyTrack>[],
      'artists': <SpotifyArtist>[],
      'playlists': <SpotifyPlaylist>[],
    };
    if (clean.isEmpty || !isConfigured) return empty;

    if (_useDesktop) {
      try {
        final r = await _desktop.search(clean);
        return {'tracks': r.tracks, 'artists': r.artists, 'playlists': r.playlists};
      } catch (e) {
        throw SpotifyDataException('搜索失败：$e');
      }
    }

    final data = await _getJson('/search?q=${Uri.encodeComponent(clean)}&type=track,artist,playlist&limit=10');
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) from) {
      final items = (data[key] as Map<String, dynamic>?)?['items'];
      return items is List ? items.whereType<Map<String, dynamic>>().map(from).toList() : <T>[];
    }

    return {
      'tracks': parse('tracks', SpotifyTrack.fromJson),
      'artists': parse('artists', SpotifyArtist.fromJson),
      'playlists': parse('playlists', SpotifyPlaylist.fromJson),
    };
  }

  // ---------------------------------------------------------------------------
  // Spotify Connect 设备
  // ---------------------------------------------------------------------------
  Future<List<SpotifyDevice>> getDevices() async {
    if (!isConfigured) return const [];
    // 设备列表需要 dealer 长连接注册（connect-state），桌面版会话暂不提供，避免请求被限流的 Web API
    if (_useDesktop) return const [];

    try {
      final data = await _getJson(SpotifyEndpoints.playerDevices);
      final items = data['devices'];
      return items is List ? items.whereType<Map<String, dynamic>>().map(SpotifyDevice.fromJson).toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // 歌词（spclient color-lyrics）
  // ---------------------------------------------------------------------------

  /// 取歌词：无歌词返回空歌词（可缓存）；网络 / 鉴权错误抛 [LyricsException]（不应缓存）。
  Future<SpotifyLyrics> getLyrics(String trackId) {
    if (!isConfigured) return Future.value(const SpotifyLyrics(lines: []));
    return lyrics.fetch(trackId);
  }
}
