import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutify_app/services/network/network_proxy.dart';
import 'package:flutify_app/services/network/proxy_endpoint.dart';
import 'package:flutify_app/services/network/proxy_tunnel.dart';
import 'package:flutify_app/services/network/system_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 网络代理：系统代理解析、绕过规则、按模式选路、CONNECT 隧道。
void main() {
  group('ProxyEndpoint.tryParse', () {
    test('accepts host:port, scheme prefix and IPv6', () {
      expect(ProxyEndpoint.tryParse('127.0.0.1:7890'), const ProxyEndpoint('127.0.0.1', 7890));
      expect(ProxyEndpoint.tryParse(' http://proxy.lan:8080/ '), const ProxyEndpoint('proxy.lan', 8080));
      expect(ProxyEndpoint.tryParse('[::1]:7890')?.toString(), '[::1]:7890');
      expect(ProxyEndpoint.tryParse('http://proxy:80'), const ProxyEndpoint('proxy', 80));
    });

    test('rejects missing or invalid port', () {
      expect(ProxyEndpoint.tryParse(''), isNull);
      expect(ProxyEndpoint.tryParse('127.0.0.1'), isNull);
      expect(ProxyEndpoint.tryParse('127.0.0.1:99999'), isNull);
    });
  });

  group('SystemProxySettings', () {
    test('parses reg query output with a single server', () {
      const output =
          '\r\nHKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\r\n'
          '    ProxyEnable    REG_DWORD    0x1\r\n'
          '    ProxyServer    REG_SZ    127.0.0.1:7890\r\n'
          '    ProxyOverride    REG_SZ    localhost;127.*;*.corp.example;<local>\r\n';
      final s = SystemProxyReader.parseRegQuery(output);
      expect(s.http, const ProxyEndpoint('127.0.0.1', 7890));
      expect(s.https, const ProxyEndpoint('127.0.0.1', 7890));
      expect(s.bypasses('git.corp.example'), isTrue);
      expect(s.bypasses('intranet'), isTrue, reason: '<local> = 不带点的主机名');
      expect(s.bypasses('api.spotify.com'), isFalse);
    });

    test('disabled proxy is treated as none', () {
      const output = '    ProxyEnable    REG_DWORD    0x0\r\n    ProxyServer    REG_SZ    127.0.0.1:7890\r\n';
      expect(SystemProxyReader.parseRegQuery(output).isEmpty, isTrue);
    });

    test('per-protocol server list; socks entry is ignored', () {
      final s = SystemProxySettings.fromWindows(
        enabled: true,
        server: 'http=10.0.0.1:80;https=10.0.0.1:443;socks=10.0.0.1:1080',
      );
      expect(s.http, const ProxyEndpoint('10.0.0.1', 80));
      expect(s.https, const ProxyEndpoint('10.0.0.1', 443));
    });

    test('environment variables with leading-dot no_proxy', () {
      final s = SystemProxySettings.fromEnvironment({
        'HTTPS_PROXY': 'http://p:3128',
        'no_proxy': '.internal,example.org',
      });
      expect(s.https, const ProxyEndpoint('p', 3128));
      expect(s.http, isNull);
      expect(s.bypasses('a.internal'), isTrue);
      expect(s.bypasses('internal'), isTrue);
      expect(s.bypasses('example.org'), isTrue);
      expect(s.bypasses('spotify.com'), isFalse);
    });
  });

  group('NetworkProxy', () {
    final spotify = Uri.parse('https://api.spotify.com/v1/me');
    final system = SystemProxySettings.fromWindows(enabled: true, server: '127.0.0.1:7890');

    test('modes route requests accordingly; loopback is always direct', () async {
      final proxy = NetworkProxy(systemReader: () async => system);
      await proxy.configure(AppPreferences.defaults);
      expect(proxy.findProxy(spotify), 'PROXY 127.0.0.1:7890');
      expect(proxy.findProxy(Uri.parse('http://127.0.0.1:51234/stream')), 'DIRECT');
      expect(proxy.findProxy(Uri.parse('http://localhost:51234/stream')), 'DIRECT');

      await proxy.configure(AppPreferences.defaults.copyWith(proxyMode: ProxyMode.none));
      expect(proxy.findProxy(spotify), 'DIRECT');

      await proxy.configure(
        AppPreferences.defaults.copyWith(proxyMode: ProxyMode.manual, proxyHost: '10.1.1.1', proxyPort: 8888),
      );
      expect(proxy.findProxy(spotify), 'PROXY 10.1.1.1:8888');
    });

    test('manual mode without a valid address connects directly', () async {
      final proxy = NetworkProxy(systemReader: () async => system);
      await proxy.configure(AppPreferences.defaults.copyWith(proxyMode: ProxyMode.manual));
      expect(proxy.findProxy(spotify), 'DIRECT');
    });

    test('concurrent system refreshes share a single read', () async {
      var reads = 0;
      final gate = Completer<void>();
      final proxy = NetworkProxy(
        systemReader: () async {
          reads++;
          await gate.future;
          return system;
        },
      );
      final a = proxy.refreshSystem();
      final b = proxy.refreshSystem();
      gate.complete();
      await Future.wait([a, b]);
      expect(reads, 1);
    });
  });

  group('ProxyTunnel', () {
    test('CONNECT through an HTTP proxy, then relays bytes both ways', () async {
      // 假代理：回 200 并在同一个包里带上目标服务器的首批字节，之后原样回显
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      server.listen((client) {
        var connected = false;
        client.listen((data) {
          if (!connected) {
            connected = true;
            requests.add(latin1.decode(data));
            client.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\nHELLO'));
          } else {
            client.add(data);
          }
        });
      });
      addTearDown(server.close);

      final proxy = NetworkProxy(systemReader: () async => SystemProxySettings.none);
      await proxy.configure(
        AppPreferences.defaults.copyWith(proxyMode: ProxyMode.manual, proxyHost: '127.0.0.1', proxyPort: server.port),
      );
      final conn = await ProxyTunnel.connect('ap.spotify.com', 4070, timeout: const Duration(seconds: 5), proxy: proxy);
      final received = StringBuffer();
      final done = Completer<void>();
      conn.input.listen((d) {
        received.write(latin1.decode(d));
        if (received.toString() == 'HELLOping') done.complete();
      });
      conn.socket.add(latin1.encode('ping'));
      await done.future.timeout(const Duration(seconds: 5));
      conn.socket.destroy();

      expect(requests.single, startsWith('CONNECT ap.spotify.com:4070 HTTP/1.1\r\n'));
    });

    test('a non-2xx proxy response fails the connection', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((client) {
        client.listen((_) => client.add(latin1.encode('HTTP/1.1 407 Proxy Authentication Required\r\n\r\n')));
      });
      addTearDown(server.close);

      final proxy = NetworkProxy(systemReader: () async => SystemProxySettings.none);
      await proxy.configure(
        AppPreferences.defaults.copyWith(proxyMode: ProxyMode.manual, proxyHost: '127.0.0.1', proxyPort: server.port),
      );
      await expectLater(
        ProxyTunnel.connect('ap.spotify.com', 4070, timeout: const Duration(seconds: 5), proxy: proxy),
        throwsA(isA<ProxyTunnelException>()),
      );
    });
  });
}
