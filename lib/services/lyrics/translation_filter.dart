import '../../models/lyrics.dart';
import 'lrclib_candidate.dart';
import 'lyric_script.dart';

/// 识别 LRCLIB 里的「翻译版 / 罗马音 / 双语对照」歌词：这些都不是原唱歌词，一律不用。
///
/// 依据（满足任一即排除）：
/// 1. 曲名 / 歌手 / 专辑带翻译标记（曲名与当前曲目完全一致时不看，避免误杀 "Lost in Translation"）；
/// 2. 歌词开头 600 字内带翻译标记（常见于「中文翻译：xxx」署名行）；
/// 3. 同一时间点（0.5 秒内）出现不同文种的两行，且这种成对行占三分之一以上；
/// 4. 整首有两种文字大类各占 40% 以上（整体双语混排）。
class TranslationFilter {
  TranslationFilter._();

  static const List<String> _markers = [
    'translation', 'translated', 'romanization', 'romanized', 'romanised', 'romaji', //
    'pronunciation', 'phonetic', 'pinyin',
    '翻譯', '翻译', '中譯', '中译', '羅馬音', '罗马音', '音譯', '音译', '空耳', '拼音', '注音', '對照', '对照',
  ];

  static bool hasMarker(String text) {
    if (text.isEmpty) return false;
    final low = text.toLowerCase();
    return _markers.any(low.contains);
  }

  /// 返回 true 表示这份歌词不要。[title] 为当前曲目名。
  static bool isRejected(LrclibCandidate c, String title) {
    final nameMatch = c.trackName.trim().toLowerCase() == title.trim().toLowerCase();
    if (!nameMatch && hasMarker('${c.trackName} ${c.artistName} ${c.albumName}')) return true;
    final head = c.synced.length > 600 ? c.synced.substring(0, 600) : c.synced;
    if (hasMarker(head)) return true;
    return isBilingual(c.lines);
  }

  /// 第 3、4 条：同时间点双语对照，或整体双语混排。
  static bool isBilingual(List<LyricLine> lines) {
    var n = 0, cjk = 0, lat = 0, cyr = 0, pairs = 0;
    final seen = <int, int>{};
    for (final l in lines) {
      if (l.words.trim().isEmpty) continue;
      n++;
      final fam = lineFamily(l.words);
      if (fam == 0) {
        cjk++;
      } else if (fam == 1) {
        lat++;
      } else if (fam == 2) {
        cyr++;
      }
      // 0.5 秒一个桶：译文对照常与原文共用时间戳
      final bucket = (l.startTimeMs / 500).round();
      final prev = seen[bucket];
      if (prev == null) {
        seen[bucket] = fam;
      } else if (prev >= 0 && fam >= 0 && prev != fam) {
        pairs++;
      }
    }
    if (n < 4) return false;
    if (pairs >= 3 && pairs * 3 >= n) return true;
    final big = [cjk, lat, cyr].where((k) => k * 5 >= n * 2).length;
    return big >= 2;
  }
}
