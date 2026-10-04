// Local diagnostics only: no account data or license server is accessed.
import 'dart:io';
import 'dart:typed_data';

import '../../lib/services/eme/cenc_audio.dart';
import '../../lib/services/eme/windows_cdm_process.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/cdm/check_native_bridge.dart helper.exe encrypted.m4a',
    );
    exitCode = 2;
    return;
  }
  final file = await File(arguments[1]).readAsBytes();
  final audio = CencAudio.parse(file);
  stdout.writeln(
    'cenc_parsed bytes=${file.length} encrypted_samples=${audio.samples.length} pssh_bytes=${audio.pssh.length}',
  );
  for (final dll in await WindowsCdmProcess.installedLibraries()) {
    final host = await WindowsCdmProcess.start(
      helper: arguments[0],
      library: dll,
    );
    stdout.writeln('native_interface=${host.interfaceVersion}');
    try {
      await host.decryptBatch(audio.samples.take(2).toList(), file);
      throw StateError(
        'Encrypted media unexpectedly decrypted without a license',
      );
    } on CdmException catch (error) {
      if (error.code != 'cdm_302') rethrow;
      stdout.writeln('unlicensed_decrypt=kNoKey (expected)');
    } finally {
      await host.close();
    }
    stdout.writeln('native_process_closed');
  }
  // Parser must not modify the encrypted source.
  if (file.length != (await File(arguments[1]).length()))
    throw StateError('source changed');
  final output = Uint8List.fromList(file);
  audio.markClear(output);
  stdout.writeln(
    'container_rewrite_preserves_length=${output.length == file.length}',
  );
}
