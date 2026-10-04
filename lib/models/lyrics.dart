class LyricLine {
  final int startTimeMs;
  final String words;
  final List<String> syllables;

  const LyricLine({
    required this.startTimeMs,
    required this.words,
    this.syllables = const [],
  });

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      startTimeMs: json['startTimeMs'] is String
          ? int.tryParse(json['startTimeMs'] as String) ?? 0
          : (json['startTimeMs'] as int? ?? 0),
      words: json['words'] as String? ?? '',
      syllables:
          (json['syllables'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'startTimeMs': startTimeMs,
    'words': words,
    'syllables': syllables,
  };
}

/// 歌词来源：Spotify 官方（color-lyrics），或 Spotify 没有逐行同步歌词时由 LRCLIB 补全。
enum LyricsProvider { spotify, lrclib }

/// 来源提供的其他语言译词，按下标对应原歌词（包括间奏空行）。
class LyricsAlternative {
  final String language;
  final List<String> lines;

  const LyricsAlternative({required this.language, required this.lines});

  static LyricsAlternative? fromJson(Object? json) {
    if (json is! Map) return null;
    final language = json['language'];
    final lines = json['lines'];
    if (language is! String ||
        language.isEmpty ||
        lines is! List ||
        lines.any((line) => line is! String))
      return null;
    return LyricsAlternative(
      language: language,
      lines: List<String>.unmodifiable(lines.cast<String>()),
    );
  }

  Map<String, dynamic> toJson() => {'language': language, 'lines': lines};
}

class SpotifyLyrics {
  final String syncType; // 'LINE_SYNCED' or 'UNSYNCED'
  final List<LyricLine> lines;
  final String language;
  final LyricsProvider provider;
  final List<LyricsAlternative> alternatives;

  const SpotifyLyrics({
    this.syncType = 'LINE_SYNCED',
    this.lines = const [],
    this.language = 'und',
    this.provider = LyricsProvider.spotify,
    this.alternatives = const [],
  });

  /// 有逐行时间轴、可以随播放滚动的歌词。
  bool get isSynced => syncType == 'LINE_SYNCED' && lines.isNotEmpty;

  factory SpotifyLyrics.fromJson(Map<String, dynamic> json) {
    final lyricsData = json['lyrics'] is Map<String, dynamic>
        ? json['lyrics'] as Map<String, dynamic>
        : json;

    return SpotifyLyrics(
      syncType: lyricsData['syncType'] as String? ?? 'LINE_SYNCED',
      language: lyricsData['language'] as String? ?? 'und',
      alternatives: lyricsData['alternatives'] is List
          ? [
              for (final entry in lyricsData['alternatives'] as List)
                ?LyricsAlternative.fromJson(entry),
            ]
          : const [],
      lines:
          (lyricsData['lines'] as List<dynamic>?)
              ?.map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'syncType': syncType,
    'language': language,
    'lines': lines.map((l) => l.toJson()).toList(),
    'alternatives': alternatives.map((a) => a.toJson()).toList(),
  };
}
