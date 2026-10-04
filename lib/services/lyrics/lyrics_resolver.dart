import '../../models/lyrics.dart';
import '../../models/lyrics_query.dart';
import 'lrclib_lyrics_source.dart';
import 'lyrics_language.dart';
import 'lyrics_translation.dart';
import 'netease_translation_source.dart';
import 'zh_script.dart';

/// 合并后的歌词与是否可以缓存（网络问题导致的结果不缓存，下次打开会重试）。
class ResolvedLyrics {
  final SpotifyLyrics lyrics;
  final bool cacheable;

  const ResolvedLyrics(this.lyrics, {this.cacheable = true});
}

/// 歌词来源合并：Spotify 官方优先，没有逐行同步歌词时用 LRCLIB 补全；
/// 之后可选挂译文源（网易云社区翻译，只取译文、不动原文）。
///
/// | Spotify 结果 | 处理 |
/// |---|---|
/// | 逐行同步（LINE_SYNCED） | 直接用，不查 LRCLIB |
/// | 只有纯文本（UNSYNCED） | LRCLIB 找到同步歌词就替换，否则保留纯文本 |
/// | 没有歌词（404） | LRCLIB 找到就用，否则为空 |
/// | 请求失败 | LRCLIB 找到就用，否则抛出原错误（调用方显示「暂无歌词」且不缓存） |
///
/// 「双语歌词」决定加载原文时是否预取网易云译文；翻译按钮 / 自动翻译通过 translate 独立查询。
/// 查询会把曲名与歌手发给网易云音乐。预取开关变化时由调用方重新解析
///（见 SpotifyProvider.invalidateResolvedLyrics）。查不到译文时保持单语；
/// 查询遇网络错误时把结果标记为不可缓存，下次打开歌词会重新尝试（原文本身已有缓存，重试很便宜）。
class LyricsResolver {
  final Future<SpotifyLyrics> Function(String trackId) _official;

  /// LRCLIB 补全来源；为 null 时只用官方歌词。
  final LrclibLyricsSource? fallback;

  /// 网易云译文来源；为 null 时不查译文。
  final NeteaseTranslationSource? translation;

  /// 设置里是否开启了补全；为 false 时行为与只用官方歌词相同。
  final bool Function() _fallbackEnabled;

  /// 是否在加载原文时预取双语歌词；主动翻译由 translate 单独处理。
  final bool Function() _translationEnabled;

  LyricsResolver(
    this._official, {
    this.fallback,
    bool Function()? fallbackEnabled,
    this.translation,
    bool Function()? translationEnabled,
  }) : _fallbackEnabled = fallbackEnabled ?? (() => true),
       _translationEnabled = translationEnabled ?? (() => true);

  /// 翻译按钮或自动翻译明确发起的查询，不依赖「预加载双语歌词」开关。
  /// 网易云提供中文社区译词；只转换译词字形，不把原文转字形冒充翻译。
  Future<LyricsTranslation?> translate(
    LyricsQuery query,
    SpotifyLyrics lyrics,
    String target,
  ) async {
    final embedded = LyricsTranslationController.official(lyrics, target);
    if (embedded != null) return embedded;
    if (!lyrics.isSynced || lyrics.lines.isEmpty) return null;
    final language = LyricsLanguage.normalize(target);
    var networkError = false;
    final source = translation;
    if (source != null && language.startsWith('zh')) {
      try {
        final found = await source.find(query, lyrics.lines);
        networkError = found.networkError;
        final lines = found.lines;
        if (lines != null &&
            lines.length == lyrics.lines.length &&
            lines.any((line) => line.words.trim().isNotEmpty)) {
          final code = LyricsLanguage.of(
            'und',
            lines.map((l) => l.words).join('\n'),
          );
          if (code.startsWith('zh')) {
            return LyricsTranslation(
              List.unmodifiable(
                lines.map(
                  (line) => ZhScript.convert(
                    line.words,
                    toSimplified: language != 'zh-Hant',
                  ),
                ),
              ),
              LyricsProvider.netease,
            );
          }
        }
      } catch (_) {
        networkError = true;
      }
    }
    if (_fallbackEnabled()) {
      final found = await fallback?.findTranslation(query, lyrics, target);
      if (found != null) return found;
    }
    if (networkError) throw StateError('Lyrics translation source unavailable');
    return null;
  }

  Future<ResolvedLyrics> resolve(LyricsQuery query) async {
    var resolved = await _resolveOriginal(query);
    final translated = await _attachTranslation(query, resolved);
    return translated ?? resolved;
  }

  /// 删除两路本地缓存（「重新获取歌词」）：LRCLIB 选词结果与网易云译文。
  Future<void> forget(LyricsQuery query) async {
    await fallback?.forget(query);
    await translation?.forget(query);
  }

  Future<ResolvedLyrics> _resolveOriginal(LyricsQuery query) async {
    SpotifyLyrics? official;
    Object? error;
    StackTrace? stack;
    try {
      official = await _official(query.trackId);
    } catch (e, s) {
      error = e;
      stack = s;
    }
    if (official != null && official.isSynced) return ResolvedLyrics(official);

    final fallback = this.fallback;
    var cacheable = error == null;
    if (fallback != null && _fallbackEnabled()) {
      final found = await fallback.find(query);
      final lyrics = found.lyrics;
      if (lyrics != null) return ResolvedLyrics(lyrics);
      if (found.networkError) cacheable = false;
    }
    if (error != null) Error.throwWithStackTrace(error, stack!);
    return ResolvedLyrics(
      official ?? const SpotifyLyrics(lines: []),
      cacheable: cacheable,
    );
  }

  /// 挂译文：开启了双语歌词、同步歌词且行内还没有译文（LRCLIB 双语对照已经带过）才查；命中返回新结果。
  /// 开关在这一刻读取，解析途中切换以切换后的为准。
  Future<ResolvedLyrics?> _attachTranslation(
    LyricsQuery query,
    ResolvedLyrics resolved,
  ) async {
    final source = translation;
    if (source == null || !_translationEnabled()) return null;
    final lines = resolved.lyrics.lines;
    if (!resolved.lyrics.isSynced || lines.isEmpty) return null;
    if (lines.any((l) => l.translation.isNotEmpty)) return null;

    NeteaseTranslationLookup found;
    try {
      found = await source.find(query, lines);
    } catch (_) {
      return ResolvedLyrics(resolved.lyrics, cacheable: false);
    }
    final translated = found.lines;
    if (translated == null ||
        translated.length != lines.length ||
        translated.every((t) => t.words.isEmpty)) {
      if (found.networkError)
        return ResolvedLyrics(resolved.lyrics, cacheable: false);
      return null;
    }
    // 按下标对齐（译文源保证与 lines 等长）：同一时间戳的两句原文各拿各的译文
    return ResolvedLyrics(
      SpotifyLyrics(
        syncType: resolved.lyrics.syncType,
        language: resolved.lyrics.language,
        provider: resolved.lyrics.provider,
        translationProvider: LyricsProvider.netease,
        alternatives: resolved.lyrics.alternatives,
        lines: [
          for (final (i, l) in lines.indexed)
            translated[i].words.isEmpty
                ? l
                : LyricLine(
                    startTimeMs: l.startTimeMs,
                    words: l.words,
                    translation: translated[i].words,
                    syllables: l.syllables,
                  ),
        ],
      ),
      cacheable: resolved.cacheable,
    );
  }
}
