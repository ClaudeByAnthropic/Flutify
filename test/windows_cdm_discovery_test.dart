import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/services/eme/windows_cdm_process.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'each discovery picks up browser component updates by CDM version',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'flutify-cdm-discovery-',
      );
      addTearDown(() => root.delete(recursive: true));
      Future<String> component(List<String> segments, String version) async {
        final folder = p.joinAll([root.path, ...segments]);
        final dll = File(
          p.join(folder, '_platform_specific', 'win_x64', 'widevinecdm.dll'),
        );
        await dll.parent.create(recursive: true);
        await dll.writeAsBytes(
          [],
        ); // Discovery only: never execute a test library.
        await File(
          p.join(folder, 'manifest.json'),
        ).writeAsString(jsonEncode({'version': version}));
        return dll.path;
      }

      final bundled = await component([
        'programs',
        'Google',
        'Chrome',
        'Application',
        '154.0.8037.93',
        'WidevineCdm',
      ], '4.10.3050.0');
      final env = {
        'ProgramFiles': p.join(root.path, 'programs'),
        'LOCALAPPDATA': p.join(root.path, 'local'),
      };
      expect(await WindowsCdmProcess.installedLibraries(environment: env), [
        bundled,
      ]);
      final updated = await component([
        'local',
        'Google',
        'Chrome',
        'User Data',
        'WidevineCdm',
        '4.10.3112.0',
      ], '4.10.3112.0');
      final edge = await component([
        'local',
        'Microsoft',
        'Edge',
        'User Data',
        'WidevineCdm',
        '4.10.3100.0',
      ], '4.10.3100.0');
      await component([
        'local',
        'Google',
        'Chrome',
        'User Data',
        'WidevineCdm',
        'pending',
      ], '99.0.0.0');
      expect(await WindowsCdmProcess.installedLibraries(environment: env), [
        updated,
        edge,
        bundled,
      ]);
      await File(updated).delete();
      expect(await WindowsCdmProcess.installedLibraries(environment: env), [
        edge,
        bundled,
      ]);
    },
  );
}
