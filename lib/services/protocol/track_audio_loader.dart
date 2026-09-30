import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'access_point.dart';
import 'aes.dart';
import 'extended_metadata.dart';
import 'spotify_id.dart';
import 'storage_resolver.dart';
import 'track_metadata.dart';
import 'track_playback_exception.dart';

export 'track_playback_exception.dart';

/// 音频解密 IV（协议固定常量，对应 librespot `audio/src/decrypt.rs` 的 AUDIO_AESIV）。
final Uint8List kAudioAesIv = Uint8List.fromList([
  0x72, 0xe0, 0x67, 0xfb, 0xdd, 0xcb, 0xcf, 0x77,
  0xeb, 0xe8, 0xbc, 0x64, 0x3f, 0x63, 0x0d, 0x93,
]);

/// 一首「完整版全曲」的本地音频（已解密，可直接交给播放器）。
class LoadedAudio {
  final File file;
  final TrackAudioFile source;
  final int? durationMs;
  final String trackId;

  const LoadedAudio({
    required this.file,
    required this.source,
    required this.durationMs,
    required this.trackId,
  });

  String get path => file.path;
}

typedef AccessTokenGetter = Future<String> Function();

/// 曲目音频来源抽象：PlaybackProvider 只依赖它，测试可用替身实现（不必真的联网）。
abstract class TrackAudioSource {
  /// 取得一首曲目的本地可播放文件；失败抛 [TrackPlaybackException]。
  Future<LoadedAudio> load(String trackIdOrUri, {void Function(double progress)? progress});

  /// 预取（失败静默，不影响当前播放）。
  Future<void> prefetch(String trackIdOrUri);
}

/// 完整曲目音频加载器：metadata → storage-resolve → AP 音频密钥 → CDN 下载解密。
///
/// 全程只走逆向协议（不依赖官方客户端/Web 播放器）。产物缓存在 [cacheDirectory]/audio，
/// 同一 file_id 的曲目直接复用；下载中断只写临时文件，不会留下半截缓存。
/// 同一曲目的并发请求（预取 + 用户点播）合并为一次，缓存总量超过 [maxCacheBytes] 时淘汰最旧文件。
class TrackAudioLoader implements TrackAudioSource {
  final AccessTokenGetter accessToken;
  final AccessTokenGetter? clientToken;
  final String cacheDirectory;
  final http.Client _client;
  final List<AudioFileFormat> formatPreference;
  final String? deviceId;

  /// 音频缓存目录的容量上限（字节）。
  final int maxCacheBytes;

  Future<SpotifyAccessPoint>? _apSession;

  /// 进行中的加载（按曲目 id 合并，避免两路同时写同一个 .part 文件）。
  final Map<String, Future<LoadedAudio>> _inFlight = {};

