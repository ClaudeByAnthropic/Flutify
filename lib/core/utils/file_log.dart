import 'dart:io';

import 'package:flutter/foundation.dart';

/// 把 `debugPrint` 同时写进日志文件 `%TEMP%\flutify.log`（双击 / 任务栏启动时没有控制台，排查只能靠它）。
///
/// 每次启动覆盖旧文件；超过 [_maxBytes] 后停止写入，避免长时间运行撑大文件。
void installFileLog() {
  if (!Platform.isWindows) return;
  final IOSink sink;
  try {
    sink = File('${Directory.systemTemp.path}${Platform.pathSeparator}flutify.log')
        .openWrite(mode: FileMode.write);
  } catch (_) {
    return;
  }
  var written = 0;
  const maxBytes = 8 * 1024 * 1024;
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    original(message, wrapWidth: wrapWidth);
    if (message == null || written > maxBytes) return;
    final now = DateTime.now();
    final line = '${now.toIso8601String().substring(11, 23)} $message\n';
    written += line.length;
    sink.write(line);
  };
}
