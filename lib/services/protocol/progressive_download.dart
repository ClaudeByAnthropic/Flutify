import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'aes.dart';
import 'audio_normalization.dart';
import 'track_metadata.dart';

/// Spotify 音频文件头的处理规则（落盘与边下边播共用）。
///
/// Spotify 的 Ogg 文件以 0xa7 字节的私有头页开头（librespot `SPOTIFY_OGG_HEADER_END`），
/// 标准解码器不认识，需要跳过；跳过后必须紧跟 `OggS`，否则说明不是这种结构，按原样播放。
/// 私有头里偏移 144 起是响度数据（音量均衡用）。
class SpotifyAudioHeader {
  SpotifyAudioHeader._();

  static const int oggHeaderEnd = 0xa7;

  /// 判断需要跳过多少字节所需的最少数据量。
  static const int probeLength = oggHeaderEnd + 4;

  /// 解密后的文件开头 [head]（至少 [probeLength] 字节，不足时按不跳过处理）应跳过的字节数。
  static int skipFor(Uint8List head, AudioFileFormat format) {
    if (format.extension != 'ogg' || head.length < probeLength) return 0;
    final magic = String.fromCharCodes(head.sublist(oggHeaderEnd, oggHeaderEnd + 4));
    return magic == 'OggS' ? oggHeaderEnd : 0;
  }

  /// 私有头里的响度原始数据（16 字节，写 `.norm` 旁路文件用）；没有私有头或数据不合理时为 null。
  static Uint8List? normalizationBytesIn(Uint8List head, int skip) {
    if (skip == 0) return null;
    const start = AudioNormalization.headerOffset;
    if (head.length < start + AudioNormalization.byteLength) return null;
    final bytes = Uint8List.fromList(head.sublist(start, start + AudioNormalization.byteLength));
    return AudioNormalization.parse(bytes) == null ? null : bytes;
  }
}

/// 可边下载边播放的音频（已解密、已去掉私有头的字节流）。
///
/// 播放器通过 [read] 按字节区间取数据：区间内尚未下载到的部分会等待下载推进。
abstract class ProgressiveAudio {
  /// 可播放部分的总字节数（不含私有头）。
  int get length;

  /// MIME 类型（`audio/ogg` / `audio/mpeg`）。
  String get contentType;

  /// 已下载比例（0~1）。
  double get progress;

  /// 下载完成（成功）或失败（抛出原始错误）。
  Future<void> get done;

  /// 读取 `[start, end)`（可播放坐标，end 为空表示到结尾）。
  Stream<List<int>> read(int start, [int? end]);
}

/// 一次 CDN 下载：流式解密到内存缓冲区，同时可被播放器按区间读取。
///
/// 规则：
/// - 头部（[SpotifyAudioHeader.probeLength] 字节）到达后 [ready] 完成，此时即可开始播放；
/// - 中途断线时用 HTTP Range 从已收到的位置续传，依次轮换 CDN 地址，累计失败 [maxAttempts] 次才放弃；
/// - 服务器没给出总长度（无 Content-Length）时无法预分配缓冲区，退化为下载完成后才 [ready]。
class ProgressiveDownload implements ProgressiveAudio {
  final List<String> urls;
  final Uint8List key;
  final Uint8List iv;
  final AudioFileFormat format;
  final http.Client client;

  /// 单个地址失败后重试的总次数上限（含轮换到其他地址）。
  final int maxAttempts;

  ProgressiveDownload({
    required this.urls,
    required this.key,
    required this.iv,
    required this.format,
    required this.client,
    this.maxAttempts = 4,
  });

  /// 解密后的完整文件（含私有头）；总长度未知时下载期间为 null。
  Uint8List? _buffer;
  int _received = 0;
  int _skip = 0;
  Uint8List? _normalizationBytes;
  Object? _error;
  bool _started = false;

  final Completer<void> _ready = Completer<void>();
  final Completer<void> _done = Completer<void>();
  final List<({int bytes, Completer<void> completer})> _waiters = [];
  final List<void Function(double progress)> _progressListeners = [];

  /// 可以开始播放（头部已到达）；下载在此之前失败时抛出错误。
  Future<void> get ready => _ready.future;

  @override
  Future<void> get done => _done.future;

  bool get isComplete => _done.isCompleted && _error == null;

  @override
  int get length => (_buffer?.length ?? 0) - _skip;

  @override
  String get contentType => format.extension == 'ogg' ? 'audio/ogg' : 'audio/mpeg';

  @override
  double get progress {
    final total = _buffer?.length ?? 0;
    return total > 0 ? (_received / total).clamp(0.0, 1.0) : 0.0;
  }

  /// 文件私有头里的响度数据（[ready] 之后可用）。
  AudioNormalization? get normalization {
    final bytes = _normalizationBytes;
    return bytes == null ? null : AudioNormalization.parse(bytes);
  }

  /// 响度原始数据（16 字节），落盘时写入 `.norm` 旁路文件。
  Uint8List? get normalizationBytes => _normalizationBytes;

  /// 去掉私有头之后的完整音频（仅下载完成后可用），用于写入缓存。
  Uint8List get playableBytes => Uint8List.sublistView(_buffer!, _skip);

  /// 下载进度回调（0~1）。完成后添加的监听器立即收到 1.0。
  void addProgressListener(void Function(double progress) listener) {
    if (isComplete) {
      listener(1.0);
      return;
    }
    _progressListeners.add(listener);
  }

