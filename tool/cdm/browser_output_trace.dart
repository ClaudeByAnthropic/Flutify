// Disposable-browser diagnostic. Raw tracing data stays in memory; only the
// output-protection result and numeric masks leave this helper.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class BrowserOutputTrace {
  BrowserOutputTrace._(this._socket, this._client, this._report) {
    _subscription = _socket.listen(_receive);
  }

  final WebSocket _socket;
  final HttpClient _client;
  final void Function(Map<String, Object>) _report;
  final _pending = <int, Completer<void>>{};
  final _complete = Completer<void>();
  late final StreamSubscription<dynamic> _subscription;
  int _nextId = 0;

  static Future<BrowserOutputTrace> start(
    Directory profile,
    void Function(Map<String, Object>) report,
  ) async {
    final portFile = File('${profile.path}/DevToolsActivePort');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!await portFile.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('browser_trace_endpoint_timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final lines = await portFile.readAsLines();
    if (lines.length < 2 ||
        int.tryParse(lines[0]) == null ||
        !RegExp(r'^/devtools/browser/[a-zA-Z0-9-]+$').hasMatch(lines[1])) {
      throw StateError('browser_trace_endpoint_invalid');
    }
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    WebSocket socket;
    try {
      socket = await WebSocket.connect(
        'ws://127.0.0.1:${lines[0]}${lines[1]}',
        customClient: client,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
    final trace = BrowserOutputTrace._(socket, client, report);
    try {
      await trace._command('Tracing.start', {
        'categories': 'media',
        'transferMode': 'ReportEvents',
      });
      return trace;
    } catch (_) {
      await trace.close();
      rethrow;
    }
  }

  Future<void> navigate(String url) =>
      _command('Target.createTarget', {'url': url});

  Future<void> stop() async {
    await _command('Tracing.end');
    await _complete.future.timeout(const Duration(seconds: 5));
  }

  Future<void> close() async {
    try {
      await _subscription.cancel();
      await _socket.close().timeout(const Duration(seconds: 2));
    } finally {
      _client.close(force: true);
    }
  }

  Future<void> _command(String method, [Map<String, Object>? params]) async {
    final id = ++_nextId;
    final response = Completer<void>();
    _pending[id] = response;
    _socket.add(jsonEncode({'id': id, 'method': method, 'params': ?params}));
    try {
      await response.future.timeout(const Duration(seconds: 5));
    } finally {
      _pending.remove(id);
    }
  }

  void _receive(dynamic raw) {
    if (raw is! String) return;
    final message = jsonDecode(raw) as Map<String, dynamic>;
    if (message['id'] case final int id) {
      final response = _pending[id];
      if (response == null || response.isCompleted) return;
      if (message.containsKey('error')) {
        response.completeError(StateError('browser_trace_command_failed'));
      } else {
        response.complete();
      }
    } else if (message['method'] == 'Tracing.tracingComplete') {
      if (!_complete.isCompleted) _complete.complete();
    } else if (message['method'] == 'Tracing.dataCollected') {
      final events = (message['params'] as Map?)?['value'];
      if (events is! List) return;
      for (final event in events) {
        final result = outputProtectionTraceResult(event);
        if (result != null) _report(result);
      }
    }
  }
}

Map<String, Object>? outputProtectionTraceResult(dynamic event) {
  if (event is! Map ||
      event['name'] != 'CdmAdapter::OnQueryOutputProtectionStatusDone') {
    return null;
  }
  final args = event['args'];
  if (args is! Map || args['success'] is! bool) return null;
  final result = <String, Object>{'success': args['success'] as bool};
  final masks = args['link_mask, protection_mask'];
  if (masks is String) {
    final match = RegExp(
      r'^(?:0x)?([0-9a-fA-F]{1,8}), (?:0x)?([0-9a-fA-F]{1,8})$',
    ).firstMatch(masks);
    if (match != null) {
      result['link_mask'] = int.parse(match[1]!, radix: 16);
      result['protection_mask'] = int.parse(match[2]!, radix: 16);
    }
  }
  return result;
}
