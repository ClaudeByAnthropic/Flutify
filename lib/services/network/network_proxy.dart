import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'proxy_endpoint.dart';
import 'proxy_mode.dart';
import 'proxy_tunnel.dart';
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
/// 本机回环地址（localhost / 127.x / ::1）始终直连：播放器经本机端口读取解密后的音频；
/// 网易云音乐（[alwaysDirectDomains]）也始终直连，原因见该常量。
class NetworkProxy {
  NetworkProxy({
    Future<SystemProxySettings> Function()? systemReader,
    Future<String> Function()? countryReader,
  }) : _systemReader = systemReader ?? SystemProxyReader.read,
       _countryReader = countryReader;

  /// App 使用的唯一实例（main 里按偏好配置，设置页修改时更新）。
  static final NetworkProxy instance = NetworkProxy();

  static const Duration systemTtl = Duration(seconds: 30);

  /// 无论哪种代理模式都直连的域名（连同其子域名）：网易云音乐（歌词译文）。
  ///
  /// 国内用户为了 Spotify 通常开着海外代理（Clash 等系统代理，或这里的手动代理），网易云的请求
  /// 跟着从海外出口出去会被风控拒绝（业务码 -460 / -462 等）。网易云在国内本来就能直连，走用户
  /// 自己的网络即可，不必伪造来源 IP。只认 music.163.com，163.com 的其他服务照常按代理设置选路。
  static const Set<String> alwaysDirectDomains = {'music.163.com'};

  /// [host] 是否命中 [alwaysDirectDomains]（域名本身或其子域名）。
  static bool isAlwaysDirect(String host) {
    final h = host.toLowerCase();
    return alwaysDirectDomains.any((d) => h == d || h.endsWith('.$d'));
  }

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
  String _manualUsername = '';
  String _manualPassword = '';
  SystemProxySettings _system = SystemProxySettings.none;
  DateTime? _systemReadAt;
  Future<void>? _refreshing;

  ProxyMode get mode => _mode;
  ProxyEndpoint? get manual => _manual;

  /// 手动代理的认证用户名 / 密码（[ProxyMode.manual] 的代理要求认证时才用，空表示无认证）。
  /// 由 [configure] 配置，密码本身不持久化在本类，来自 StorageService。
  String get manualUsername => _manualUsername;
  String get manualPassword => _manualPassword;

  /// 手动代理是否配置了凭据（用户名或密码任填一项即生效：有的代理只用用户名当令牌）。
  bool get manualHasCredentials =>
      _manualUsername.isNotEmpty || _manualPassword.isNotEmpty;

  /// 最近一次读到的系统代理（设置页展示用）。
  SystemProxySettings get system => _system;

  /// 按偏好更新策略；切到「跟随系统」时立即重读一次系统代理。
  ///
  /// 参数取自 AppPreferences + StorageService（本类不直接依赖 models / 存储，保持纯 Dart
  /// 以便命令行探针复用）；[proxyUsername] / [proxyPassword] 是手动代理的 Basic 认证凭据，可留空。
  Future<void> configure({
    required ProxyMode mode,
    String proxyHost = '',
    int proxyPort = 0,
    SpotifyGateway gateway = const SpotifyGateway(),
    String proxyUsername = '',
    String proxyPassword = '',
  }) {
    final changed =
        _gatewaySettings != gateway ||
        _mode != mode ||
        _manual?.toString() !=
            (proxyPort > 0 ? '$proxyHost:$proxyPort' : null) ||
        _manualUsername != proxyUsername ||
        _manualPassword != proxyPassword;
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
    _manualUsername = proxyUsername;
    _manualPassword = proxyPassword;
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
    if (_isLoopback(host) || isAlwaysDirect(host)) return null;
    switch (_mode) {
      case ProxyMode.none:
        return null;
      case ProxyMode.manual:
        return _manual;
      case ProxyMode.system:
        final readAt = _systemReadAt;
        if (readAt == null || DateTime.now().difference(readAt) > systemTtl) {
          unawaited(refreshSystem());
        }
        if (_system.bypasses(host)) return null;
        return uri.scheme == 'http' || uri.scheme == 'ws'
            ? _system.http
            : _system.https;
    }
  }

  /// HTTPS / WSS 经需要认证的手动代理时，由 [ProxyHttpOverrides] 装的 connectionFactory
  /// 自建 CONNECT 隧道，dart:io 只当它是直连（[findProxy] 返回 DIRECT）。
  ///
  /// 凭据不能交给 dart:io：无论 `PROXY user:pass@…` 还是 addProxyCredentials，它都会把
  /// Proxy-Authorization 也加到隧道**里面**发给目标服务器的请求上，等于把代理密码发给
  /// Spotify、网易云等第三方。自建隧道时凭据只出现在发给代理的 CONNECT 上。
  bool tunnelsSecure(Uri uri) =>
      _mode == ProxyMode.manual &&
      manualHasCredentials &&
      (uri.isScheme('https') || uri.isScheme('wss')) &&
      endpointFor(uri) != null;

