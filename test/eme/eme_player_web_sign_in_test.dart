import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// 反代失败何时提示「重新 Web 登录」：依赖 Web token 的那一路被拒（401/403）或根本没有 sp_dc。
/// FairPlay 的证书请求也带 Web token（原生页面先取证书），Widevine 的证书只用 client-token。
void main() {
  late Directory tmp;
  late File m4a;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('eme_sign_in_test');
    m4a = File('${tmp.path}/a.m4a')..writeAsBytesSync([0]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// 用 serveHlsForNative 装好反代（不依赖 WebView），返回本地 license 地址。
  Future<String> serve(
    EmePlayer p, {
    Future<Uint8List> Function(Uint8List)? license,
    Future<Uint8List> Function()? cert,
  }) async {
    final r = await p.serveHlsForNative(
      m4a: m4a,
      m3u8: '#EXTM3U',
      licensePoster: license ?? (_) async => Uint8List(0),
      certFetcher: cert ?? () async => Uint8List(0),
    );
    return r.licenseUrl;
  }

  Future<int> request(String method, String url) async {
    final c = HttpClient();
    try {
      final req = await c.openUrl(method, Uri.parse(url));
      if (method == 'POST') req.add([1, 2, 3]);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      c.close(force: true);
    }
  }

  test('FairPlay：证书阶段 Web token 被拒，提示重新 Web 登录', () async {
    final p = EmePlayer()..fairPlayModeForTesting = true;
    addTearDown(p.dispose);
    final licenseUrl = await serve(
      p,
      cert: () async => throw StateError('铸造 Web token 失败：HTTP 401 {}'),
    );
    expect(
      await request('GET', licenseUrl.replaceFirst('/license', '/cert')),
      500,
    );
    expect(p.lastError?.webSignInSuggested, isTrue);
  });

  test('Widevine：证书只用 client-token，401 不当作 Web 登录失效', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    final licenseUrl = await serve(
      p,
      cert: () async =>
          throw StateError('license application-certificate 失败：HTTP 401'),
    );
    expect(
      await request('GET', licenseUrl.replaceFirst('/license', '/cert')),
      500,
    );
    expect(p.lastError, isNotNull);
    expect(p.lastError!.webSignInSuggested, isFalse);
  });

  test('从没完成 Web 登录（缺 sp_dc）也提示重新 Web 登录', () async {
    final p = EmePlayer();
    addTearDown(p.dispose);
    final licenseUrl = await serve(
      p,
      license: (_) async => throw StateError('缺少 sp_dc（需先完成 Web 登录）'),
    );
    expect(await request('POST', licenseUrl), 500);
    expect(p.lastError?.webSignInSuggested, isTrue);
  });
}
