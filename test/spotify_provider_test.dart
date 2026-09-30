import 'dart:convert';

import 'package:flutify_app/providers/spotify_provider.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/sample_catalog.dart';

/// 用内存 HTTP 替身代替网络：搜索按关键字返回合成曲目，歌词按曲目 id 返回合成歌词。
void main() {
  late SpotifyProvider spotify;
  late StorageService storage;
  late List<Uri> requests;
  var lyricsStatus = 200;

  http.Response handle(http.Request req) {
    requests.add(req.url);
    final path = req.url.path;
    if (path.contains('/color-lyrics/')) {
      if (lyricsStatus != 200) return http.Response('', lyricsStatus);
      return http.Response(
        jsonEncode({
          'lyrics': {
            'syncType': 'LINE_SYNCED',
            'lines': [
              {'startTimeMs': '1000', 'words': 'first line'},
              {'startTimeMs': '2000', 'words': 'second line'},
            ],
          },
        }),
        200,
      );
    }
    if (path.endsWith('/search')) {
      final q = req.url.queryParameters['q'] ?? '';
      final track = q.contains('two') ? SampleCatalog.track2 : SampleCatalog.track1;
      return http.Response(
        jsonEncode({
          'tracks': {
            'items': [
              {'id': track.id, 'name': track.name, 'uri': track.uri, 'artists': <dynamic>[]},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('{}', 404);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.init();
    await storage.setAccessToken('test-token'); // 合成令牌：仅用于让服务走「已配置」分支
    requests = [];
    lyricsStatus = 200;
    spotify = SpotifyProvider(SpotifyApiService(storage, MockClient((req) async => handle(req))), storage);
  });

  tearDown(() => spotify.dispose());

  test('rapid typing only applies the latest query', () async {
    spotify.performSearch('o');
    spotify.performSearch('on');
    spotify.performSearch('two');
    expect(spotify.isSearching, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(spotify.isSearching, isFalse);
    expect(spotify.searchTracks.map((t) => t.id), [SampleCatalog.track2.id]);
    expect(requests.where((u) => u.path.endsWith('/search')), hasLength(1), reason: '防抖后只发一次请求');
  });

  test('未登录（无令牌）时搜索返回空结果，不发请求', () async {
    await storage.setAccessToken('');

    spotify.performSearch('anything');
    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(spotify.searchTracks, isEmpty);
    expect(requests.where((u) => u.path.endsWith('/search')), isEmpty);
  });

  test('recent searches are deduplicated and persisted', () {
    spotify.commitRecentSearch('weeknd');
    spotify.commitRecentSearch('dua');
    spotify.commitRecentSearch('weeknd');

    expect(spotify.recentSearches, ['weeknd', 'dua']);
    expect(storage.recentSearches, ['weeknd', 'dua']);
  });

  test('lyrics are cached after the first fetch', () async {
    final id = SampleCatalog.track1.id;
    expect(spotify.cachedLyrics(id), isNull);

    final lyrics = await spotify.fetchLyrics(id);
    expect(lyrics.lines.map((l) => l.words), ['first line', 'second line']);
    expect(identical(spotify.cachedLyrics(id), lyrics), isTrue);

    await spotify.fetchLyrics(id);
    expect(requests.where((u) => u.path.contains('/color-lyrics/')), hasLength(1));
  });

  test('没有歌词（404）也会缓存为空歌词', () async {
    lyricsStatus = 404;
    final id = SampleCatalog.track2.id;

    final lyrics = await spotify.fetchLyrics(id);

    expect(lyrics.lines, isEmpty);
    expect(spotify.cachedLyrics(id), isNotNull);
  });

  test('歌词请求失败（5xx）返回空歌词但不缓存，下次会重试', () async {
    lyricsStatus = 503;
    final id = SampleCatalog.track3.id;

    final failed = await spotify.fetchLyrics(id);
    expect(failed.lines, isEmpty);
    expect(spotify.cachedLyrics(id), isNull);

    lyricsStatus = 200;
    final retried = await spotify.fetchLyrics(id);
    expect(retried.lines, hasLength(2));
  });
}
