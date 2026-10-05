// Opt-in integration diagnostic. Run with flutter test and explicitly provide
// FLUTIFY_CDM_CHECK_PREFS, FLUTIFY_CDM_CHECK_MEDIA, FLUTIFY_CDM_CHECK_HELPER.
// Defaults to metadata only; FLUTIFY_CDM_CHECK_METADATA_ONLY=0 enables licenses.
// Preferences are read once and cloned into a memory-only store: token refreshes
// cannot overwrite the running app's session. No plaintext media is saved.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutify_app/services/audio/audio_engine.dart';
import 'package:flutify_app/services/auth/spotify_auth_service.dart';
import 'package:flutify_app/services/auth/web_token_service.dart';
import 'package:flutify_app/services/eme/license_client.dart';
import 'package:flutify_app/services/eme/cenc_audio.dart';
import 'package:flutify_app/services/eme/widevine_init_data.dart';
import 'package:flutify_app/services/eme/windows_cdm_process.dart';
import 'package:flutify_app/services/eme/windows_native_decryptor.dart';
import 'package:flutify_app/services/network/network_proxy.dart';
import 'package:flutify_app/services/protocol/track_playback_media.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_license_probe.dart';
import 'license_request_metadata.dart';

class StatusClient extends http.BaseClient {
  StatusClient({this.metadataOnly = false});

  final bool metadataOnly;
  final inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (metadataOnly &&
        request.url.path == '/widevine-license/v1/audio/license') {
      throw StateError('license_request_blocked_in_metadata_mode');
    }
    final response = await inner.send(request);
    // Only fixed endpoint name and numeric status, never headers/URL/body.
    if (request.url.path.startsWith('/widevine-license/')) {
      print(
        'widevine_${request.url.pathSegments.last} http=${response.statusCode}',
      );
      if (response.statusCode != 200) {
        final bytes = await response.stream.toBytes();
        final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
        // Report fixed diagnostic categories only, never opaque server text.
        final categories = [
          for (final word in [
            'vmp',
            'verification',
            'signature',
            'revoked',
            'expired',
            'token',
            'unauthorized',
            'forbidden',
          ])
            if (text.contains(word)) word,
        ];
        print('license_rejection bytes=${bytes.length} categories=$categories');
        return http.StreamedResponse(
          Stream.value(bytes),
          response.statusCode,
          headers: response.headers,
          request: response.request,
          reasonPhrase: response.reasonPhrase,
          contentLength: bytes.length,
        );
      }
    } else if (request.url.host == 'open.spotify.com' &&
        request.url.path == '/api/token') {
      print('web_token http=${response.statusCode}');
      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();
        final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final anonymous = body['isAnonymous'];
        print(
          'web_token_anonymous=${anonymous is bool ? anonymous : 'unknown'}',
        );
        return http.StreamedResponse(
          Stream.value(bytes),
          response.statusCode,
          headers: response.headers,
          request: response.request,
          contentLength: bytes.length,
        );
      }
    }
    return response;
  }

  @override
  void close() => inner.close();
}

