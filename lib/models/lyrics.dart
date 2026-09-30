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
      syllables: (json['syllables'] as List<dynamic>?)
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

class SpotifyLyrics {
  final String syncType; // 'LINE_SYNCED' or 'UNSYNCED'
  final List<LyricLine> lines;
  final String language;

  const SpotifyLyrics({
    this.syncType = 'LINE_SYNCED',
    this.lines = const [],
    this.language = 'en',
  });

  factory SpotifyLyrics.fromJson(Map<String, dynamic> json) {
    final lyricsData = json['lyrics'] is Map<String, dynamic>
        ? json['lyrics'] as Map<String, dynamic>
        : json;

    return SpotifyLyrics(
      syncType: lyricsData['syncType'] as String? ?? 'LINE_SYNCED',
      language: lyricsData['language'] as String? ?? 'en',
      lines: (lyricsData['lines'] as List<dynamic>?)
              ?.map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'syncType': syncType,
    'language': language,
    'lines': lines.map((l) => l.toJson()).toList(),
  };
}
