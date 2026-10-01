import 'dart:convert';

import 'package:flutify_app/models/lyrics.dart';
import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/providers/spotify_provider.dart';
import 'package:flutify_app/services/lyrics/lrclib_client.dart';
import 'package:flutify_app/services/lyrics/lrclib_lyrics_source.dart';
import 'package:flutify_app/services/lyrics/lyrics_resolver.dart';
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
    final query = LyricsQuery.fromTrack(SampleCatalog.track1);
    expect(spotify.cachedLyrics(id), isNull);

    final lyrics = await spotify.fetchLyrics(query);
    expect(lyrics.lines.map((l) => l.words), ['first line', 'second line']);
    expect(identical(spotify.cachedLyrics(id), lyrics), isTrue);

    await spotify.fetchLyrics(query);
    expect(requests.where((u) => u.path.contains('/color-lyrics/')), hasLength(1));
  });

  test('歌词写入缓存时通知曲目 ID；失败不通知', () async {
    final cached = <String>[];
    final sub = spotify.lyricsCached.listen(cached.add);
    await spotify.fetchLyrics(LyricsQuery.fromTrack(SampleCatalog.track1));
    lyricsStatus = 503;
    await spotify.fetchLyrics(LyricsQuery.fromTrack(SampleCatalog.track3));
    await Future<void>.delayed(Duration.zero);
    expect(cached, [SampleCatalog.track1.id]);
    await sub.cancel();
  });

  test('没有歌词（404）也会缓存为空歌词', () async {
    lyricsStatus = 404;
    final id = SampleCatalog.track2.id;
    final query = LyricsQuery.fromTrack(SampleCatalog.track2);

    final lyrics = await spotify.fetchLyrics(query);

    expect(lyrics.lines, isEmpty);
    expect(spotify.cachedLyrics(id), isNotNull);
  });

  test('歌词请求失败（5xx）返回空歌词但不缓存，下次会重试', () async {
    lyricsStatus = 503;
    final id = SampleCatalog.track3.id;
    final query = LyricsQuery.fromTrack(SampleCatalog.track3);

    final failed = await spotify.fetchLyrics(query);
    expect(failed.lines, isEmpty);
    expect(spotify.cachedLyrics(id), isNull);

    lyricsStatus = 200;
    final retried = await spotify.fetchLyrics(query);
    expect(retried.lines, hasLength(2));
  });

  group('LRCLIB 补全', () {
    late SpotifyProvider withFallback;
    var fallbackOn = true;
    var lrclibCalls = 0;

    // 合成 LRCLIB：/api/get 返回一份同步歌词，其余接口返回空
    http.Response lrclib(http.Request req) {
      lrclibCalls++;
      if (req.url.path.endsWith('/get')) {
        return http.Response(
          jsonEncode({
            'id': 1,
            'trackName': req.url.queryParameters['track_name'],
            'artistName': req.url.queryParameters['artist_name'],
            'syncedLyrics': '[00:01.00]synthetic one\n[00:02.50]synthetic two',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('[]', 200);
    }

    setUp(() {
      fallbackOn = true;
      lrclibCalls = 0;
      final api = SpotifyApiService(storage, MockClient((req) async => handle(req)));
      withFallback = SpotifyProvider(
        api,
        storage,
        lyrics: LyricsResolver(
          api.getLyrics,
          fallback: LrclibLyricsSource(
            LrclibClient(MockClient((req) async => lrclib(req)), sleep: (_) async {}),
            sleep: (_) async {},
          ),
          fallbackEnabled: () => fallbackOn,
        ),
      );
    });

    tearDown(() => withFallback.dispose());

    test('官方有逐行同步歌词时不查 LRCLIB', () async {
      final lyrics = await withFallback.fetchLyrics(LyricsQuery.fromTrack(SampleCatalog.track1));
      expect(lyrics.provider, LyricsProvider.spotify);
      expect(lrclibCalls, 0);
    });

    test('官方没有歌词时用 LRCLIB 补全并缓存', () async {
      lyricsStatus = 404;
      final query = LyricsQuery.fromTrack(SampleCatalog.track2);
      final lyrics = await withFallback.fetchLyrics(query);
      expect(lyrics.provider, LyricsProvider.lrclib);
      expect(lyrics.lines.map((l) => l.words), ['synthetic one', 'synthetic two']);
      expect(lyrics.lines.map((l) => l.startTimeMs), [1000, 2500]);
      expect(withFallback.cachedLyrics(query.trackId), same(lyrics));
    });

    test('关闭补全后保持官方结果', () async {
      lyricsStatus = 404;
      fallbackOn = false;
      final lyrics = await withFallback.fetchLyrics(LyricsQuery.fromTrack(SampleCatalog.track3));
      expect(lyrics.lines, isEmpty);
      expect(lrclibCalls, 0);
    });
  });
}
