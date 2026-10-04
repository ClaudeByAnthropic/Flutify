import '../../models/lyrics.dart';
import '../../models/lyrics_query.dart';
import 'artist_match.dart';
import 'lrc_parser.dart';
import 'lyric_script.dart';
import 'lyrics_disk_cache.dart';
import 'netease_client.dart';
import 'translation_merge.dart';

/// 一次译文查询的结果：[lines] 为 null 表示没找到（含「这首歌没有译文」这种确定结果）；
/// [networkError] 表示没找到可能只是网络问题，调用方不缓存本次结果。
class NeteaseTranslationLookup {
  /// 与查询时的原文行**按下标一一对应**（等长；没配上译文的行 words 为空串，时间轴取原文行的）。
  /// 按下标而不是按时间对齐：两句原文时间戳相同时不能共用一条译文。
  final List<LyricLine>? lines;
  final bool networkError;

  const NeteaseTranslationLookup(this.lines, {this.networkError = false});
}

/// 从网易云音乐补译文（社区翻译 `tlyric`，带时间轴）：只取译文，原文仍以 Spotify / LRCLIB 为准。
///
/// 流程：缓存命中直接对齐 → 否则「曲名 + 主唱」搜索 →（无结果就只按曲名）→ 按曲名一致
///（去掉版本后缀后比，见 [baseTitle]）、歌手对上、时长接近挑歌 → 取 `lrc` / `tlyric` → 对齐到现有原文行。
///
/// 对齐（网易云译文的时间轴对应它自己的原文，与 Spotify 的不一定重合）：
/// 1. 文本锚定：译文行先按时间贴到网易云原文行，再按歌词文字贴回我们的原文行；
///    同一句歌词出现多次（副歌）时贴到时间最近的那次——先用只出现一次的句子估出两条时间轴的
///    整体偏移，再按偏移校正后的时间就近挑，某次副歌缺译文时不会把后面的译文整体前移；
/// 2. 时间近邻兜底：没锚上的译文按（偏移校正后）±1.5 秒就近贴到还没译文的原文行；
/// 3. 覆盖率低于 [_minCoverage] 视为歌配错了，全盘放弃（宁可没译文，不上错位的）。
class NeteaseTranslationSource {
  final NeteaseClient _client;

  /// 本地缓存（可空：测试或不需要持久化时），存的是网易云的 `lrc` / `tlyric` 原文。
  final LyricsDiskCache? cache;
  final Future<void> Function(Duration) _sleep;

