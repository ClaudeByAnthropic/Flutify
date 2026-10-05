// Opt-in comparison only. A disposable installed browser uses the same service
// certificate, initialization data and Dart license client as the native host.
// No account tokens enter the page; no media or license payload is persisted.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'browser_output_trace.dart';

Future<String> probeBrowserLicense({
  required String executable,
  required Uint8List certificate,
  required Uint8List pssh,
  required Future<Uint8List> Function(Uint8List) postLicense,
}) => _probeBrowser(
  executable: executable,
  certificate: certificate,
  pssh: pssh,
  postLicense: postLicense,
);

// This diagnostic never updates the session or posts a license. Chromium's
// documented test feature switch is confined to this disposable browser.
Future<String> probeBrowserRequestMetadata({
  required String executable,
  required Uint8List certificate,
  required Uint8List pssh,
  required void Function(Uint8List) inspect,
  bool disableHostVerificationForTesting = false,
  void Function(Map<String, Object>)? outputProtectionTrace,
}) => _probeBrowser(
  executable: executable,
  certificate: certificate,
  pssh: pssh,
  inspect: inspect,
  disableHostVerificationForTesting: disableHostVerificationForTesting,
  outputProtectionTrace: outputProtectionTrace,
);

Future<String> _probeBrowser({
  required String executable,
  required Uint8List certificate,
  required Uint8List pssh,
  Future<Uint8List> Function(Uint8List)? postLicense,
  void Function(Uint8List)? inspect,
  bool disableHostVerificationForTesting = false,
  void Function(Map<String, Object>)? outputProtectionTrace,
}) async {
  final metadataOnly = inspect != null;
  if (disableHostVerificationForTesting && !metadataOnly) {
    throw ArgumentError('host_verification_switch_requires_metadata_only');
  }
  final profile = await Directory.systemTemp.createTemp('flutify-cdm-compare-');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final result = Completer<String>();
  final nonce = List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  Process? browser;
  BrowserOutputTrace? trace;
  final subscription = server.listen((request) async {
    try {
      if (!request.uri.path.startsWith('/$nonce/')) {
        request.response.statusCode = 404;
        return;
      }
      switch (request.uri.path.substring(nonce.length + 2)) {
        case '':
          request.response.headers.contentType = ContentType.html;
          request.response.write(_page);
        case 'init':
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'certificate': base64Encode(certificate),
              'pssh': base64Encode(pssh),
              'metadataOnly': metadataOnly,
            }),
          );
        case 'license':
        case 'inspect':
          if (request.method != 'POST' ||
              request.uri.path.endsWith('/inspect') != metadataOnly) {
            request.response.statusCode = 405;
            return;
          }
          final bytes = BytesBuilder();
          await for (final chunk in request) {
            bytes.add(chunk);
            if (bytes.length > 1024 * 1024) throw StateError('request_limit');
          }
          try {
            if (metadataOnly) {
              inspect(bytes.takeBytes());
              // Leave this live CDM instance available briefly for an external
              // observer to verify the loaded DLL version. No license is sent.
              await Future<void>.delayed(const Duration(seconds: 1));
              if (!result.isCompleted) result.complete('metadata_collected');
            } else {
              request.response.add(await postLicense!(bytes.takeBytes()));
            }
          } catch (_) {
            request.response.statusCode = 502;
          }
        case 'result':
          final status = request.uri.queryParameters['status'];
          const allowed = {
            'usable',
            'license_rejected',
            'keys_unusable',
            'eme_unavailable',
            'certificate_rejected',
            'session_failed',
          };
          if (!result.isCompleted && allowed.contains(status)) {
            result.complete(status!);
          }
        default:
          request.response.statusCode = 404;
      }
    } catch (_) {
      request.response.statusCode = 500;
    } finally {
      await request.response.close();
    }
  });
  try {
    browser = await Process.start(executable, [
      '--headless=new',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-background-networking',
      '--disable-sync',
      '--no-proxy-server',
      if (outputProtectionTrace != null) '--remote-debugging-port=0',
      if (disableHostVerificationForTesting)
        '--disable-features=CdmHostVerification',
      '--user-data-dir=${profile.path}',
      if (outputProtectionTrace == null)
        'http://127.0.0.1:${server.port}/$nonce/',
    ]);
    browser.stdout.drain<void>().ignore();
    browser.stderr.drain<void>().ignore();
    if (outputProtectionTrace != null) {
      trace = await BrowserOutputTrace.start(profile, outputProtectionTrace);
      await trace.navigate('http://127.0.0.1:${server.port}/$nonce/');
    }
    final status = await result.future.timeout(
      const Duration(seconds: 40),
      onTimeout: () => 'browser_timeout',
    );
    await trace?.stop();
    return status;
  } finally {
    try {
      await trace?.close();
    } catch (_) {
      // Continue terminating the disposable browser even if tracing disconnected.
    }
    if (browser != null) {
      // Terminate only this disposable browser and its children.
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${browser.pid}', '/T', '/F']);
      } else {
        browser.kill();
      }
      await browser.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
    await subscription.cancel();
    await server.close(force: true);
    try {
      final target = await profile.resolveSymbolicLinks();
      final temp = await Directory.systemTemp.resolveSymbolicLinks();
      if (p.equals(p.dirname(target), temp) &&
          p.basename(target).startsWith('flutify-cdm-compare-')) {
        await Directory(target).delete(recursive: true);
      }
    } on FileSystemException {
      /* Browser shutdown may still hold files. */
    }
  }
}

const _page =
    r'''<!doctype html><meta charset="utf-8"><title>CDM compatibility check</title>
<script>
(async () => {
  const report = status => fetch('result?status=' + status);
  const decode = value => Uint8Array.from(atob(value), c => c.charCodeAt(0));
  let stage = 'eme_unavailable';
  let session;
  try {
    const data = await (await fetch('init')).json();
    const access = await navigator.requestMediaKeySystemAccess('com.widevine.alpha', [{
      initDataTypes: ['cenc'],
      audioCapabilities: [{contentType: 'audio/mp4; codecs="mp4a.40.2"'}],
      distinctiveIdentifier: 'not-allowed', persistentState: 'not-allowed',
      sessionTypes: ['temporary'],
    }]);
    const keys = await access.createMediaKeys();
    stage = 'certificate_rejected';
    if (!await keys.setServerCertificate(decode(data.certificate))) throw Error();
    stage = 'session_failed';
    session = keys.createSession('temporary');
    session.addEventListener('keystatuseschange', () => {
      const statuses = [...session.keyStatuses.values()];
      if (statuses.includes('usable')) report('usable');
      else if (statuses.length && !statuses.includes('status-pending')) report('keys_unusable');
    });
    session.addEventListener('message', async event => {
      try {
        if (data.metadataOnly) {
          await fetch('inspect', {method: 'POST', body: event.message});
          return;
        }
        const response = await fetch('license', {method: 'POST', body: event.message});
        if (!response.ok) { await report('license_rejected'); return; }
        await session.update(await response.arrayBuffer());
      } catch (_) { await report('session_failed'); }
    });
    await session.generateRequest('cenc', decode(data.pssh));
  } catch (_) { await report(stage); }
})();
</script>''';
