import '../../models/lyrics.dart';
import '../../models/lyrics_query.dart';
import 'lrclib_lyrics_source.dart';

/// 合并后的歌词与是否可以缓存（网络问题导致的结果不缓存，下次打开会重试）。
class ResolvedLyrics {
  final SpotifyLyrics lyrics;
  final bool cacheable;

  const ResolvedLyrics(this.lyrics, {this.cacheable = true});
}

/// 歌词来源合并：Spotify 官方优先，没有逐行同步歌词时用 LRCLIB 补全。
///
/// | Spotify 结果 | 处理 |
/// |---|---|
/// | 逐行同步（LINE_SYNCED） | 直接用，不查 LRCLIB |
/// | 只有纯文本（UNSYNCED） | LRCLIB 找到同步歌词就替换，否则保留纯文本 |
/// | 没有歌词（404） | LRCLIB 找到就用，否则为空 |
/// | 请求失败 | LRCLIB 找到就用，否则抛出原错误（调用方显示「暂无歌词」且不缓存） |
class LyricsResolver {
  final Future<SpotifyLyrics> Function(String trackId) _official;

  /// LRCLIB 补全来源；为 null 时只用官方歌词。
  final LrclibLyricsSource? fallback;

  /// 设置里是否开启了补全；为 false 时行为与只用官方歌词相同。
  final bool Function() _fallbackEnabled;

  LyricsResolver(this._official, {this.fallback, bool Function()? fallbackEnabled})
    : _fallbackEnabled = fallbackEnabled ?? (() => true);

  Future<ResolvedLyrics> resolve(LyricsQuery query) async {
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
    return ResolvedLyrics(official ?? const SpotifyLyrics(lines: []), cacheable: cacheable);
  }
}
