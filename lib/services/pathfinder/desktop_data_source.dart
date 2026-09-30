import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/spotify_endpoints.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/category.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import 'pathfinder_client.dart';
import 'pathfinder_operations.dart';
import 'pathfinder_parsers.dart';

/// 桌面版会话的数据来源：与官方桌面客户端相同的内部接口。
///
/// 桌面版 client_id 被众多第三方客户端共用，公开 Web API（api.spotify.com）长期处于 429 限流；
/// 这里改走 Pathfinder GraphQL 与 spclient，与官方桌面版的请求路径一致。
/// 专辑页 / 艺人页会先后请求"信息"与"曲目"，同一实体的查询在 [_cacheTtl] 内复用，避免重复请求。
class DesktopDataSource {
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// decorateContextTracks 单次补全的曲目数。
  static const int _decorateBatch = 50;

  /// 歌单详情最多加载的曲目数。
  static const int _playlistLimit = 100;

  final http.Client _client;
  final Future<Map<String, String>> Function() _headers;
  final PathfinderClient _pathfinder;
  final Map<String, _CacheEntry> _cache = {};

  DesktopDataSource(this._client, {required Future<Map<String, String>> Function() headers})
      : _headers = headers,
        _pathfinder = PathfinderClient(_client, headers: headers);

