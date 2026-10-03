import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'proxy_endpoint.dart';
import 'proxy_mode.dart';
import 'system_proxy.dart';
import 'spotify_gateway.dart';
import 'gateway_http_client.dart';

/// 全局网络代理策略（设置 →「网络」）：所有 HTTP / WebSocket 请求与接入点的 TCP 连接都按它选路。
///
/// - [ProxyMode.system]：跟随系统代理（[SystemProxyReader]），读到的结果缓存 [systemTtl]，
///   过期后在后台重读，所以在 Clash 等工具里开关系统代理，几十秒内就会生效，不必重启；
/// - [ProxyMode.none]：一律直连；
/// - [ProxyMode.manual]：一律走手动填写的 HTTP 代理（地址无效时直连）。
///
/// 本机回环地址（localhost / 127.x / ::1）始终直连：播放器经本机端口读取解密后的音频。
class NetworkProxy {
  NetworkProxy({
    Future<SystemProxySettings> Function()? systemReader,
    Future<String> Function()? countryReader,
  }) : _systemReader = systemReader ?? SystemProxyReader.read,
       _countryReader = countryReader;

  /// App 使用的唯一实例（main 里按偏好配置，设置页修改时更新）。
  static final NetworkProxy instance = NetworkProxy();

  static const Duration systemTtl = Duration(seconds: 30);

  final Future<SystemProxySettings> Function() _systemReader;
  final Future<String> Function()? _countryReader;
  final _gatewayChanges = StreamController<void>.broadcast(sync: true);
  Stream<void> get gatewayChanges => _gatewayChanges.stream;
  String? gatewayCountry;
  bool gatewayChecking = false;
  bool gatewayLookupFailed = false;
  SpotifyGateway _gatewaySettings = const SpotifyGateway();
  int _generation = 0;
  Future<void>? _countryCheck;
  bool _configured = false;

  ProxyMode _mode = ProxyMode.system;
  ProxyEndpoint? _manual;
  SpotifyGateway gateway = const SpotifyGateway();
  SystemProxySettings _system = SystemProxySettings.none;
  DateTime? _systemReadAt;
  Future<void>? _refreshing;

  ProxyMode get mode => _mode;
  ProxyEndpoint? get manual => _manual;

  /// 最近一次读到的系统代理（设置页展示用）。
  SystemProxySettings get system => _system;

  /// 按偏好更新策略；切到「跟随系统」时立即重读一次系统代理。
  ///
  /// 参数取自 AppPreferences（本类不直接依赖 models，保持纯 Dart 以便命令行探针复用）。
  Future<void> configure({
    required ProxyMode mode,
    String proxyHost = '',
    int proxyPort = 0,
    SpotifyGateway gateway = const SpotifyGateway(),
  }) {
    final changed =
        _gatewaySettings != gateway ||
        _mode != mode ||
        _manual?.toString() != (proxyPort > 0 ? '$proxyHost:$proxyPort' : null);
    if (changed) {
      _generation++;
      _countryCheck = null;
      gatewayChecking = false;
      gatewayLookupFailed = false;
    }
    // The stored manual choice is not overwritten by an automatic decision.
    final enabled = gateway.automatic && _configured
        ? this.gateway.enabled
        : gateway.enabled;
    _configured = true;
    _gatewaySettings = gateway;
    this.gateway = gateway.copyWith(enabled: enabled);
    _mode = mode;
    _manual = proxyPort > 0
        ? ProxyEndpoint.tryParse('$proxyHost:$proxyPort')
        : null;
    _gatewayChanges.add(null);
    return () async {
      if (_mode == ProxyMode.system) await refreshSystem();
      if (changed) await refreshGatewayCountry();
    }();
  }

  /// Recheck on startup, network change, resume and a periodic timer.
  /// Failed/obsolete lookups never change the last effective route.
  Future<void> refreshGatewayCountry({bool networkChanged = false}) {
    if (!_gatewaySettings.automatic || !_gatewaySettings.isValid) {
      return Future.value();
    }
    if (networkChanged) {
      _generation++;
      _countryCheck = null;
    }
    final generation = _generation;
    // Defer execution so even an immediately throwing reader clears the future.
    return _countryCheck ??= Future<void>(() => _checkCountry(generation));
  }

