import 'dart:async';
import 'dart:io';

import 'proxy_endpoint.dart';
import 'proxy_mode.dart';
import 'system_proxy.dart';

/// 全局网络代理策略（设置 →「网络」）：所有 HTTP / WebSocket 请求与接入点的 TCP 连接都按它选路。
///
/// - [ProxyMode.system]：跟随系统代理（[SystemProxyReader]），读到的结果缓存 [systemTtl]，
///   过期后在后台重读，所以在 Clash 等工具里开关系统代理，几十秒内就会生效，不必重启；
/// - [ProxyMode.none]：一律直连；
/// - [ProxyMode.manual]：一律走手动填写的 HTTP 代理（地址无效时直连）。
///
/// 本机回环地址（localhost / 127.x / ::1）始终直连：播放器经本机端口读取解密后的音频。
class NetworkProxy {
  NetworkProxy({Future<SystemProxySettings> Function()? systemReader})
    : _systemReader = systemReader ?? SystemProxyReader.read;

  /// App 使用的唯一实例（main 里按偏好配置，设置页修改时更新）。
  static final NetworkProxy instance = NetworkProxy();

  static const Duration systemTtl = Duration(seconds: 30);

  final Future<SystemProxySettings> Function() _systemReader;

  ProxyMode _mode = ProxyMode.system;
  ProxyEndpoint? _manual;
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
  }) {
    _mode = mode;
    _manual = proxyPort > 0
        ? ProxyEndpoint.tryParse('$proxyHost:$proxyPort')
        : null;
    return _mode == ProxyMode.system ? refreshSystem() : Future.value();
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
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = proxy.findProxy;
}
