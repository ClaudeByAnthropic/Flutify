import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// LRCLIB 补全歌词的本地缓存：`<目录>/<sha1(键)>.lrc`，同一首歌不再重复联网选词。
///
/// 只缓存选中的歌词原文（已对齐简繁）；「没找到」不落盘，下次启动会再试。
/// 读写失败一律静默：缓存只是加速，不影响歌词本身。
class LyricsDiskCache {
  final Directory directory;

  LyricsDiskCache(this.directory);

  File _file(String key) => File('${directory.path}${Platform.pathSeparator}${sha1.convert(utf8.encode(key))}.lrc');

  Future<String?> read(String key) async {
    try {
      final file = _file(key);
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String lrc) async {
    try {
      await directory.create(recursive: true);
      await _file(key).writeAsString(lrc, flush: true);
    } catch (_) {}
  }

  Future<void> remove(String key) async {
    try {
      final file = _file(key);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 已缓存的歌词份数。
  Future<int> count() async {
    try {
      if (!await directory.exists()) return 0;
      return await directory.list().where((e) => e is File && e.path.endsWith('.lrc')).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }
}
