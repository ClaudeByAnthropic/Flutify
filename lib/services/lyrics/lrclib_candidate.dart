import '../../models/lyrics.dart';
import 'lrc_parser.dart';

/// LRCLIB 返回的一条歌词记录（`/api/get` 返回单个对象，`/api/search` 返回数组）。
///
/// 只保留带同步歌词（`syncedLyrics`）的记录：纯文本歌词 Spotify 自己就有，补全的意义在于时间轴。
class LrclibCandidate {
  final String trackName;
  final String artistName;
  final String albumName;
  final String synced;

  /// 时长（秒），未知为 0。
  final double duration;
  final bool instrumental;

  /// 解析后的歌词行（纯音乐为空）。
  late final List<LyricLine> lines = instrumental ? const [] : LrcParser.parse(synced);

  /// 被判为翻译版 / 音译 / 双语对照（由选词器写入）。
  bool rejected = false;

  LrclibCandidate({
    required this.trackName,
    this.artistName = '',
    this.albumName = '',
    required this.synced,
    this.duration = 0,
    this.instrumental = false,
  });

  /// 解析单条记录；没有同步歌词或结构不对时返回 null。
  static LrclibCandidate? fromJson(Object? json) {
    if (json is! Map) return null;
    final synced = json['syncedLyrics'];
    if (synced is! String || synced.isEmpty) return null;
    String str(String key) => json[key] is String ? json[key] as String : '';
    final duration = json['duration'];
    return LrclibCandidate(
      trackName: str('trackName'),
      artistName: str('artistName'),
      albumName: str('albumName'),
      synced: synced,
      duration: duration is num ? duration.toDouble() : 0,
      instrumental: json['instrumental'] == true,
    );
  }

  /// 解析 `/api/get`（对象）或 `/api/search`（数组）的响应。
  static List<LrclibCandidate> listFrom(Object? json) {
    final items = json is List ? json : [json];
    return [for (final item in items) ?fromJson(item)];
  }
}
