import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/app_preferences.dart';
import '../../models/lyrics.dart';
import '../../models/lyrics_query.dart';
import 'lyrics_language.dart';

class LyricsTranslation {
  final List<String> lines;
  final LyricsProvider provider;

  const LyricsTranslation(this.lines, this.provider);
}

typedef TranslationLookup =
    Future<LyricsTranslation?> Function(
      LyricsQuery query,
      SpotifyLyrics lyrics,
      String target,
    );

/// Select source-provided translations. There is no machine translation here.
class LyricsTranslationController extends ChangeNotifier {
  final TranslationLookup? lookup;
  LyricsTranslationController({this.lookup});

  SpotifyLyrics? _lyrics;
  LyricsQuery? _query;
  String _target = '';
  String _trackKey = '';
  String _settingsKey = '';
  int _revision = 0;
  bool _disposed = false;
  bool _cancelled = false;
  bool _attempted = false;
  bool busy = false;
  bool failed = false;
  LyricsTranslation? _translation;

  List<String>? get lines => _translation?.lines;
  bool get fromLrclib => _translation?.provider == LyricsProvider.lrclib;
  bool get fromNetease => _translation?.provider == LyricsProvider.netease;
  bool get available => _lyrics != null && _lyrics!.lines.isNotEmpty;
  bool get unavailable =>
      _attempted && !failed && !busy && _translation == null;

  static LyricsTranslation? official(SpotifyLyrics lyrics, String target) {
    final normalized = LyricsLanguage.normalize(target);
    final alternatives = [...lyrics.alternatives]
      ..sort((a, b) {
        int rank(LyricsAlternative a) =>
            LyricsLanguage.normalize(a.language) == normalized ? 0 : 1;
        return rank(a).compareTo(rank(b));
      });
    for (final alternative in alternatives) {
      if (alternative.lines.length != lyrics.lines.length ||
          !alternative.lines.any((line) => line.trim().isNotEmpty))
        continue;
      final code = LyricsLanguage.of(
        alternative.language,
        alternative.lines.join('\n'),
      );
      if (!LyricsLanguage.matches(code, normalized)) continue;
      if (listEquals(
        alternative.lines,
        lyrics.lines.map((line) => line.words).toList(),
      ))
        continue;
      return LyricsTranslation(
        List.unmodifiable(alternative.lines),
        LyricsProvider.spotify,
      );
    }
    final inline = lyrics.lines.map((line) => line.translation).toList();
    final code = LyricsLanguage.of('und', inline.join('\n'));
    if (inline.any((line) => line.trim().isNotEmpty) &&
        LyricsLanguage.matches(code, normalized)) {
      return LyricsTranslation(
        List.unmodifiable(inline),
        lyrics.translationProvider ?? lyrics.provider,
      );
    }
    return null;
  }

  void configure(
    SpotifyLyrics? lyrics,
    AppPreferences prefs,
    String locale, {
    LyricsQuery? query,
  }) {
    if (_disposed) return;
    final code = LyricsLanguage.normalize(locale);
    final target = code == 'zh' ? 'zh-Hans' : code;
    final trackKey = query == null
        ? ''
        : '${query.trackId}|${query.title}|${query.artist}';
    final settingsKey =
        '${prefs.lyricsAutoTranslate}|${prefs.lyricsExcludeInterfaceLanguage}|'
        '${prefs.lyricsExcludedLanguages.join(',')}|${prefs.lyricsFallback}|${prefs.lyricsBilingual}';
    if (identical(lyrics, _lyrics) &&
        target == _target &&
        trackKey == _trackKey &&
        settingsKey == _settingsKey)
      return;
    final changedSong = trackKey != _trackKey;
    final changedContent =
        changedSong ||
        !identical(lyrics, _lyrics) ||
        target != _target ||
        settingsKey != _settingsKey;
    _lyrics = lyrics;
    _query = query;
    _target = target;
    _trackKey = trackKey;
    _settingsKey = settingsKey;
    if (changedSong) _cancelled = false;
    if (changedContent) {
      _revision++;
      busy = failed = _attempted = false;
      _translation = null;
    }
    notifyListeners();
    if (lyrics == null || _cancelled || !prefs.lyricsAutoTranslate) return;
    final source = LyricsLanguage.of(
      lyrics.language,
      lyrics.lines.map((l) => l.words).join('\n'),
    );
    if (prefs.lyricsExcludeInterfaceLanguage &&
        LyricsLanguage.excluded(source, target))
      return;
    if (prefs.lyricsExcludedLanguages.any(
      (code) => LyricsLanguage.excluded(source, code),
    ))
      return;
    unawaited(translate());
  }

  Future<void> translate() async {
    final lyrics = _lyrics;
    if (_disposed || lyrics == null || lyrics.lines.isEmpty || busy) return;
    _cancelled = false;
    failed = false;
    _attempted = true;
    final revision = ++_revision;
    _translation = official(lyrics, _target);
    if (_translation != null) {
      notifyListeners();
      return;
    }
    final query = _query;
    if (lookup == null || query == null) {
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final result = await lookup!(query, lyrics, _target);
      if (_disposed || revision != _revision) return;
      if (result != null && result.lines.length == lyrics.lines.length)
        _translation = result;
    } catch (_) {
      if (_disposed || revision != _revision) return;
      failed = true;
    }
    if (_disposed || revision != _revision) return;
    busy = false;
    notifyListeners();
  }

  void cancel() {
    _revision++;
    _cancelled = true;
    busy = failed = _attempted = false;
    _translation = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