  /// 供 [HttpClient.findProxy] 使用，须与 [ProxyHttpOverrides] 的 connectionFactory 配套：
  /// 需要认证的 HTTPS 在这里返回 DIRECT，实际经代理隧道（见 [tunnelsSecure]）。
  String findProxy(Uri uri) {
    final endpoint = endpointFor(uri);
    if (endpoint == null || tunnelsSecure(uri)) return 'DIRECT';
    // 明文 HTTP 经认证代理：凭据嵌进代理串（`PROXY user:pass@host:port`），dart:io 随请求带上
    // Proxy-Authorization。明文请求本来就是发给代理的，代理消费这个逐跳头，不会到达目标；
    // 也省掉每个请求先吃一次 407 质询的往返。
    // 不用 authenticateProxy + addProxyCredentials：dart:io 的 Basic 代理凭据
    // 永不置 used 标记，密码错误时 407 → 自动重试会无限循环（实测 5 秒 2.8 万个请求）；
    // 嵌入凭据在密码错误时代理回 407，错误直接抛给调用方，清晰可查。
    if (_mode == ProxyMode.manual &&
        manualHasCredentials &&
        _embeddableInProxyString(_manualUsername, _manualPassword)) {
      return 'PROXY $_manualUsername:$_manualPassword@$endpoint';
    }
    return 'PROXY $endpoint';
  }

  /// 用户名是否可用于 Basic 认证：按 RFC 7617 不能含 `:`（它是用户名与密码的分隔符）。
  static bool isValidUsername(String user) => !user.contains(':');

  /// 凭据能否无损嵌入 findProxy 的代理串（只影响明文 HTTP；HTTPS 走自建隧道，任意字符都行）。
  ///
  /// 按 dart:io 的解析：整串按 `;` 分段，最后一个 `@` 之前是身份，按第一个 `:` 拆出用户名与密码
  /// 并各自 trim，两者都不能为空。不满足时明文 HTTP 退化为不带凭据；HTTPS / WSS 仍由自建
  /// CONNECT 隧道带上原始凭据。
  static bool _embeddableInProxyString(String user, String pass) {
    bool clean(String s) =>
        s.isNotEmpty &&
        s.trim() == s &&
        !s.contains(';') &&
        !s.contains(RegExp(r'[\x00-\x1f\x7f]'));
    return clean(user) && clean(pass) && isValidUsername(user);
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

  /// 自建隧道（CONNECT 加 TLS 握手）在客户端没设 connectionTimeout 时的上限。
  static const Duration tunnelTimeout = Duration(seconds: 30);

  /// 在创建任何网络客户端之前调用。
  static void install(NetworkProxy proxy) =>
      HttpOverrides.global = ProxyHttpOverrides(proxy);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    return GatewayHttpClient(
      client
        ..findProxy = proxy.findProxy
        ..connectionFactory = (uri, proxyHost, proxyPort) =>
            _connect(client, context, uri, proxyHost, proxyPort),
      () => proxy.gateway,
    );
  }

  /// 装了 connectionFactory 后 dart:io 不再自己建连，其余情况照它原来的方式建：
  /// - 经代理（dart:io 自己发 CONNECT / 明文代理请求）：只连到代理；
  /// - 直连：明文 TCP，HTTPS 在这里完成 TLS（与 dart:io 默认路径一样用客户端的 SecurityContext）；
  /// - [NetworkProxy.tunnelsSecure]：先经 [ProxyTunnel] 建带认证的 CONNECT 隧道，再在隧道上做 TLS。
  Future<ConnectionTask<Socket>> _connect(
    HttpClient client,
    SecurityContext? context,
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) {
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }
    final secure = uri.isScheme('https') || uri.isScheme('wss');
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (secure ? 443 : 80);
    if (!secure) return Socket.startConnect(host, port);
    if (!proxy.tunnelsSecure(uri)) {
      return SecureSocket.startConnect(host, port, context: context);
    }

    Socket? tunnelSocket;
    var cancelled = false;
    final socket = () async {
      final tunnel = await ProxyTunnel.connect(
        host,
        port,
        timeout: client.connectionTimeout ?? tunnelTimeout,
        proxy: proxy,
        useGateway: false,
      );
      final tcpSocket = tunnel.socket.tcpSocket;
      if (tcpSocket == null) {
        tunnel.socket.destroy();
        throw const ProxyTunnelException('Expected a TCP proxy tunnel');
      }
      tunnelSocket = tcpSocket;
      if (cancelled) {
        tunnel.socket.destroy();
        throw const SocketException('连接已取消');
      }
      // 隧道建立后目标服务器在 ClientHello 之前不会发数据，ProxyTunnel 没有缓冲任何属于 TLS 的字节
      return SecureSocket.secure(tcpSocket, host: host, context: context);
    }();
    return Future.value(
      ConnectionTask.fromSocket(socket, () {
        cancelled = true;
        tunnelSocket?.destroy();
      }),
    );
  }
}
