import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'cenc_audio.dart';

/// A temporary CDM session in a disposable native child process. Only opaque
/// requests/responses and media samples cross its anonymous pipes. Account
/// credentials stay in the existing Dart license client.
class WindowsCdmProcess {
  WindowsCdmProcess._(this._process) : _input = _PipeReader(_process.stdout) {
    // Never copy opaque CDM diagnostics/payloads into the application's log.
    _process.stderr.drain<void>().ignore();
  }

  final Process _process;
  final _PipeReader _input;
  final List<Uint8List> _messages = [];
  bool _closed = false;
  int interfaceVersion = 0;

  static Future<WindowsCdmProcess> start({
    String? helper,
    String? library,
  }) async {
    final executable =
        helper ??
        p.join(
          p.dirname(Platform.resolvedExecutable),
          'flutify_cdm_bridge.exe',
        );
    if (!await File(executable).exists())
      throw const CdmException('helper_missing');
    final candidates = library == null ? await installedLibraries() : [library];
    if (candidates.isEmpty) throw const CdmException('cdm_missing');
    for (final path in candidates) {
      WindowsCdmProcess? host;
      try {
        host = WindowsCdmProcess._(await Process.start(executable, [path]));
        final hello = await host._response().timeout(
          const Duration(seconds: 10),
        );
        if (hello.length != 4) throw const CdmException('invalid_greeting');
        host.interfaceVersion = ByteData.sublistView(
          hello,
        ).getUint32(0, Endian.little);
        return host;
      } catch (_) {
        host?.abort();
      }
    }
    throw const CdmException('cdm_initialization_failed');
  }