  TrackAudioLoader({
    required this.accessToken,
    this.clientToken,
    required this.cacheDirectory,
    this.formatPreference = kPlayableFormatPreference,
    this.deviceId,
    this.maxCacheBytes = 512 * 1024 * 1024,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<Map<String, String>> _headers() async {
    final token = await accessToken();
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/x-protobuf',
    };
    if (clientToken != null) {
      headers['client-token'] = await clientToken!();
    }
    return headers;
  }

  /// 加载一首完整曲目（base62 id 或 `spotify:track:` URI），返回本地已解密文件。
  ///
  /// [progress] 回调 0.0~1.0（下载/解密进度）。已缓存时立即返回。
  @override
  Future<LoadedAudio> load(
    String trackIdOrUri, {
    void Function(double progress)? progress,
  }) {
    final SpotifyId id;
    try {
      id = SpotifyId.fromUri(trackIdOrUri);
    } on FormatException {
      return Future.error(
        const TrackPlaybackException(TrackPlaybackFailure.unavailable, '这首歌不是 Spotify 曲目，无法播放'),
      );
    }
    final key = id.toBase62();
    // 已在加载同一首：复用其结果（进度回调只属于第一个调用者）
    return _inFlight[key] ??= _load(id, progress).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<LoadedAudio> _load(SpotifyId id, void Function(double progress)? progress) async {
    // 1) metadata：取各格式 file_id
    final TrackMetadata meta;
    try {
      meta = await fetchTrackMetadata(id);
    } on TrackPlaybackException {
      rethrow;
    } catch (e) {
      throw TrackPlaybackException(TrackPlaybackFailure.network, '获取曲目信息失败，请检查网络', e);
    }
    final candidates = meta.candidateFiles(formatPreference);
    if (candidates.isEmpty) {
      // 有音频文件但都不是 OGG/MP3（FLAC / AAC 走 Widevine DRM，AP 不下发密钥）
      throw TrackPlaybackException(
        TrackPlaybackFailure.unavailable,
        meta.hasAnyFile ? '这首歌仅提供 DRM 加密格式，暂不支持播放' : '这首歌在你所在的地区或账号下暂不可播放',
      );
    }
    final durationMs = meta.durationMs > 0 ? meta.durationMs : null;

    // 2) 缓存命中：任一候选格式已落盘即直接使用
    for (final c in candidates) {
      final cached = _cacheFile(c.file);
      if (cached.existsSync() && cached.lengthSync() > 0) {
        progress?.call(1.0);
        return LoadedAudio(file: cached, source: c.file, durationMs: durationMs, trackId: id.toBase62());
      }
    }

    // 3) 音频密钥（AP 协议）：按音质逐档尝试，被拒（如免费账号请求 320k）则降一档
    final SpotifyAccessPoint ap;
    try {
      ap = await _ensureAccessPoint();
    } on ApLoginException catch (e) {
      _disposeAccessPoint();
      throw TrackPlaybackException(TrackPlaybackFailure.notSignedIn, '播放服务登录失败：${e.message}', e);
    } catch (e) {
      _disposeAccessPoint();
      throw TrackPlaybackException(TrackPlaybackFailure.network, '无法连接 Spotify 播放服务，请检查网络', e);
    }
    TrackAudioFile? file;
    Uint8List? key;
    Object? keyError;
    for (final c in candidates) {
      try {
        key = await ap.requestAudioKey(c.file.fileId, c.gid);
        file = c.file;
        break;
      } on ApKeyException catch (e) {
        keyError = e;
      } catch (e) {
        _disposeAccessPoint();
        throw TrackPlaybackException(TrackPlaybackFailure.network, '获取音频密钥超时，请稍后重试', e);
      }
    }
    if (file == null || key == null) {
      throw TrackPlaybackException(
        TrackPlaybackFailure.unavailable,
        '这首歌暂时无法播放（可能需要 Premium 或受版权限制）',
        keyError,
      );
    }

    // 4) CDN 解析 + 下载 + 流式解密
    final cached = _cacheFile(file);
    await cached.parent.create(recursive: true);
    final tmp = File('${cached.path}.part');
    try {
      final storage = await resolveAudioStorage(
        fileIdHex: file.fileIdHex,
        headers: _headers,
        client: _client,
      );
      await _downloadAndDecrypt(
        urls: storage.cdnUrls,
        key: key,
        destination: tmp,
        progress: progress,
      );
      await _finalize(tmp, cached, file.format);
    } catch (e) {
      if (tmp.existsSync()) tmp.deleteSync();
      throw TrackPlaybackException(TrackPlaybackFailure.network, '音频下载失败，请检查网络后重试', e);
    }
    _trimCache(keep: cached);

    return LoadedAudio(file: cached, source: file, durationMs: durationMs, trackId: id.toBase62());
  }

  /// 落盘：Spotify 的 Ogg 文件以 0xa7 字节的私有头页开头（librespot `SPOTIFY_OGG_HEADER_END`），
  /// 标准解码器不认识，剥掉后第二页必须以 `OggS` 开头；其余格式原样重命名。
  static Future<void> _finalize(File tmp, File destination, AudioFileFormat format) async {
    const spotifyOggHeaderEnd = 0xa7;
    final isOgg = format.extension == 'ogg';
    if (isOgg && tmp.lengthSync() > spotifyOggHeaderEnd + 4) {
      final raf = await tmp.open();
      await raf.setPosition(spotifyOggHeaderEnd);
      final magic = await raf.read(4);
      await raf.close();
      if (String.fromCharCodes(magic) == 'OggS') {
        await tmp.openRead(spotifyOggHeaderEnd).pipe(destination.openWrite());
        tmp.deleteSync();
        return;
      }
    }
    if (destination.existsSync()) destination.deleteSync(); // Windows 上 rename 不覆盖已有文件
    tmp.renameSync(destination.path);
  }

  /// 缓存淘汰：目录总量超过 [maxCacheBytes] 时，按修改时间从旧到新删除（保留 [keep]）。
  void _trimCache({required File keep}) {
    try {
      final dir = keep.parent;
      final files = dir.listSync().whereType<File>().where((f) => !f.path.endsWith('.part')).toList();
      var total = files.fold<int>(0, (sum, f) => sum + f.lengthSync());
      if (total <= maxCacheBytes) return;
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files) {
        if (total <= maxCacheBytes) break;
        if (f.path == keep.path) continue;
        total -= f.lengthSync();
        f.deleteSync();
      }
    } catch (_) {
      // 淘汰失败（文件被占用等）不影响播放
    }
  }

  /// 预取（失败静默，不影响播放流程）。
  @override
  Future<void> prefetch(String trackIdOrUri) async {
    try {
      await load(trackIdOrUri);
    } catch (_) {}
  }

  /// 拉取曲目 metadata。
  ///
  /// 优先 extended-metadata `TRACK_V4`（现网唯一稳定带 file 列表的来源）；
  /// 该扩展缺失时回退 `metadata/4/track/{gid}`（旧接口，新版客户端身份下常不含 file）。
  Future<TrackMetadata> fetchTrackMetadata(SpotifyId id) async {
    try {
      final payload = await ExtendedMetadataClient(_client, headers: _headers)
          .fetch('spotify:track:${id.toBase62()}', ExtensionKind.trackV4);
      if (payload != null) {
        final meta = TrackMetadata.parse(payload);
        if (meta.files.isNotEmpty || meta.alternatives.isNotEmpty) return meta;
      }
    } on ExtendedMetadataHttpException catch (e) {
      if (e.statusCode == 401) {
        throw const TrackPlaybackException(TrackPlaybackFailure.notSignedIn, '登录已失效，请重新登录后再播放');
      }
    }

    final res = await _client.get(
      Uri.parse('https://spclient.wg.spotify.com/metadata/4/track/${id.toBase16()}'),
      headers: await _headers(),
    );
    switch (res.statusCode) {
      case 200:
        return TrackMetadata.parse(res.bodyBytes);
      case 401:
        throw const TrackPlaybackException(TrackPlaybackFailure.notSignedIn, '登录已失效，请重新登录后再播放');
      case 404:
        throw const TrackPlaybackException(TrackPlaybackFailure.unavailable, '找不到这首歌的音频');
      default:
        throw StateError('metadata 请求失败：HTTP ${res.statusCode}');
    }
  }

  /// 复用 AP 会话（登录失效时重建一次）。
  Future<SpotifyAccessPoint> _ensureAccessPoint() async {
    Future<SpotifyAccessPoint> create() async {
      final ap = await SpotifyAccessPoint.connect(client: _client);
      await ap.authenticate(
        ApCredentials.accessToken(await accessToken()),
        deviceId: deviceId,
      );
      return ap;
    }

    try {
      final existing = await (_apSession ??= create());
      if (!existing.isClosed) return existing;
      _apSession = null;
      return await (_apSession = create());
    } catch (_) {
      _disposeAccessPoint();
      final ap = await create();
      _apSession = Future.value(ap);
      return ap;
    }
  }

  void _disposeAccessPoint() {
    final session = _apSession;
    _apSession = null;
    session?.then((ap) => ap.close()).catchError((_) {});
  }

  File _cacheFile(TrackAudioFile file) =>
      File('$cacheDirectory${Platform.pathSeparator}audio${Platform.pathSeparator}'
          '${file.fileIdHex}.${file.extension}');

  Future<void> _downloadAndDecrypt({
    required List<String> urls,
    required Uint8List key,
    required File destination,
    void Function(double progress)? progress,
  }) async {
    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadOne(url, key, destination, progress);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('所有 CDN 地址下载失败：$lastError');
  }

  Future<void> _downloadOne(
    String url,
    Uint8List key,
    File destination,
    void Function(double progress)? progress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw StateError('CDN 返回 HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? -1;
    final cipher = AesCtr(key, kAudioAesIv);
    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        final data = Uint8List.fromList(chunk);
        cipher.process(data); // AES-128-CTR 流式解密（与文件格式无关）
        sink.add(data);
        received += data.length;
        if (total > 0) progress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received == 0) throw StateError('CDN 返回空文件');
    progress?.call(1.0);
  }

  /// 释放资源（AP 会话与 HTTP 客户端）。
  void dispose() {
    _disposeAccessPoint();
    _client.close();
  }
}
