import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/file_log.dart';

/// Paint a frame before opening plugins or touching persistent storage.
/// Keep failures and stalled platform calls visible even before FlutifyApp exists.
class AppStartup extends StatefulWidget {
  const AppStartup({super.key, required this.initialize});

  final Future<Widget> Function(ValueChanged<String> reportStage) initialize;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  String _stage = '正在启动';
  String? _failure;
  Widget? _app;
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    _timer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _slow = true);
    });
    try {
      final app = await widget.initialize((stage) {
        debugPrint('[Startup] $stage');
        if (mounted) setState(() => _stage = stage);
      });
      if (mounted) setState(() => _app = app);
      debugPrint('[Startup] Ready');
    } catch (error, stack) {
      debugPrint('[Startup] Failed at $_stage: $error\n$stack');
      if (mounted) setState(() => _failure = '$error\n$stack');
    } finally {
      _timer?.cancel();
    }
  }

  Future<void> _copyDiagnostics() async {
    final log = await readLogTail().timeout(
      const Duration(seconds: 2),
      onTimeout: () => '',
    );
    await Clipboard.setData(
      ClipboardData(
        text:
            'Flutify startup: $_stage\n${_failure ?? 'Initialization pending'}\n$log',
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_app != null) return _app!;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Flutify', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 24),
                  if (_failure == null) const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_failure == null ? _stage : '启动失败：$_stage'),
                  if (_failure != null || _slow) ...[
                    const SizedBox(height: 12),
                    Text(
                      _failure != null
                          ? '请复制诊断信息反馈，然后关闭并重新打开应用。'
                          : '启动时间较长，请复制诊断信息反馈。',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _copyDiagnostics,
                      child: const Text('复制诊断信息'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