class _MetadataCollected implements Exception {
  const _MetadataCollected();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final metadataOnly = env['FLUTIFY_CDM_CHECK_METADATA_ONLY'] != '0';
  test(
    metadataOnly
        ? 'local CDM request metadata without license requests'
        : 'real session license and native full-file decrypt',
    () async {
      final oldPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message?.startsWith('[native-wv]') ?? false) print(message);
      };
      addTearDown(() => debugPrint = oldPrint);
      var stage = 'preferences';
      NativeMemoryAudio? memory;
      WindowsNativeDecryptor? decryptor;
      StatusClient? client;
      try {
        final raw =
            jsonDecode(
                  await File(env['FLUTIFY_CDM_CHECK_PREFS']!).readAsString(),
                )
                as Map<String, dynamic>;
        // This opt-in flutter test lives outside test/ to avoid normal CI runs.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({
          for (final entry in raw.entries)
            if (entry.key.startsWith('flutter.'))
              entry.key.substring(8): entry.value,
        });
        final storage = StorageService(await SharedPreferences.getInstance());
        if (storage.spDc.isEmpty) {
          throw const CdmException('web_session_missing');
        }
        final prefs = AppPreferences.decode(storage.preferencesJson);
        stage = 'network';
        ProxyHttpOverrides.install(NetworkProxy.instance);
        await NetworkProxy.instance.configure(
          mode: prefs.proxyMode,
          proxyHost: prefs.proxyHost,
          proxyPort: prefs.proxyPort,
          gateway: prefs.gateway,
          proxyUsername: prefs.proxyUsername,
          proxyPassword: storage.proxyPassword,
        );
        client = StatusClient(metadataOnly: metadataOnly);
        final web = WebTokenService(storage, client);
        final auth = SpotifyAuthService(storage);
        var manifest = '';
        if (env['FLUTIFY_CDM_CHECK_FETCH_MANIFEST'] == '1') {
          stage = 'manifest';
          final fileId = File(
            env['FLUTIFY_CDM_CHECK_MEDIA']!,
          ).uri.pathSegments.last.split('.').first;
          if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(fileId)) {
            throw const CdmException('invalid_media_file_id');
          }
          manifest = await fetchHlsManifest(
            fileId,
            headers: () async {
              await auth.ensureAccessToken();
              return {
                'Authorization': 'Bearer ${storage.accessToken}',
                'client-token': await auth.ensureClientToken(),
                'User-Agent': 'Spotify/130100234 Win32_x86_64/0 (PC desktop)',
                'app-platform': 'Win32_x86_64',
                'spotify-app-version': '1.3.1.234.g59d6bf59',
              };
            },
            client: client,
          );
          print('fresh_manifest_loaded=true');
        }
        stage = 'web_token';
        final useCachedToken =
            env['FLUTIFY_CDM_CHECK_REFRESH_TOKEN'] != '1' &&
            storage.webAccessToken.isNotEmpty &&
            storage.webAccessTokenExpiry >
                DateTime.now().millisecondsSinceEpoch + 60000;
        final token = metadataOnly
            ? ''
            : useCachedToken
            ? storage.webAccessToken
            : (await web.mintAccessToken()).token;
        if (!metadataOnly) print('web_token_refreshed=${!useCachedToken}');
        final license = WidevineLicenseClient(
          webToken: () async => token,
          clientToken: auth.ensureClientToken,
          client: client,
        );
        stage = 'certificate';
        final certificate = await license.fetchCert();
        print('fresh_certificate bytes=${certificate.length}');
        final pssh =
            widevinePsshFromHls(manifest) ??
            CencAudio.parse(
              await File(env['FLUTIFY_CDM_CHECK_MEDIA']!).readAsBytes(),
            ).pssh;
        void inspect(String host, Uint8List request) {
          print(
            '$host request_metadata=${jsonEncode(licenseRequestMetadata(request, pssh: pssh, certificate: certificate))}',
          );
        }

        Future<WindowsCdmProcess> startNativeHost() async {
          final host = await WindowsCdmProcess.start(
            helper: env['FLUTIFY_CDM_CHECK_HELPER'],
            library: env['FLUTIFY_CDM_CHECK_LIBRARY'],
          );
          if (env['FLUTIFY_CDM_CHECK_SETTLE'] == '1') {
            // The helper keeps pumping CDM timers while it awaits pipe input.
            // Tests whether asynchronous verification is still settling.
            await Future<void>.delayed(const Duration(seconds: 5));
            print('native_post_initialize_wait_ms=5000');
          }
          return host;
        }

        if (metadataOnly) {
          if (env['FLUTIFY_CDM_CHECK_BROWSER'] case final browser?) {
            final traceOutput = env['FLUTIFY_CDM_CHECK_OUTPUT_TRACE'] == '1';
            for (final (variant, disableVerification) in [
              ('browser_default', false),
              if (!traceOutput) ...[
                ('browser_verification_disabled', true),
                ('browser_verification_restored', false),
              ],
            ]) {
              stage = variant;
              final status = await probeBrowserRequestMetadata(
                executable: browser,
                certificate: certificate,
                pssh: pssh,
                inspect: (request) => inspect(variant, request),
                disableHostVerificationForTesting: disableVerification,
                outputProtectionTrace: traceOutput
                    ? (value) => print(
                        'browser_output_protection=${jsonEncode(value)}',
                      )
                    : null,
              );
              print('$variant status=$status license_requests_sent=0');
              expect(status, 'metadata_collected');
            }
          }
          stage = 'native_metadata';
          final host = await startNativeHost();
          try {
            await host.open(
              certificate: certificate,
              pssh: pssh,
              postLicense: (request) async {
                inspect('native', request);
                throw const _MetadataCollected();
              },
            );
            fail('metadata_request_missing');
          } on _MetadataCollected {
            print('metadata_only_complete license_requests_sent=0');
          } finally {
            await host.close();
          }
          return;
        }

        if (env['FLUTIFY_CDM_CHECK_BROWSER'] case final browser?) {
          stage = 'browser_comparison';
          final status = await probeBrowserLicense(
            executable: browser,
            certificate: certificate,
            pssh: pssh,
            postLicense: (request) async {
              inspect('browser', request);
              return license.postLicense(request);
            },
          );
          print('browser_same_session=$status');
        }
        decryptor = WindowsNativeDecryptor(
          startHost: startNativeHost,
          fetchCertificate: () async {
            stage = 'cdm_session';
            return certificate;
          },
          postLicense: (request) async {
            stage = 'license_http';
            inspect('native', request);
            final bytes = await license.postLicense(request);
            print('license_response bytes=${bytes.length}');
            stage = 'cdm_license_update_or_decrypt';
            return bytes;
          },
        );
        stage = 'native_start';
        memory = await decryptor.decrypt(
          EmeTrackContent(
            fileIdHex: '0000000000000000000000000000000000000000',
            m4aPath: env['FLUTIFY_CDM_CHECK_MEDIA']!,
            m3u8: manifest,
          ),
        );
        expect(memory.length, greaterThan(0));
        print('native_full_decrypt_pass bytes=${memory.length}');
      } catch (error) {
        fail(
          'native_check_failed stage=$stage code=${error is CdmException
              ? error.code
              : error is LicenseHttpException
              ? error.code
              : error.runtimeType}',
        );
      } finally {
        memory?.dispose();
        decryptor?.cancel();
        client?.close();
        HttpOverrides.global = null;
      }
    },
    skip: !Platform.isWindows || env['FLUTIFY_CDM_CHECK_PREFS'] == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
