import '../../models/lyrics.dart';
import '../../models/lyrics_query.dart';
import 'lrc_parser.dart';
import 'lrclib_candidate.dart';
import 'lrclib_client.dart';
import 'lrclib_selector.dart';
import 'lyric_script.dart';
import 'lyrics_disk_cache.dart';
import 'zh_script.dart';

/// 一次补全查询的结果：[lyrics] 为 null 表示没找到；[networkError] 表示没找到可能只是网络问题。
class LrclibLookup {
  final SpotifyLyrics? lyrics;
  final bool networkError;

  const LrclibLookup(this.lyrics, {this.networkError = false});
}

/// 从 LRCLIB 补全逐行同步歌词（Spotify 没有歌词，或只有不滚动的纯文本歌词时使用）。
///
/// 查询顺序（移植自「任务栏歌词」，候选够投票就提前停）：
/// 1. 精确 get：曲名 + 歌手 + 专辑 + 时长；
/// 2. 曲名 + 主唱搜索（库里歌手名常与 Spotify 不一致：翻唱、艺名、简繁）；
/// 3. 只按曲名搜（候选少于 4 份时）；
/// 4. 全文 q 搜索兜底，并试简繁字形相反的曲名（候选少于 3 份时）。
/// 相邻请求间隔 [requestGap]，避免触发 LRCLIB 限流。选词规则见 [LrclibSelector]。
class LrclibLyricsSource {
  final LrclibClient _client;

  /// 本地缓存（可空：测试或不需要持久化时）。
  final LyricsDiskCache? cache;
  final Duration requestGap;
  final Future<void> Function(Duration) _sleep;

  LrclibLyricsSource(
    this._client, {
    this.cache,
    this.requestGap = const Duration(milliseconds: 600),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future.delayed;

  /// 缓存键：优先用 Spotify 曲目 ID（同一首歌的本地化曲名会变，ID 不会）。
  static String cacheKey(LyricsQuery q) =>
      q.trackId.isNotEmpty ? 'v1|${q.trackId}' : 'v1|${q.title}\u0001${q.artist}\u0001${q.album}';

  /// 删除这首歌的本地缓存（「重新获取歌词」）。
  Future<void> forget(LyricsQuery query) async => cache?.remove(cacheKey(query));

  Future<LrclibLookup> find(LyricsQuery query) async {
    if (query.title.trim().isEmpty) return const LrclibLookup(null);

    final key = cacheKey(query);
    final hit = await cache?.read(key);
    if (hit != null) {
      final lines = LrcParser.parse(hit);
      if (lines.isNotEmpty) return LrclibLookup(_lyrics(lines, lyricLang(hit)));
    }

    final candidates = <LrclibCandidate>[];
    var networkError = false;
    var first = true;
    Future<void> add(Future<LrclibResponse> Function() request) async {
      if (!first) await _sleep(requestGap);
      first = false;
      final res = await request();
      networkError |= res.networkError;
      candidates.addAll(res.candidates);
    }

    final title = query.title;
    await add(
      () => _client.get(
        track: title,
        artist: query.artist,
        album: query.album,
        durationSec: (query.durationMs / 1000).round(),
      ),
    );
    await add(() => _client.search(track: title, artist: query.primaryArtist));
    if (candidates.length < 4) await add(() => _client.search(track: title));
    if (candidates.length < 3) {
      final altTitle = detectLang('$title ${query.artist}') == LyricLang.zh
          ? ZhScript.convert(title, toSimplified: LrclibSelector.wantsTraditional(query))
          : null;
      final queries = [
        if (query.primaryArtist.isNotEmpty) '$title ${query.primaryArtist}',
        title,
        if (altTitle != null && altTitle != title) altTitle,
      ];
      for (final q in queries) {
        if (candidates.length >= 3) break;
        await add(() => _client.search(q: q));
      }
    }

    final selection = LrclibSelector.select(candidates, query);
    if (selection == null) return LrclibLookup(null, networkError: networkError);
    final lines = LrcParser.parse(selection.synced);
    if (lines.isEmpty) return LrclibLookup(null, networkError: networkError);
    await cache?.write(key, selection.synced);
    return LrclibLookup(_lyrics(lines, selection.lang));
  }

  static SpotifyLyrics _lyrics(List<LyricLine> lines, LyricLang lang) => SpotifyLyrics(
    lines: lines,
    language: switch (lang) {
      LyricLang.zh => 'zh',
      LyricLang.ja => 'ja',
      LyricLang.ko => 'ko',
      _ => 'en',
    },
    provider: LyricsProvider.lrclib,
  );
}