  Future<void> _checkCountry(int generation) async {
    if (generation != _generation) return;
    gatewayChecking = true;
    _gatewayChanges.add(null);
    try {
      if (_mode == ProxyMode.system) await refreshSystem();
      final country = await (_countryReader?.call() ?? _readCountry()).timeout(
        const Duration(seconds: 8),
      );
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(country) || country == 'XX') {
        throw const FormatException('Invalid country');
      }
      if (generation != _generation) return;
      final enabled = _gatewaySettings.enabledForCountry(country);
      gatewayCountry = country;
      gatewayLookupFailed = false;
      gateway = _gatewaySettings.copyWith(enabled: enabled);
    } catch (_) {
      if (generation == _generation) gatewayLookupFailed = true;
    } finally {
      if (generation == _generation) {
        gatewayChecking = false;
        _countryCheck = null;
        _gatewayChanges.add(null);
      }
    }
  }

  static String countryFromTrace(String trace) {
    final matches = RegExp(
      r'^loc=([A-Z]{2})\r?$',
      multiLine: true,
    ).allMatches(trace).toList();
    if (matches.length != 1 || matches.single.group(1) == 'XX') {
      throw const FormatException('Missing or invalid trace country');
    }
    return matches.single.group(1)!;
  }

  Future<String> _readCountry() async {
    // Bypass the Spotify gateway while honoring the selected forward proxy.
    final client = HttpClient()..findProxy = findProxy;
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.parse('https://cloudflare.com/cdn-cgi/trace'),
        );
        request.followRedirects = false;
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw const HttpException('Country lookup failed');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 16384)
            throw const FormatException('Trace too large');
        }
        return countryFromTrace(utf8.decode(bytes));
      })().timeout(const Duration(seconds: 8));
    } finally {
      client.close(force: true);
    }
  }

  /// 重新读取系统代理（并发调用合并为一次）。
  Future<void> refreshSystem() => _refreshing ??= () async {
    try {
      _system = await _systemReader();
      _systemReadAt = DateTime.now();
    } finally {
      _refreshing = null;
    }
  }();

  /// [uri] 应经过的代理；null 表示直连。
  ProxyEndpoint? endpointFor(Uri uri) {
    final host = uri.host;
    if (_isLoopback(host)) return null;
    switch (_mode) {
      case ProxyMode.none:
        return null;
      case ProxyMode.manual:
        return _manual;
      case ProxyMode.system:
        final readAt = _systemReadAt;
        if (readAt == null || DateTime.now().difference(readAt) > systemTtl)
          unawaited(refreshSystem());
        if (_system.bypasses(host)) return null;
        return uri.scheme == 'http' || uri.scheme == 'ws'
            ? _system.http
            : _system.https;
    }
  }

  /// 供 [HttpClient.findProxy] 使用。
  String findProxy(Uri uri) {
    final endpoint = endpointFor(uri);
    return endpoint == null ? 'DIRECT' : 'PROXY $endpoint';
  }

  static bool _isLoopback(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '::1' || h == '[::1]') return true;
    return InternetAddress.tryParse(h)?.isLoopback ?? false;
  }
}

/// 让进程内所有 [HttpClient]（package:http、WebSocket）都按 [NetworkProxy] 选路。
class ProxyHttpOverrides extends HttpOverrides {
  final NetworkProxy proxy;

  ProxyHttpOverrides(this.proxy);

  /// 在创建任何网络客户端之前调用。
  static void install(NetworkProxy proxy) =>
      HttpOverrides.global = ProxyHttpOverrides(proxy);

  @override
  HttpClient createHttpClient(SecurityContext? context) => GatewayHttpClient(
    super.createHttpClient(context)..findProxy = proxy.findProxy,
    () => proxy.gateway,
  );
}
