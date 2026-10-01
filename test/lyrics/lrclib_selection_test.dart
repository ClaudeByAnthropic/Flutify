import 'package:flutify_app/models/lyrics_query.dart';
import 'package:flutify_app/services/lyrics/lrclib_candidate.dart';
import 'package:flutify_app/services/lyrics/lrclib_selector.dart';
import 'package:flutify_app/services/lyrics/lyric_script.dart';
import 'package:flutify_app/services/lyrics/translation_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// LRCLIB 选词：翻译版排除、原唱语言投票、简繁对齐（合成候选）。
void main() {
  const english =
      '[00:01.00]walking down the road\n[00:03.00]under the sky\n[00:05.00]all night long\n'
      '[00:07.00]you and me';
  const chinese = '[00:01.00]走在路上\n[00:03.00]天空下面\n[00:05.00]整夜不停\n[00:07.00]你和我';
  const japanese = '[00:01.00]道を歩いて\n[00:03.00]空の下で\n[00:05.00]夜通しずっと\n[00:07.00]君とわたし';
  const bilingual =
      '[00:01.00]walking down the road\n[00:01.10]走在路上\n[00:03.00]under the sky\n'
      '[00:03.10]天空下面\n[00:05.00]all night long\n[00:05.10]整夜不停';

  LrclibCandidate candidate(String synced, {String title = 'Road', double duration = 200, String artist = ''}) =>
      LrclibCandidate(trackName: title, artistName: artist, synced: synced, duration: duration);

  const query = LyricsQuery(trackId: 't', title: 'Road', artist: 'Someone', durationMs: 200000);

  group('TranslationFilter', () {
    test('曲名带翻译标记且与当前曲名不同时排除', () {
      expect(TranslationFilter.isRejected(candidate(chinese, title: 'Road (中文翻译)'), 'Road'), isTrue);
    });

    test('曲名完全一致时不因标记误杀', () {
      expect(
        TranslationFilter.isRejected(candidate(english, title: 'Lost in Translation'), 'Lost in Translation'),
        isFalse,
      );
    });

    test('同时间点双语对照判为双语', () {
      expect(TranslationFilter.isRejected(candidate(bilingual), 'Road'), isTrue);
      expect(TranslationFilter.isRejected(candidate(english), 'Road'), isFalse);
    });
  });

  group('LrclibSelector', () {
    test('多数候选的语言胜出：英文歌不会配上少数的译词', () {
      final picked = LrclibSelector.select([candidate(chinese), candidate(english), candidate(english)], query);
      expect(picked?.lang, LyricLang.latin);
      expect(picked?.synced, english);
    });

    test('日文原词占多数时选日文', () {
      final picked = LrclibSelector.select([candidate(japanese), candidate(japanese), candidate(english)], query);
      expect(picked?.lang, LyricLang.ja);
    });

    test('时长差太多的候选降权', () {
      final picked = LrclibSelector.select([
        candidate(english, duration: 400),
        candidate(english.replaceAll('road', 'street')),
      ], query);
      expect(picked?.synced, contains('street'));
    });

    test('只剩被排除的版本时退而求其次', () {
      final picked = LrclibSelector.select([candidate(bilingual)], query);
      expect(picked, isNotNull);
    });

    test('繁体曲名的歌把简体歌词转成繁体', () {
      const zhQuery = LyricsQuery(trackId: 't', title: '說話的時候', artist: '某人', durationMs: 200000);
      const simplified = '[00:01.00]说话的时候\n[00:03.00]这里会响\n[00:05.00]听见声音\n[00:07.00]东边门开';
      final picked = LrclibSelector.select([candidate(simplified, title: '說話的時候')], zhQuery);
      expect(picked?.lang, LyricLang.zh);
      expect(picked?.synced, contains('說話'));
    });

    test('没有候选返回 null', () => expect(LrclibSelector.select([], query), isNull));
  });
}