  NeteaseTranslationSource(
    this._client, {
    this.cache,
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future.delayed;

  /// 对齐后译文至少覆盖的非空原文行比例。
  static const double _minCoverage = 0.4;

  /// 中文原文不查译文：网易云上中文歌基本没有 tlyric，跳过能为绝大多数曲目省掉两次请求。
  static bool needsTranslation(List<LyricLine> originals) =>
      lyricLang(TranslationMerge.originalText(originals)) != LyricLang.zh;

  /// 缓存键：优先用 Spotify 曲目 ID（同一首歌多次搜歌结果不变，对齐在读取时重算）。
  /// v2：挑歌改为去版本后缀比曲名，「没找到这首歌」也落盘。
  static String cacheKey(LyricsQuery q) => q.trackId.isNotEmpty
      ? 'netease|v2|${q.trackId}'
      : 'netease|v2|${q.title} ${q.artist}';

  /// 删除这首歌的本地译文缓存（「重新获取歌词」）。
  Future<void> forget(LyricsQuery cacheKeyHint) async =>
      cache?.remove(cacheKey(cacheKeyHint));

  /// 为 [originals] 查译文；返回的译文行与 [originals] 按下标一一对应（见 [NeteaseTranslationLookup.lines]）。
  Future<NeteaseTranslationLookup> find(
    LyricsQuery query,
    List<LyricLine> originals,
  ) async {
    if (originals.isEmpty || !needsTranslation(originals))
      return const NeteaseTranslationLookup(null);

    final cacheGeneration = cache?.generation;
    final key = cacheKey(query);
    NeteaseLyricBundle? bundle;
    final hit = await cache?.read(key);
    if (hit != null) bundle = NeteaseLyricBundle.decode(hit);

    if (bundle == null) {
      final song = await _findSong(query);
      if (song.value == null) {
        // 搜到了但没有对得上的歌也是确定结果（存空 bundle），免得每次启动都重搜；网络问题不缓存
        if (!song.networkError)
          await cache?.write(
            key,
            const NeteaseLyricBundle().encode(),
            expectedGeneration: cacheGeneration,
          );
        return NeteaseTranslationLookup(null, networkError: song.networkError);
      }
      final lyric = await _client.lyric(song.value!.id);
      if (lyric.value == null)
        return NeteaseTranslationLookup(null, networkError: lyric.networkError);
      bundle = lyric.value!;
      // 「这首网易云歌没有译文」也是确定结果，一并缓存（重新获取歌词可强制刷新）
      await cache?.write(
        key,
        bundle.encode(),
        expectedGeneration: cacheGeneration,
      );
    }

    if (bundle.tlyric.trim().isEmpty)
      return const NeteaseTranslationLookup(null);
    final aligned = align(bundle.lrc, bundle.tlyric, originals);
    return NeteaseTranslationLookup(aligned);
  }

  /// 挑歌：曲名完全一致（网易云歌名通常不带版本后缀），多位艺人逐一比对，
  /// 两边都有时长时要求相差 ≤ 5 秒。
  Future<NeteaseResponse<NeteaseSong>> _findSong(LyricsQuery query) async {
    var networkError = false;
    var first = true;
    Future<NeteaseResponse<List<NeteaseSong>>> search(String keyword) async {
      if (!first) await _sleep(const Duration(milliseconds: 300));
      first = false;
      final res = await _client.search(keyword);
      networkError |= res.networkError;
      return res;
    }

    final title = baseTitle(query.title);
    var songs =
        (await search('$title ${query.primaryArtist}')).value ??
        const <NeteaseSong>[];
    // 只按曲名重搜是给「没搜到」用的：第一次就网络错误（断网 / 风控冷却中）时重搜也是白等，结果反正不缓存
    if (songs.isEmpty && !networkError)
      songs = (await search(title)).value ?? const <NeteaseSong>[];
    final pick = pickSong(songs, query);
    return NeteaseResponse(pick, networkError: pick == null && networkError);
  }

  /// 版本标记：Spotify 曲名常带「 - Remastered 2011」「 - Live」「(feat. X)」，网易云多半只有原曲名。
  static final RegExp _versionWord = RegExp(
    r'\b(?:feat|ft|with|remaster\w*|live|version|ver|edit|re-?mix|mix|mono|stereo|acoustic|unplugged|'
    r'from|deluxe|radio|explicit|clean|bonus|demo|single|album|extended|session)\b',
    caseSensitive: false,
  );
  static final RegExp _dashSuffix = RegExp(r'\s+[-–—]\s+(.+)$');
  static final RegExp _bracketed = RegExp(r'\s*[\(\[（【]([^\)\]）】]*)[\)\]）】]');

  /// 去掉版本后缀的曲名（保留大小写，搜索用）：「 - xxx」后缀与括号段只在含版本标记时去掉，
  /// 「Lemon（Cover 米津玄师）」「（伴奏）」这类不是同一份歌词的不动，挑歌时自然对不上。
  static String baseTitle(String title) {
    var t = title.trim();
    final dash = _dashSuffix.firstMatch(t);
    if (dash != null && _versionWord.hasMatch(dash.group(1)!))
      t = t.substring(0, dash.start);
    t = t.replaceAllMapped(
      _bracketed,
      (m) => _versionWord.hasMatch(m.group(1)!) ? '' : m.group(0)!,
    );
    t = t.trim();
    return t.isEmpty ? title.trim() : t;
  }

  /// 从搜索结果里挑出对应曲目；都没有把握返回 null（配错歌的译文比没有更糟）。
  /// 曲名去版本后缀后一致即可（remix / live 等不同版本靠时长区分），完全一致的优先、原版次之。
  static NeteaseSong? pickSong(List<NeteaseSong> songs, LyricsQuery query) {
    final wanted = baseTitle(query.title).toLowerCase();
    NeteaseSong? best;
    var bestScore = -1;
    for (final s in songs) {
      if (baseTitle(s.name).toLowerCase() != wanted) continue;
      // 歌手可比且对不上：同名的另一首歌（与 LRCLIB 选词同一标准）
      if (ArtistMatcher.compare(query.artist, s.artists) ==
          ArtistMatch.mismatch)
        continue;
      // 曲名完全一致最优先；其次网易云这条本身不带版本标记（原版，而不是 Live / Remix）
      var score =
          s.name.trim().toLowerCase() == query.title.trim().toLowerCase()
          ? 2
          : (baseTitle(s.name) == s.name.trim() ? 1 : 0);
      if (ArtistMatcher.compare(query.artist, s.artists) == ArtistMatch.match)
        score += 4;
      if (query.durationMs > 0 && s.durationMs > 0) {
        final dd = (s.durationMs - query.durationMs).abs();
        if (dd > 5000) continue; // 曲名相同的不同版本 / 不同歌
        score += 2;
      }
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best;
  }

  /// 把网易云 `tlyric` 对齐到我们的原文行；覆盖不足返回 null。
  /// 返回与 [originals] 等长、按下标对应的译文行（没有译文的为空串，含原文里的间奏空行）。
  static List<LyricLine>? align(
    String lrc,
    String tlyric,
    List<LyricLine> originals,
  ) {
    final refLines = LrcParser.parse(lrc);
    final transLines = LrcParser.parse(
      tlyric,
    ).where((l) => l.words.trim().isNotEmpty).toList();
    // 非空原文行及其在 originals 里的下标
    final originalIdx = [
      for (final (i, l) in originals.indexed)
        if (l.words.trim().isNotEmpty) i,
    ];
    final originalLines = [for (final i in originalIdx) originals[i]];
    if (transLines.isEmpty || originalLines.isEmpty) return null;

    final attached = <int, String>{}; // originals 索引 → 译文
    final usedOriginals = <int>{};
    final usedTrans = <int>{};

    // 1. 文本锚定：译文 →（同一时间桶）→ 网易云原文 →（文字相同）→ 我们的原文
    String normalize(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[\s　]+'), '')
        .replaceAll(RegExp(r'[\.,，、!！?？:：;；"“”()（）\-—…♪]'), '');
    final byText = <String, List<int>>{}; // 文字 → 我们的原文行（originalLines 下标）
    for (var i = 0; i < originalLines.length; i++) {
      byText.putIfAbsent(normalize(originalLines[i].words), () => []).add(i);
    }
    // 与网易云原文共享时间桶（0.5 秒）的行即其原文
    final refTexts = [
      for (final trans in transLines)
        {
          for (final r in refLines)
            if ((r.startTimeMs / 500).round() ==
                    (trans.startTimeMs / 500).round() &&
                r.words.trim().isNotEmpty)
              normalize(r.words),
        },
    ];

    // 两条时间轴的整体偏移（我们的 − 网易云的）：取只出现一次的句子算中位数，副歌按它校正后就近挑
    final deltas = <int>[
      for (final (ti, trans) in transLines.indexed)
        for (final text in refTexts[ti])
          if (byText[text]?.length == 1)
            originalLines[byText[text]!.single].startTimeMs - trans.startTimeMs,
    ]..sort();
    final offset = deltas.isEmpty ? 0 : deltas[deltas.length ~/ 2];

    for (final (ti, trans) in transLines.indexed) {
      final expected = trans.startTimeMs + offset;
      for (final text in refTexts[ti]) {
        var best = -1;
        for (final i in byText[text] ?? const <int>[]) {
          if (usedOriginals.contains(i)) continue;
          if (best < 0 ||
              (originalLines[i].startTimeMs - expected).abs() <
                  (originalLines[best].startTimeMs - expected).abs()) {
            best = i;
          }
        }
        if (best < 0) continue;
        usedOriginals.add(best);
        usedTrans.add(ti);
        attached[best] = trans.words;
        break;
      }
    }

    // 2. 时间近邻兜底：偏移校正后 ±1500ms 内最近且未占用的原文行
    for (final (ti, trans) in transLines.indexed) {
      if (usedTrans.contains(ti)) continue;
      var best = -1, bestDelta = 1501;
      for (var i = 0; i < originalLines.length; i++) {
        if (usedOriginals.contains(i)) continue;
        final delta =
            (originalLines[i].startTimeMs - trans.startTimeMs - offset).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          best = i;
        }
      }
      if (best >= 0) {
        usedOriginals.add(best);
        usedTrans.add(ti);
        attached[best] = trans.words;
      }
    }

    if (attached.length < originalLines.length * _minCoverage) return null;
    final byOriginal = {
      for (final e in attached.entries) originalIdx[e.key]: e.value,
    };
    return [
      for (final (i, l) in originals.indexed)
        LyricLine(startTimeMs: l.startTimeMs, words: byOriginal[i] ?? ''),
    ];
  }
}
