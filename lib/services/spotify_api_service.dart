import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants/mock_spotify_data.dart';
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
import 'pathfinder/desktop_data_source.dart';
import 'storage_service.dart';

/// 数据层：按登录方式选择数据来源，失败或未登录时降级到 Mock 数据。
///
/// - 桌面版 OAuth 会话：内部接口（Pathfinder GraphQL + spclient），见 [DesktopDataSource]；
///   失败时直接降级，不再请求对该 client_id 长期限流的公开 Web API；
/// - 其他会话 / 手动 Token：公开 Web API（api.spotify.com）。
class SpotifyApiService {
  final StorageService _storage;
  final http.Client _client;

  /// 鉴权服务；接入后每次请求前自动续期 access_token。未接入时仅使用手动填写的 Token。
  SpotifyAuthService? _auth;

  late final DesktopDataSource _desktop = DesktopDataSource(_client, headers: _headers);

  SpotifyApiService(this._storage, [http.Client? client])
      : _client = client ?? http.Client();

  void attachAuth(SpotifyAuthService auth) => _auth = auth;

  /// 当前是否走桌面端内部接口。
  bool get _useDesktop => isConfigured && _auth?.isLoggedIn == true && _auth?.method == AuthMethod.desktop;

  /// 桌面端内部接口取数；返回 null 或抛错时使用 [fallback]。
  Future<T> _desktopOr<T>(Future<T?> Function() load, T fallback) async {
    try {
      return await load() ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

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

  String get _baseUrl => _storage.apiBaseUrl.trim().isEmpty
      ? SpotifyEndpoints.defaultWebApiBase
      : _storage.apiBaseUrl;

  bool get isConfigured => _storage.accessToken.isNotEmpty && !_storage.useMockData;

  // Current User
  Future<SpotifyUser> getCurrentUser() async {
    if (!isConfigured) return MockSpotifyData.currentUser;
    final auth = _auth;
    if (_useDesktop && auth != null) {
      // 昵称头像已在登录时由内部资料接口获取
      return SpotifyUser(
        id: auth.username,
        displayName: auth.displayName.isEmpty ? 'Spotify User' : auth.displayName,
        images: auth.avatarUrl.isEmpty ? const [] : [SpotifyImage(url: auth.avatarUrl)],
      );
    }

    try {
      final res = await _client.get(Uri.parse('$_baseUrl${SpotifyEndpoints.me}'), headers: await _headers());
      if (res.statusCode == 200) {
        return SpotifyUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return MockSpotifyData.currentUser;
  }

  // Home Playlists & Shelves
  Future<List<SpotifyPlaylist>> getFeaturedPlaylists() async {
    if (!isConfigured) return MockSpotifyData.allPlaylists;
    if (_useDesktop) return _desktopOr(_desktop.homePlaylists, MockSpotifyData.allPlaylists);

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl${SpotifyEndpoints.featuredPlaylists}?limit=10'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['playlists'] != null && data['playlists']['items'] is List) {
          return (data['playlists']['items'] as List)
              .whereType<Map<String, dynamic>>()
              .map((p) => SpotifyPlaylist.fromJson(p))
              .toList();
        }
      }
    } catch (_) {}
    return MockSpotifyData.allPlaylists;
  }

  // Categories
  Future<List<SpotifyCategory>> getCategories() async {
    if (!isConfigured) return MockSpotifyData.categories;
    if (_useDesktop) return _desktopOr(_desktop.categories, MockSpotifyData.categories);

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl${SpotifyEndpoints.categories}?limit=20'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['categories'] != null && data['categories']['items'] is List) {
          return (data['categories']['items'] as List)
              .whereType<Map<String, dynamic>>()
              .map((c) => SpotifyCategory.fromJson(c))
              .toList();
        }
      }
    } catch (_) {}
    return MockSpotifyData.categories;
  }

  // Playlist Details
  Future<SpotifyPlaylist> getPlaylist(String id) async {
    if (!isConfigured) {
      final found = MockSpotifyData.allPlaylists.firstWhere(
        (p) => p.id == id,
        orElse: () => MockSpotifyData.playlistTodaysTopHits,
      );
      return found;
    }
    if (_useDesktop) return _desktopOr(() => _desktop.playlist(id), MockSpotifyData.playlistTodaysTopHits);

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl/playlists/$id'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        return SpotifyPlaylist.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return MockSpotifyData.playlistTodaysTopHits;
  }

  // Album Details
  Future<SpotifyAlbum> getAlbum(String id) async {
    if (!isConfigured) {
      return MockSpotifyData.allAlbums.firstWhere((a) => a.id == id, orElse: () => MockSpotifyData.albumAfterHours);
    }
    if (_useDesktop) {
      return _desktopOr(() async => (await _desktop.albumPage(id))?.album, MockSpotifyData.albumAfterHours);
    }

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl/albums/$id'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        return SpotifyAlbum.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return MockSpotifyData.albumAfterHours;
  }

  // Artist Details
  Future<SpotifyArtist> getArtist(String id) async {
    if (!isConfigured) {
      return MockSpotifyData.findArtist(id) ?? MockSpotifyData.artistTheWeeknd;
    }
    if (_useDesktop) {
      return _desktopOr(() async => (await _desktop.artistPage(id))?.artist, MockSpotifyData.artistTheWeeknd);
    }

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl/artists/$id'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        return SpotifyArtist.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return MockSpotifyData.artistTheWeeknd;
  }

  // Album Tracks
  // /albums/{id}/tracks 返回的是 simplified track（不含 album 字段），
  // 这里回填专辑信息，保证封面等字段可用。
  Future<List<SpotifyTrack>> getAlbumTracks(SpotifyAlbum album) async {
    if (!isConfigured) return MockSpotifyData.tracksForAlbum(album.id);
    if (_useDesktop) {
      return _desktopOr(() async => (await _desktop.albumPage(album.id))?.tracks, const <SpotifyTrack>[]);
    }

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl/albums/${album.id}/tracks?limit=50'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['items'] is List) {
          return (data['items'] as List)
              .whereType<Map<String, dynamic>>()
              .map((t) => SpotifyTrack.fromJson(t).copyWith(album: album))
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  // Artist Top Tracks
  Future<List<SpotifyTrack>> getArtistTopTracks(String id) async {
    if (!isConfigured) return MockSpotifyData.tracksForArtist(id);
    if (_useDesktop) {
      return _desktopOr(() async => (await _desktop.artistPage(id))?.topTracks, const <SpotifyTrack>[]);
    }

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl/artists/$id/top-tracks?market=from_token'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['tracks'] is List) {
          return (data['tracks'] as List)
              .whereType<Map<String, dynamic>>()
              .map((t) => SpotifyTrack.fromJson(t))
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  // Artist Albums (Discography)
  Future<List<SpotifyAlbum>> getArtistAlbums(String id) async {
    if (!isConfigured) return MockSpotifyData.albumsForArtist(id);
    if (_useDesktop) return _desktopOr(() => _desktop.artistAlbums(id), const <SpotifyAlbum>[]);

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl/artists/$id/albums?include_groups=album,single&limit=20'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['items'] is List) {
          return (data['items'] as List)
              .whereType<Map<String, dynamic>>()
              .map((a) => SpotifyAlbum.fromJson(a))
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  // Search
  Future<Map<String, List<dynamic>>> search(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      return {
        'tracks': <SpotifyTrack>[],
        'artists': <SpotifyArtist>[],
        'playlists': <SpotifyPlaylist>[],
      };
    }

    if (!isConfigured) {
      final matchedTracks = MockSpotifyData.allTracks
          .where((t) => t.name.toLowerCase().contains(clean) || t.artistNames.toLowerCase().contains(clean))
          .toList();
      final matchedPlaylists = MockSpotifyData.allPlaylists
          .where((p) => p.name.toLowerCase().contains(clean))
          .toList();
      final matchedArtists =
          MockSpotifyData.allArtists.where((a) => a.name.toLowerCase().contains(clean)).toList();

      return {
        'tracks': matchedTracks,
        'artists': matchedArtists,
        'playlists': matchedPlaylists,
      };
    }

    if (_useDesktop) {
      try {
        final r = await _desktop.search(query.trim());
        return {'tracks': r.tracks, 'artists': r.artists, 'playlists': r.playlists};
      } catch (_) {
        return {'tracks': <SpotifyTrack>[], 'artists': <SpotifyArtist>[], 'playlists': <SpotifyPlaylist>[]};
      }
    }

    try {
      final encoded = Uri.encodeComponent(query);
      final res = await _client.get(
        Uri.parse('$_baseUrl/search?q=$encoded&type=track,artist,playlist&limit=10'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tracks = (data['tracks']?['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map((t) => SpotifyTrack.fromJson(t))
                .toList() ??
            [];
        final artists = (data['artists']?['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map((a) => SpotifyArtist.fromJson(a))
                .toList() ??
            [];
        final playlists = (data['playlists']?['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map((p) => SpotifyPlaylist.fromJson(p))
                .toList() ??
            [];

        return {
          'tracks': tracks,
          'artists': artists,
          'playlists': playlists,
        };
      }
    } catch (_) {}

    return {
      'tracks': <SpotifyTrack>[],
      'artists': <SpotifyArtist>[],
      'playlists': <SpotifyPlaylist>[],
    };
  }

  // Connect Devices
  Future<List<SpotifyDevice>> getDevices() async {
    if (!isConfigured) return MockSpotifyData.devices;
    // 设备列表需要 dealer 长连接注册（connect-state），桌面版会话暂不提供，避免请求被限流的 Web API
    if (_useDesktop) return const [];

    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl${SpotifyEndpoints.playerDevices}'),
        headers: await _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['devices'] is List) {
          return (data['devices'] as List)
              .whereType<Map<String, dynamic>>()
              .map((d) => SpotifyDevice.fromJson(d))
              .toList();
        }
      }
    } catch (_) {}
    return MockSpotifyData.devices;
  }

  // Lyrics (SpClient color-lyrics 或 Mock)
  // 该内部端点必须声明 app-platform：官方客户端身份的会话沿用自身平台，其余情况按 WebPlayer 声明。
  // 获取失败时返回空歌词，由 UI 展示「暂无歌词」。
  Future<SpotifyLyrics> getLyrics(String trackId) async {
    if (!isConfigured) return MockSpotifyData.sampleLyrics;

    try {
      final path = SpotifyEndpoints.spclientColorLyrics.replaceAll('{track_id}', trackId);
      final res = await _client.get(
        Uri.parse('${SpotifyEndpoints.defaultSpClientBase}$path?format=json&vocalRemoval=false&market=from_token'),
        headers: {
          'app-platform': 'WebPlayer',
          ...await _headers(),
        },
      );
      if (res.statusCode == 200) {
        return SpotifyLyrics.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return const SpotifyLyrics(lines: []);
  }

  // Diagnostic API Tester for reverse-engineering inspect
  Future<Map<String, dynamic>> testApiEndpoint(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    final startTime = DateTime.now();
    try {
      final uri = Uri.parse(path.startsWith('http') ? path : '$_baseUrl$path');
      final headers = await _headers();
      http.Response res;

      if (method.toUpperCase() == 'POST') {
        res = await _client.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
      } else if (method.toUpperCase() == 'PUT') {
        res = await _client.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
      } else {
        res = await _client.get(uri, headers: headers);
      }

      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
      return {
        'status': res.statusCode,
        'latency_ms': latencyMs,
        'headers': res.headers,
        'body': res.body,
        'success': res.statusCode >= 200 && res.statusCode < 300,
      };
    } catch (e) {
      return {
        'status': 0,
        'latency_ms': DateTime.now().difference(startTime).inMilliseconds,
        'error': e.toString(),
        'success': false,
      };
    }
  }
}
