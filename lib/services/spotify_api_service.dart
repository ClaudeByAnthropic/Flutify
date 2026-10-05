import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants/spotify_endpoints.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/category.dart';
import '../l10n/app_locale.dart';
import '../models/device.dart';
import '../models/home_feed.dart';
import '../models/image.dart';
import '../models/lyrics.dart';
import '../models/playlist.dart';
import '../models/podcast.dart';
import '../models/track.dart';
import '../models/track_credits.dart';
import '../models/user_profile.dart';
import 'auth/spotify_auth_service.dart';
import 'auth/session_http_client.dart';
import 'connect/connect_service.dart';
import 'library/desktop_library_source.dart';
import 'library/library_source.dart';
import 'library/session_library_source.dart';
import 'library/web_api_library_source.dart';
import 'lyrics_service.dart';
import 'canvas/canvas_service.dart';
import 'pathfinder/desktop_data_source.dart';
import 'pathfinder/pathfinder_client.dart';
import 'podcast/podcast_service.dart';
import 'storage_service.dart';

/// 取数据失败（未登录、网络错误、接口返回异常）。[message] 为简体中文说明，可直接展示。
class SpotifyDataException implements Exception {
  final String message;
  final int? statusCode;

  const SpotifyDataException(this.message, [this.statusCode]);

  /// 需要先登录。
  static const SpotifyDataException notSignedIn = SpotifyDataException(
    '请先登录 Spotify 账号',
  );

  @override
  String toString() =>
      statusCode == null ? message : '$message（HTTP $statusCode）';
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
  late final CanvasService canvas = CanvasService(_client, headers: _headers);

  /// 鉴权服务；接入后每次请求前自动续期 access_token。未接入时仅使用手动填写的 Token。
  SpotifyAuthService? _auth;

  late final DesktopDataSource _desktop = DesktopDataSource(
    _client,
    headers: _headers,
    language: () => AppLocale.spotifyLanguage,
  );

  /// 歌词服务（color-lyrics）。
  late final LyricsService lyrics = LyricsService(_client, headers: _headers);

  /// 播客节目页数据（open.spotify.com 的服务端渲染状态，无需鉴权、不限流）。
  late final PodcastService _podcast = PodcastService(_client);

  /// Spotify Connect 遥控服务（dealer 长连接 + connect-state）；懒创建，调用 `start()` 才会联网。
  /// 只有桌面版会话可用，见 [supportsConnect]。
  late final ConnectService connect = ConnectService(
    client: _client,
    headers: _headers,
    deviceId: () => _storage.deviceId,
  );

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

  SpotifyApiService(this._storage, [http.Client? client])
    : _client = SessionHttpClient(_storage, client ?? http.Client());

  void attachAuth(SpotifyAuthService auth) => _auth = auth;

  /// 当前是否走桌面端内部接口。
  bool get _useDesktop => isConfigured && _auth?.isLoggedIn == true;