  /// 相同查询在有效期内合并为一次请求（含进行中的请求）。
  Future<Map<String, dynamic>> _query(PathfinderOperation op, Map<String, Object?> variables) {
    final key = '${op.name}:${jsonEncode(variables)}';
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) return cached.future;
    final future = _pathfinder.query(op, variables);
    _cache[key] = _CacheEntry(future, DateTime.now().add(_cacheTtl));
    // 失败的请求不缓存
    future.catchError((Object _) {
      _cache.remove(key);
      return const <String, dynamic>{};
    });
    if (_cache.length > 64) _cache.remove(_cache.keys.first);
    return future;
  }

  // ---------------------------------------------------------------------------
  // 主页 / 浏览
  // ---------------------------------------------------------------------------

  Future<List<SpotifyPlaylist>> homePlaylists() async {
    final data = await _query(PathfinderOperation.home, {
      'homeEndUserIntegration': kDesktopEndUserIntegration,
      'timeZone': _ianaTimeZone(),
      'sp_t': '',
      'facet': '',
      'sectionItemsLimit': 10,
      'includeEpisodeContentRatingsV2': false,
    });
    return PathfinderParsers.homePlaylists(data);
  }

  Future<List<SpotifyCategory>> categories() async {
    final data = await _query(PathfinderOperation.browseAll, {
      'pagePagination': {'offset': 0, 'limit': 10},
      'sectionPagination': {'offset': 0, 'limit': 99},
      'browseEndUserIntegration': kDesktopEndUserIntegration,
    });
    return PathfinderParsers.categories(data);
  }

  // ---------------------------------------------------------------------------
  // 专辑 / 艺人
  // ---------------------------------------------------------------------------

  Future<({SpotifyAlbum album, List<SpotifyTrack> tracks})?> albumPage(String id) async {
    final data = await _query(PathfinderOperation.getAlbum, {
      'uri': 'spotify:album:$id',
      'locale': '',
      'offset': 0,
      'limit': 50,
    });
    return PathfinderParsers.albumPage(data);
  }

  Future<({SpotifyArtist artist, List<SpotifyTrack> topTracks})?> artistPage(String id) async {
    final data = await _query(PathfinderOperation.queryArtistOverview, {
      'uri': 'spotify:artist:$id',
      'locale': '',
      'preReleaseV2': false,
    });
    return PathfinderParsers.artistPage(data);
  }

  Future<List<SpotifyAlbum>> artistAlbums(String id) async {
    // 唱片目录条目不带艺人信息：复用艺人页查询（通常已缓存）回填艺人名
    SpotifyArtist? artist;
    try {
      artist = (await artistPage(id))?.artist;
    } catch (_) {}
    final data = await _query(PathfinderOperation.queryArtistDiscographyAll, {
      'uri': 'spotify:artist:$id',
      'offset': 0,
      'limit': 20,
      'order': 'DATE_DESC',
    });
    return PathfinderParsers.discography(data, artist: artist);
  }

  // ---------------------------------------------------------------------------
  // 搜索
  // ---------------------------------------------------------------------------

  Future<({List<SpotifyTrack> tracks, List<SpotifyArtist> artists, List<SpotifyPlaylist> playlists})> search(
    String term,
  ) async {
    final data = await _pathfinder.query(PathfinderOperation.searchDesktop, {
      'searchTerm': term,
      'offset': 0,
      'limit': 10,
      'numberOfTopResults': 5,
      'includeAudiobooks': false,
      'includeArtistHasConcertsField': false,
      'includePreReleases': false,
      'includeLocalConcertsField': false,
      'includeAuthors': false,
    });
    return PathfinderParsers.search(data);
  }

  // ---------------------------------------------------------------------------
  // 歌单：spclient playlist/v2 取元数据与曲目 URI → decorateContextTracks 批量补全
  // ---------------------------------------------------------------------------

  Future<SpotifyPlaylist?> playlist(String id) async {
    final res = await _client.get(
      Uri.parse('${SpotifyEndpoints.defaultSpClientBase}/playlist/v2/playlist/$id'
          '?decorate=attributes,length,owner&from=0&length=$_playlistLimit'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) return null;
    final parsed = PathfinderParsers.playlistV2(id, jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    if (parsed == null) return null;

    final batches = <Future<List<SpotifyTrack>>>[];
    for (var i = 0; i < parsed.trackUris.length; i += _decorateBatch) {
      final uris = parsed.trackUris.sublist(i, (i + _decorateBatch).clamp(0, parsed.trackUris.length));
      batches.add(_pathfinder
          .query(PathfinderOperation.decorateContextTracks, {'uris': uris})
          .then(PathfinderParsers.decoratedTracks));
    }
    final tracks = (await Future.wait(batches)).expand((t) => t).toList();

    // 歌单无自定义封面时，以首曲专辑封面代替
    final playlist = parsed.playlist;
    final images = playlist.images.isEmpty && tracks.isNotEmpty ? tracks.first.album?.images : null;
    return playlist.copyWith(tracks: tracks, images: images);
  }

  /// 按 URI 批量补全曲目（decorateContextTracks，每批 [_decorateBatch] 首、最多 [concurrency] 批并行）。
  ///
  /// 返回顺序与 [uris] 一致；服务端未返回（下架 / 无权限）的曲目被略过。
  Future<List<SpotifyTrack>> tracksByUris(List<String> uris, {int concurrency = 3}) async {
    final batches = <List<String>>[
      for (var i = 0; i < uris.length; i += _decorateBatch)
        uris.sublist(i, (i + _decorateBatch).clamp(0, uris.length)),
    ];
    final results = List<List<SpotifyTrack>>.filled(batches.length, const []);
    var next = 0;
    Object? lastError;
    var failed = 0;
    Future<void> worker() async {
      while (next < batches.length) {
        final index = next++;
        try {
          final data = await _pathfinder.query(PathfinderOperation.decorateContextTracks, {'uris': batches[index]});
          results[index] = PathfinderParsers.decoratedTracks(data);
        } catch (e) {
          // 单批失败不拖垮整个列表
          lastError = e;
          failed++;
        }
      }
    }

    await Future.wait([for (var i = 0; i < concurrency && i < batches.length; i++) worker()]);
    // 全部批次都失败说明是网络 / 鉴权问题而非个别曲目缺失：抛出，避免调用方把它当成「空列表」
    if (batches.isNotEmpty && failed == batches.length) throw lastError!;
    final byId = {for (final t in results.expand((r) => r)) t.id: t};
    return [
      for (final uri in uris)
        ?byId[PathfinderParsers.idFromUri(uri)],
    ];
  }

  /// 歌单概要（名称、封面、曲目数，不含曲目）：rootlist 缺元数据时补全。
  Future<SpotifyPlaylist?> playlistSummary(String id) async {
    final res = await _client.get(
      Uri.parse('${SpotifyEndpoints.defaultSpClientBase}/playlist/v2/playlist/$id'
          '?decorate=attributes,length,owner&from=0&length=0'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) return null;
    return PathfinderParsers.playlistV2(id, jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)?.playlist;
  }

  /// home 查询需要 IANA 时区名；Dart 只能拿到 UTC 偏移，整点偏移用 `Etc/GMT∓N` 表示（符号与习惯相反）。
  static String _ianaTimeZone() {
    final offset = DateTime.now().timeZoneOffset;
    if (offset.inMinutes % 60 != 0 || offset == Duration.zero) return 'UTC';
    final hours = offset.inHours;
    return 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
  }
}

class _CacheEntry {
  final Future<Map<String, dynamic>> future;
  final DateTime expiresAt;
  const _CacheEntry(this.future, this.expiresAt);
}
