import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_release.dart';

abstract class UpdateInstaller {
  Future<UpdateTarget> target();
  Future<Directory> downloadDirectory();
  /// Returns false when Android has opened the unknown-source settings page.
  Future<bool> install(File package, String checksum);
}

class PlatformUpdateInstaller implements UpdateInstaller {
  final Future<void> Function() closeWindows;
  static const _channel = MethodChannel('flutify/updates');
  PlatformUpdateInstaller({required this.closeWindows});

  @override
  Future<UpdateTarget> target() async {
    if (Platform.isWindows) {
      final installed = await File(p.join(p.dirname(Platform.resolvedExecutable), 'unins000.exe')).exists();
      final arch = Abi.current() == Abi.windowsArm64 ? 'arm64' : 'x64';
      return UpdateTarget(installed ? UpdatePlatform.windowsInstaller : UpdatePlatform.windowsPortable, arch);
    }
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final abi = info.supportedAbis.firstWhere(
        (a) => const ['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(a),
        orElse: () => 'universal',
      );
      return UpdateTarget(UpdatePlatform.android, abi);
    }
    return const UpdateTarget(UpdatePlatform.unsupported, '');
  }

  @override
  Future<Directory> downloadDirectory() async {
    // Android's FileProvider exposes only cache/flutify-updates/.
    final base = Platform.isAndroid ? await getTemporaryDirectory() : await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'flutify-updates'));
  }

  @override
  Future<bool> install(File package, String checksum) async {
    // Recheck after any time spent waiting for the user's confirmation.
    final actual = await sha256.bind(package.openRead()).first;
    if (actual.toString() != checksum) throw const FormatException('Update SHA-256 mismatch');
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('installApk', {'path': package.path}) ?? false;
    }
    if (!Platform.isWindows) throw UnsupportedError('Use the release page');
    final operation = await (await downloadDirectory()).createTemp('apply-');
    final script = File(p.join(operation.path, 'update.ps1'));
    await script.writeAsString(await rootBundle.loadString('assets/updates/windows_update.ps1'));
    final plan = File(p.join(operation.path, 'plan.json'));
    await plan.writeAsString(jsonEncode({
      'target': p.dirname(Platform.resolvedExecutable),
      'package': package.absolute.path,
      'checksum': checksum,
      'processId': pid,
      'installer': (await target()).platform == UpdatePlatform.windowsInstaller,
    }));
    final powershell = p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows',
        'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    final args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', script.path, '-PlanPath', plan.path];
    final prepared = await Process.run(powershell, [...args, '-PrepareOnly']);
    if (prepared.exitCode != 0) throw StateError('Unable to prepare update: ${prepared.stderr}');
    // Detach the helper before normal app shutdown (which saves playback state).
    await Process.start(powershell, ['-WindowStyle', 'Hidden', ...args],
        mode: ProcessStartMode.detached);
    final ready = File(p.join(operation.path, 'waiting'));
    for (var i = 0; i < 100; i++) {
      if (await ready.exists()) {
        await File(p.join(operation.path, 'commit')).writeAsString('commit');
        await closeWindows();
        return true;
      }
      if (await File(p.join(operation.path, 'error.txt')).exists()) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // The helper requires an explicit commit file: a slow startup must not
    // unexpectedly apply an abandoned operation on some later app exit.
    await File(p.join(operation.path, 'cancelled')).writeAsString('cancelled');
    throw StateError('Update helper did not start');
  }
}