  /// 是否支持 Spotify Connect 遥控：dealer / connect-state 只接受桌面版会话的令牌与客户端身份。
  bool get supportsConnect => _useDesktop;

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
      'Accept-Language': AppLocale.spotifyLanguage,
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (clientToken.isNotEmpty) 'client-token': clientToken,
      // 与令牌所属客户端一致的 UA / app-platform / spotify-app-version（开发者应用 OAuth 为空）
      ...?auth?.clientHeaders,
    };
  }

  String get _baseUrl => _storage.apiBaseUrl.trim().isEmpty
      ? SpotifyEndpoints.defaultWebApiBase
      : _storage.apiBaseUrl;

  /// 是否已有可用的 access_token（登录或手动填写）。
  bool get isConfigured => _storage.accessToken.isNotEmpty;

  /// GET Web API 并解析 JSON 对象；非 200 抛 [SpotifyDataException]。
  Future<Map<String, dynamic>> _getJson(String path) async {
    final http.Response res;
    try {
      res = await _client.get(
        Uri.parse('$_baseUrl$path'),
        headers: await _headers(),
      );
    } catch (e) {
      throw SpotifyDataException('网络请求失败，请检查网络：$e');
    }
    if (res.statusCode != 200)
      throw SpotifyDataException('请求失败', res.statusCode);
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is! Map<String, dynamic>)
      throw const SpotifyDataException('服务端返回了无法识别的数据');
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
    } on PathfinderException catch (e) {
      // hash 失效的说明面向用户（引导升级客户端），直接透传不加「加载失败」前缀
      throw SpotifyDataException(e.message);
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
        displayName: auth.displayName.isEmpty
            ? 'Spotify User'
            : auth.displayName,
        images: auth.avatarUrl.isEmpty
            ? const []
            : [SpotifyImage(url: auth.avatarUrl)],
      );
    }
    return SpotifyUser.fromJson(await _getJson(SpotifyEndpoints.me));
  }

  // ---------------------------------------------------------------------------
  // 主页 / 浏览
  // ---------------------------------------------------------------------------
  /// 主页。[facet] 为筛选标签 id（空 = 全部）。
  ///
  /// 桌面版会话：与官方桌面端同一 home 查询，完整还原分区；
  /// 其余会话：公开 Web API 没有主页接口，只能用推荐歌单拼一个卡架（[facet] 无效）。
  Future<HomeFeed> getHome({String facet = ''}) async {
    if (!isConfigured) return HomeFeed.empty;
    if (_useDesktop) return _desktopLoad(() => _desktop.home(facet: facet));

    final data = await _getJson(
      '${SpotifyEndpoints.featuredPlaylists}?limit=20',
    );
    final items = (data['playlists'] as Map<String, dynamic>?)?['items'];
    final playlists = items is List
        ? items
              .whereType<Map<String, dynamic>>()
              .map(SpotifyPlaylist.fromJson)
              .toList()
        : const [];
    if (playlists.isEmpty) return HomeFeed.empty;
    return HomeFeed(
      sections: [
        HomeSection(
          uri: 'spotify:section:featured',
          kind: HomeSectionKind.shelf,
          title: (data['message'] as String?) ?? '',
          items: [
            for (final p in playlists)
              HomeItem(
                kind: HomeItemKind.playlist,
                uri: p.contextUri,
                title: p.name,
                subtitle: p.description,
                images: p.images,
                playlist: p,
              ),
          ],
        ),
      ],
    );
  }

  /// 「显示全部」：某个分区的更多条目。找不到该分区（主页已刷新换了一批）时抛 [SpotifyDataException]。
  Future<HomeSection> getHomeSection(String uri, {String facet = ''}) async {
    if (!isConfigured) throw SpotifyDataException.notSignedIn;
    if (_useDesktop)
      return _desktopLoad(() => _desktop.homeSection(uri, facet: facet));
    final home = await getHome();
    return home.sections.firstWhere(
      (s) => s.uri == uri,
      orElse: () => throw const SpotifyDataException('没有找到对应的内容'),
    );
  }

  Future<List<SpotifyCategory>> getCategories() async {
    if (!isConfigured) return const [];
    if (_useDesktop) return _desktopLoad(_desktop.categories);

    final data = await _getJson('${SpotifyEndpoints.categories}?limit=20');
    final items = (data['categories'] as Map<String, dynamic>?)?['items'];
    return items is List
        ? items
              .whereType<Map<String, dynamic>>()
              .map(SpotifyCategory.fromJson)
              .toList()
        : const [];
  }

  /// 分类页：分区与分区条目。
  ///
  /// 桌面版会话走 Pathfinder `browsePage`（[idOrUri] 为 browseAll 返回的分类 URI）；
  /// 其余会话公开 Web API 没有分区概念，用该分类的歌单拼一个分区兜底。
  Future<List<HomeSection>> getBrowsePage(String idOrUri) async {
    if (!isConfigured) throw SpotifyDataException.notSignedIn;
    if (_useDesktop) return _desktopLoad(() => _desktop.browsePage(idOrUri));

    final id = idOrUri.split(':').last;
    final data = await _getJson(
      SpotifyEndpoints.categoryPlaylists.replaceAll('{category_id}', id) +
          '?limit=20',
    );
    final items = (data['playlists'] as Map<String, dynamic>?)?['items'];
    final playlists = items is List
        ? items
              .whereType<Map<String, dynamic>>()
              .map(SpotifyPlaylist.fromJson)
              .toList()
        : const <SpotifyPlaylist>[];
    if (playlists.isEmpty) return const [];
    return [
      HomeSection(
        uri: 'spotify:section:category_$id',
        kind: HomeSectionKind.shelf,
        title: '',
        items: [
          for (final p in playlists)
            HomeItem(
              kind: HomeItemKind.playlist,
              uri: p.contextUri,
              title: p.name,
              subtitle: p.description,
              images: p.images,
              playlist: p,
            ),
        ],
      ),
    ];
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
    if (_useDesktop)
      return _desktopLoad(() async => (await _desktop.albumPage(id))?.album);
    return SpotifyAlbum.fromJson(await _getJson('/albums/$id'));
  }

  Future<SpotifyArtist> getArtist(String id) async {
    if (!isConfigured) throw SpotifyDataException.notSignedIn;
    if (_useDesktop)
      return _desktopLoad(() async => (await _desktop.artistPage(id))?.artist);
    return SpotifyArtist.fromJson(await _getJson('/artists/$id'));
  }

  /// 专辑曲目。/albums/{id}/tracks 返回的是 simplified track（不含 album 字段），
  /// 这里回填专辑信息，保证封面等字段可用。失败时返回空列表。
  Future<List<SpotifyTrack>> getAlbumTracks(SpotifyAlbum album) async {
    if (!isConfigured) return const [];
    try {
      if (_useDesktop)
        return (await _desktop.albumPage(album.id))?.tracks ?? const [];
      final data = await _getJson('/albums/${album.id}/tracks?limit=50');
      final items = data['items'];
      return items is List
          ? items
                .whereType<Map<String, dynamic>>()
                .map((t) => SpotifyTrack.fromJson(t).copyWith(album: album))
                .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  /// 艺人热门曲目；失败时返回空列表。
  Future<List<SpotifyTrack>> getArtistTopTracks(String id) async {
    if (!isConfigured) return const [];
    try {
      if (_useDesktop)
        return (await _desktop.artistPage(id))?.topTracks ?? const [];
      final data = await _getJson('/artists/$id/top-tracks?market=from_token');
      final items = data['tracks'];
      return items is List
          ? items
                .whereType<Map<String, dynamic>>()
                .map(SpotifyTrack.fromJson)
                .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  /// 曲目制作人员。只有桌面版会话可用（公开 Web API 没有对应接口）。
  Future<TrackCredits> getTrackCredits(String trackId) async {
    if (!isConfigured || !_useDesktop) throw SpotifyDataException.notSignedIn;
    return _desktopLoad(() => _desktop.trackCredits(trackId));
  }

  /// 以曲目为种子的「歌曲电台」歌单（只含 id 与占位名称，详情页会按 id 加载完整歌单）。
  /// 该曲目没有电台时抛 [SpotifyDataException]。
  Future<SpotifyPlaylist> getSongRadio(SpotifyTrack track) async {
    if (!isConfigured || !_useDesktop) throw SpotifyDataException.notSignedIn;
    final id = await _desktopLoad(() => _desktop.songRadioPlaylistId(track.id));
    return SpotifyPlaylist(id: id, name: track.name);
  }

  /// 按 URI 取单曲完整信息（Connect 远程曲目补全艺人 / 封面用）。
  /// 只有桌面版会话可用（与 Connect 一致）；非曲目 URI 或失败时返回 null。
  Future<SpotifyTrack?> getTrackByUri(String uri) async {
    if (!isConfigured || !_useDesktop || !uri.startsWith('spotify:track:'))
      return null;
    try {
      final tracks = await _desktop.tracksByUris([uri]);
      return tracks.isEmpty ? null : tracks.first;
    } catch (_) {
      return null;
    }
  }

  /// 艺人唱片目录；失败时返回空列表。
  Future<List<SpotifyAlbum>> getArtistAlbums(String id) async {
    if (!isConfigured) return const [];
    try {
      if (_useDesktop) return await _desktop.artistAlbums(id);
      final data = await _getJson(
        '/artists/$id/albums?include_groups=album,single&limit=20',
      );
      final items = data['items'];
      return items is List
          ? items
                .whereType<Map<String, dynamic>>()
                .map(SpotifyAlbum.fromJson)
                .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // 播客
  // ---------------------------------------------------------------------------

  /// 节目详情与最新单集（所有会话可用：不依赖鉴权接口）。
  Future<PodcastShow> getPodcastShow(String id) => _podcast.fetchShow(id);

  /// 单集详情（含所属节目 URI）；用于只带单集 URI 的入口（最近播放等）。
  Future<PodcastEpisode> getPodcastEpisode(String id) =>
      _podcast.fetchEpisode(id);

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
        return {
          'tracks': r.tracks,
          'artists': r.artists,
          'playlists': r.playlists,
        };
      } catch (e) {
        throw SpotifyDataException('搜索失败：$e');
      }
    }

    final data = await _getJson(
      '/search?q=${Uri.encodeComponent(clean)}&type=track,artist,playlist&limit=10',
    );
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) from) {
      final items = (data[key] as Map<String, dynamic>?)?['items'];
      return items is List
          ? items.whereType<Map<String, dynamic>>().map(from).toList()
          : <T>[];
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
      return items is List
          ? items
                .whereType<Map<String, dynamic>>()
                .map(SpotifyDevice.fromJson)
                .toList()
          : const [];
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