  /// Rediscover installed modules for every new session. Browser updates own
  /// installation/signatures; Flutify neither downloads nor bundles a CDM DLL.
  static Future<List<String>> installedLibraries({
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final applicationRoots = <String>{
      for (final base in [
        env['ProgramFiles'],
        env['ProgramFiles(x86)'],
        env['LOCALAPPDATA'],
      ])
        if (base != null)
          for (final browser in [
            'Google/Chrome/Application',
            'Microsoft/Edge/Application',
          ])
            p.joinAll([base, ...browser.split('/')]),
    };
    final componentRoots = <String>{
      if (env['LOCALAPPDATA'] case final base?)
        for (final browser in ['Google/Chrome', 'Microsoft/Edge'])
          p.joinAll([base, ...browser.split('/'), 'User Data', 'WidevineCdm']),
    };
    final folders = <String>{};
    for (final root in {...applicationRoots, ...componentRoots}) {
      try {
        await for (final item in Directory(root).list(followLinks: false)) {
          if (item is Directory &&
              RegExp(r'^\d+(\.\d+){3}$').hasMatch(p.basename(item.path))) {
            folders.add(
              applicationRoots.contains(root)
                  ? p.join(item.path, 'WidevineCdm')
                  : item.path,
            );
          }
        }
      } on FileSystemException {
        /* Browser or component updater directory is absent. */
      }
    }
    final found = <({String path, List<int> version})>[];
    for (final folder in folders) {
      try {
        final dll = p.join(
          folder,
          '_platform_specific',
          'win_x64',
          'widevinecdm.dll',
        );
        if (!await File(dll).exists()) continue;
        var version = <int>[];
        try {
          final manifest =
              jsonDecode(
                    await File(p.join(folder, 'manifest.json')).readAsString(),
                  )
                  as Map;
          version = (manifest['version'] as String)
              .split('.')
              .map(int.parse)
              .toList();
        } catch (_) {
          /* A valid installed DLL can still lack a manifest. */
        }
        found.add((path: dll, version: version));
      } on FileSystemException {
        /* Component was removed or replaced during browser update. */
      }
    }
    found.sort((a, b) {
      for (var i = 0; i < 4; i++) {
        final cmp = (i < b.version.length ? b.version[i] : 0).compareTo(
          i < a.version.length ? a.version[i] : 0,
        );
        if (cmp != 0) return cmp;
      }
      return a.path.compareTo(b.path);
    });
    return found.map((item) => item.path).toList();
  }

  Future<void> open({
    required Uint8List certificate,
    required Uint8List pssh,
    required Future<Uint8List> Function(Uint8List) postLicense,
  }) async {
    await _command(1, certificate);
    await _command(2, pssh);
    // Handles privacy-mode's message exchange without logging or altering it.
    var exchanges = 0;
    if (_messages.isEmpty) throw const CdmException('missing_license_request');
    while (_messages.isNotEmpty) {
      if (++exchanges > 4) throw const CdmException('license_exchange_limit');
      final response = await postLicense(_messages.removeAt(0));
      if (_closed) throw const CdmException('cancelled');
      await _command(3, response);
    }
  }

  Future<Uint8List> decryptBatch(
    List<CencSample> samples,
    Uint8List data,
  ) async {
    final builder = BytesBuilder(copy: false);
    void number(int n) {
      builder.add(
        (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List(),
      );
    }

    void blob(Uint8List bytes) {
      number(bytes.length);
      builder.add(bytes);
    }

    number(samples.length);
    var size = 0;
    for (final sample in samples) {
      blob(sample.kid);
      blob(sample.iv);
      number(sample.subsamples.length);
      for (final sub in sample.subsamples) {
        number(sub.clear);
        number(sub.cipher);
      }
      blob(
        Uint8List.sublistView(data, sample.offset, sample.offset + sample.size),
      );
      size += sample.size;
    }
    final output = await _command(4, builder.takeBytes());
    if (output.length != size)
      throw const CdmException('decrypted_size_mismatch');
    return output;
  }

  Future<Uint8List> _command(int kind, Uint8List bytes) async {
    if (_closed) throw const CdmException('cancelled');
    if (bytes.length + 1 > 8 * 1024 * 1024)
      throw const CdmException('frame_too_large');
    final header = ByteData(5)
      ..setUint32(0, bytes.length + 1, Endian.little)
      ..setUint8(4, kind);
    _process.stdin.add(header.buffer.asUint8List());
    _process.stdin.add(bytes);
    try {
      await _process.stdin.flush().timeout(const Duration(seconds: 10));
      return await _response().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      abort();
      throw const CdmException('cdm_timeout');
    }
  }

  Future<Uint8List> _response() async {
    for (;;) {
      final size = ByteData.sublistView(
        await _input.read(4),
      ).getUint32(0, Endian.little);
      if (size < 1 || size > 8 * 1024 * 1024)
        throw const CdmException('invalid_frame');
      final frame = await _input.read(size);
      final body = Uint8List.sublistView(frame, 1);
      if (frame[0] == 0) return body;
      if (frame[0] == 1) {
        _messages.add(body);
        continue;
      }
      if (frame[0] == 2 && body.length == 4) {
        throw CdmException(
          'cdm_${ByteData.sublistView(body).getUint32(0, Endian.little)}',
        );
      }
      throw const CdmException('invalid_response');
    }
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      await _command(5, Uint8List(0)).timeout(const Duration(seconds: 2));
      await _process.stdin.close();
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Forced termination below also destroys the temporary CDM. */
    } finally {
      abort();
    }
  }

  void abort() {
    if (_closed) return;
    _closed = true;
    _process.kill();
    _input.cancel();
    _process.stdin.close().ignore();
  }
}

class CdmException implements Exception {
  const CdmException(this.code);
  final String code;
  @override
  String toString() => 'Native Widevine: $code';
}

class _PipeReader {
  _PipeReader(Stream<List<int>> stream) : _chunks = StreamIterator(stream);
  final StreamIterator<List<int>> _chunks;
  List<int> _chunk = const [];
  int _at = 0;
  Future<Uint8List> read(int size) async {
    final output = Uint8List(size);
    var copied = 0;
    while (copied < size) {
      if (_at == _chunk.length) {
        if (!await _chunks.moveNext())
          throw const CdmException('process_exited');
        _chunk = _chunks.current;
        _at = 0;
      }
      final count = (size - copied).clamp(0, _chunk.length - _at);
      output.setRange(copied, copied + count, _chunk, _at);
      copied += count;
      _at += count;
    }
    return output;
  }

  void cancel() {
    _chunks.cancel().ignore();
  }
}