  /// 开始下载（重复调用无效）。
  void start() {
    if (_started) return;
    _started = true;
    // 结果通过 ready / done 观察；未被监听的错误不应成为未捕获异常
    _ready.future.catchError((Object _) {});
    _done.future.catchError((Object _) {});
    unawaited(_run());
  }

  Future<void> _run() async {
    if (urls.isEmpty) {
      _fail(StateError('没有可用的 CDN 地址'));
      return;
    }
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final url = urls[attempt % urls.length];
      try {
        await _fetch(url);
        _complete();
        return;
      } catch (e) {
        lastError = e;
      }
    }
    _fail(StateError('所有 CDN 地址下载失败：$lastError'));
  }

  /// 从 [_received] 处开始（续传时带 Range）下载到结尾。
  Future<void> _fetch(String url) async {
    final resume = _received > 0 && _buffer != null;
    final request = http.Request('GET', Uri.parse(url));
    if (resume) request.headers['Range'] = 'bytes=$_received-';
    final response = await client.send(request);
    final status = response.statusCode;
    if (status != 200 && status != 206) {
      await response.stream.drain<void>().catchError((_) {});
      throw StateError('CDN 返回 HTTP $status');
    }

    // 服务器忽略 Range 时从头重新写（内容相同，已交给播放器的数据不受影响）
    var pos = status == 206 ? _received : 0;
    if (_buffer == null) {
      final total = _totalLength(response);
      if (total != null && total > 0) _buffer = Uint8List(total);
    }
    final cipher = AesCtr.atOffset(key, iv, pos);
    final buffer = _buffer;
    // 总长度未知：先收集，结束后再整体放入缓冲区
    final pending = buffer == null ? BytesBuilder(copy: false) : null;

    await for (final chunk in response.stream) {
      final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      cipher.process(data);
      if (buffer != null) {
        if (pos + data.length > buffer.length) throw StateError('CDN 返回的数据超出声明长度');
        buffer.setRange(pos, pos + data.length, data);
        pos += data.length;
        if (pos > _received) _advance(pos);
      } else {
        pending!.add(data);
      }
    }

    if (pending != null) {
      final bytes = pending.takeBytes();
      if (bytes.isEmpty) throw StateError('CDN 返回空文件');
      _buffer = bytes;
      _advance(bytes.length);
    } else if (_received < buffer!.length) {
      throw StateError('下载中断（$_received/${buffer.length}）');
    }
  }

  /// 总长度：200 取 Content-Length；206 取 Content-Range 的 `/total`。
  static int? _totalLength(http.StreamedResponse response) {
    if (response.statusCode == 206) {
      final range = response.headers['content-range'];
      final slash = range?.lastIndexOf('/') ?? -1;
      if (range != null && slash >= 0) return int.tryParse(range.substring(slash + 1).trim());
      return null;
    }
    return response.contentLength;
  }

  void _advance(int received) {
    _received = received;
    final buffer = _buffer!;
    if (!_ready.isCompleted && (_received >= SpotifyAudioHeader.probeLength || _received >= buffer.length)) {
      final head = Uint8List.sublistView(buffer, 0, math.min(_received, SpotifyAudioHeader.probeLength));
      _skip = SpotifyAudioHeader.skipFor(head, format);
      _normalizationBytes = SpotifyAudioHeader.normalizationBytesIn(head, _skip);
      _ready.complete();
    }
    final p = progress;
    for (final listener in _progressListeners) {
      listener(p);
    }
    _waiters.removeWhere((w) {
      if (_received < w.bytes) return false;
      w.completer.complete();
      return true;
    });
  }

  void _complete() {
    if (!_ready.isCompleted) _ready.complete();
    _done.complete();
    for (final listener in _progressListeners) {
      listener(1.0);
    }
    _progressListeners.clear();
    _releaseWaiters();
  }

  void _fail(Object error) {
    _error = error;
    if (!_ready.isCompleted) _ready.completeError(error);
    _done.completeError(error);
    _progressListeners.clear();
    _releaseWaiters();
  }

  void _releaseWaiters() {
    for (final w in _waiters) {
      if (_error != null) {
        w.completer.completeError(_error!);
      } else {
        w.completer.complete();
      }
    }
    _waiters.clear();
  }

  /// 等到至少收到 [bytes] 字节（文件坐标）。下载失败时抛错；下载已结束仍不够时直接返回。
  Future<void> _waitFor(int bytes) {
    if (_received >= bytes || isComplete) return Future.value();
    if (_error != null) return Future.error(_error!);
    final completer = Completer<void>();
    _waiters.add((bytes: bytes, completer: completer));
    return completer.future;
  }

  @override
  Stream<List<int>> read(int start, [int? end]) async* {
    await ready;
    final buffer = _buffer!;
    var pos = start + _skip;
    final stop = math.min((end ?? length) + _skip, buffer.length);
    const maxChunk = 64 * 1024;
    while (pos < stop) {
      await _waitFor(pos + 1);
      final available = math.min(_received, stop);
      if (available <= pos) break; // 下载已结束但数据不够（不应发生）
      final chunkEnd = math.min(available, pos + maxChunk);
      yield Uint8List.sublistView(buffer, pos, chunkEnd);
      pos = chunkEnd;
    }
  }
}
