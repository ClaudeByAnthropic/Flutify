import 'dart:convert';

import 'package:http/http.dart' as http;

/// `track-playback/v1/media` 返回的一个音频文件（file_id + 格式 + 码率）。
class PlaybackFile {
  final String fileIdHex;
  final int format;
  final int bitrate;

  /// 该条目出自的 manifest 分组（`file_ids_mp4` / `file_ids_mp4_cbcs`）。
  /// macOS FairPlay 只认 cbcs 分组的加密形态（schm=cbcs）。
  final String formatKey;

  /// cbcs 分组的 audio 记录可能携带 `encoding_id`（FairPlay 的 assetId）。
  final String? encodingId;

  const PlaybackFile({
    required this.fileIdHex,
    required this.format,
    required this.bitrate,
    this.formatKey = '',
    this.encodingId,
  });
}

/// 曲目播放媒体信息（名称 / 时长 / 可选 MP4 文件列表）。
class TrackPlaybackMedia {
  final String name;
  final int durationMs;
  final List<PlaybackFile> mp4Files;

  const TrackPlaybackMedia({
    required this.name,
    required this.durationMs,
    required this.mp4Files,
  });

  /// 是否有可用的 CENC MP4 文件。
  bool get hasMp4 => mp4Files.isNotEmpty;

  /// 选免费档可播的 MP4：优先 128k（MP4_128），无则取最低码率。
  PlaybackFile? selectForFree() {
    if (mp4Files.isEmpty) return null;
    final sorted = [...mp4Files]
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
    return sorted.first;
  }

  /// 选 FairPlay 用的 cbcs 文件：只从 `file_ids_mp4_cbcs` 分组取、取最低码率；
  /// 无 cbcs 条目返回 null（该曲目对 macOS 解密不可用，调用方报「不可用」）。
  /// 对齐 Spotify Web 播放器的行为：keySystem 为 FairPlay 时只向 manifest 请求
  /// file_ids_mp4_cbcs（见 vendor 播放器 FILE_IDS_CBCS 分支）。
  PlaybackFile? selectCbcsForFairPlay() {
    final cbcs = mp4Files
        .where((f) => f.formatKey == 'file_ids_mp4_cbcs')
        .toList();
    if (cbcs.isEmpty) return null;
    cbcs.sort((a, b) => a.bitrate.compareTo(b.bitrate));
    return cbcs.first;
  }
}

/// 宽松转 int（服务端有时把 format/bitrate 给成字符串）。
int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// 拉取 `track-playback/v1/media`（桌面端身份），取 CENC MP4 文件列表。
///
/// 这是 Widevine/EME 链路的文件清单来源（与 metadata.proto 的 OGG/MP3 列表不同）。
Future<TrackPlaybackMedia> fetchTrackPlaybackMedia(
  String trackIdOrUri, {
  required Future<Map<String, String>> Function() headers,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final id = trackIdOrUri.split(':').last.split('?').first.split('/').last;
    final uri = 'spotify:track:$id';
    final url = Uri.parse(
      'https://spclient.wg.spotify.com/track-playback/v1/media/$uri'
      '?manifestFileFormat=file_ids_mp4&manifestFileFormat=file_ids_mp4_cbcs',
    );
    final h = await headers();
    final res = await c.get(url, headers: {...h, 'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw StateError('track-playback 失败：HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final item = body['media']?[uri]?['item'] as Map<String, dynamic>?;
    if (item == null) throw StateError('track-playback 响应缺 item');
    final metadata = item['metadata'] as Map<String, dynamic>? ?? {};
    final manifest = item['manifest'] as Map<String, dynamic>? ?? {};

    final files = <PlaybackFile>[];
    for (final entry in manifest.entries) {
      if (!entry.key.startsWith('file_ids_mp4')) continue;
      for (final f in (entry.value as List? ?? [])) {
        final m = f as Map<String, dynamic>;
        // 非字符串的 file_id 无法当十六进制 id 用：跳过这一项，不让整首歌解析失败
        final fid = m['file_id'];
        if (fid is! String) continue;
        files.add(
          PlaybackFile(
            fileIdHex: fid,
            format: _toInt(m['format']),
            bitrate: _toInt(m['bitrate']),
            formatKey: entry.key,
            encodingId: m['encoding_id']?.toString(),
          ),
        );
      }
    }
    return TrackPlaybackMedia(
      name: metadata['name'] as String? ?? '',
      durationMs: _toInt(metadata['duration']),
      mp4Files: files,
    );
  } finally {
    if (client == null) c.close();
  }
}

/// 拉取 sneaktables policy=1 的 HLS 清单（含 EXT-X-KEY 的 PSSH + EXT-X-MAP/BYTERANGE）。
///
/// 该清单是 EME 的 initData（PSSH）来源，也是 HLS.js 喂段的结构依据。
Future<String> fetchHlsManifest(
  String fileIdHex, {
  required Future<Map<String, String>> Function() headers,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final url = Uri.parse(
      'https://spclient.wg.spotify.com/sneaktables/v2/hls/1/$fileIdHex/audio.m3u8',
    );
    final h = await headers();
    final res = await c.get(
      url,
      headers: {...h, 'Accept': 'application/vnd.apple.mpegurl'},
    );
    if (res.statusCode != 200) {
      throw StateError('sneaktables HLS 清单失败：HTTP ${res.statusCode}');
    }
    return res.body;
  } finally {
    if (client == null) c.close();
  }
}
