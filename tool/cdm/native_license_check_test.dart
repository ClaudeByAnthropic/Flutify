// Opt-in integration diagnostic. Run with flutter test and explicitly provide
// FLUTIFY_CDM_CHECK_PREFS, FLUTIFY_CDM_CHECK_MEDIA, FLUTIFY_CDM_CHECK_HELPER.
// Preferences are read once and cloned into a memory-only store: token refreshes
// cannot overwrite the running app's session. No plaintext media is saved.
import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutify_app/services/audio/audio_engine.dart';
import 'package:flutify_app/services/auth/spotify_auth_service.dart';
import 'package:flutify_app/services/auth/web_token_service.dart';
import 'package:flutify_app/services/eme/license_client.dart';
import 'package:flutify_app/services/eme/windows_cdm_process.dart';
import 'package:flutify_app/services/eme/windows_native_decryptor.dart';
import 'package:flutify_app/services/network/network_proxy.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StatusClient extends http.BaseClient {
  final inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    // Only fixed endpoint name and numeric status, never headers/URL/body.
    if (request.url.path.startsWith('/widevine-license/')) {
      print(
        'widevine_${request.url.pathSegments.last} http=${response.statusCode}',
      );
    } else if (request.url.host == 'open.spotify.com' &&
        request.url.path == '/api/token') {
      print('web_token http=${response.statusCode}');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  test(
    'real session license and native full-file decrypt',
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
        if (storage.spDc.isEmpty)
          throw const CdmException('web_session_missing');
        final prefs = AppPreferences.decode(storage.preferencesJson);
        stage = 'network';
        ProxyHttpOverrides.install(NetworkProxy.instance);
        await NetworkProxy.instance.configure(
          mode: prefs.proxyMode,
          proxyHost: prefs.proxyHost,
          proxyPort: prefs.proxyPort,
          gateway: prefs.gateway,
        );
        client = StatusClient();
        final web = WebTokenService(storage, client);
        final auth = SpotifyAuthService(storage);
        stage = 'web_token';
        final token =
            storage.webAccessToken.isNotEmpty &&
                storage.webAccessTokenExpiry >
                    DateTime.now().millisecondsSinceEpoch + 60000
            ? storage.webAccessToken
            : (await web.mintAccessToken()).token;
        print('web_token_fresh=true');
        final license = WidevineLicenseClient(
          webToken: () async => token,
          clientToken: auth.ensureClientToken,
          client: client,
        );
        decryptor = WindowsNativeDecryptor(
          startHost: () => WindowsCdmProcess.start(
            helper: env['FLUTIFY_CDM_CHECK_HELPER'],
            library: env['FLUTIFY_CDM_CHECK_LIBRARY'],
          ),
          fetchCertificate: () async {
            stage = 'certificate';
            final bytes = await license.fetchCert();
            print('fresh_certificate bytes=${bytes.length}');
            stage = 'cdm_session';
            return bytes;
          },
          postLicense: (request) async {
            stage = 'license_http';
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
            m3u8: '',
          ),
        );
        expect(memory.length, greaterThan(0));
        print('native_full_decrypt_pass bytes=${memory.length}');
      } catch (error) {
        fail(
          'native_check_failed stage=$stage code=${error is CdmException ? error.code : error.runtimeType}',
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
