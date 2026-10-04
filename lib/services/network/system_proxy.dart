import 'dart:io';

import 'proxy_endpoint.dart';
import 'system_proxy_macos.dart';

/// 系统代理设置的快照。
///
/// - Windows：读取「设置 → 网络 → 代理 → 手动设置代理」（注册表 `Internet Settings` 的
///   ProxyEnable / ProxyServer / ProxyOverride），Clash、v2rayN 等「系统代理」开关写的就是这里；
///   自动配置脚本（PAC）不支持，按直连处理；
/// - macOS：GUI 应用不继承 shell 环境变量，优先走原生通道
///   （CFNetworkCopySystemProxySettings，见 [SystemProxyReader.macOSSettingsReader]）；
/// - 其他平台（及 macOS 通道不可用时的回退）：环境变量
///   `https_proxy` / `http_proxy` / `no_proxy`（大小写均可）。
class SystemProxySettings {
  /// http:// 请求用的代理。
  final ProxyEndpoint? http;

  /// https:// 请求与原始 TCP 隧道用的代理。
  final ProxyEndpoint? https;

  /// 不走代理的主机规则（`*.example.com`、`10.*`、`<local>` 表示不带点的内网主机名）。
  final List<String> bypass;

  const SystemProxySettings({this.http, this.https, this.bypass = const []});

  static const SystemProxySettings none = SystemProxySettings();

  bool get isEmpty => http == null && https == null;

  /// 展示用：优先 https 的代理。
  ProxyEndpoint? get primary => https ?? http;

  /// [host] 是否命中绕过规则。
  bool bypasses(String host) {
    final h = host.toLowerCase();
    for (final raw in bypass) {
      final rule = raw.trim().toLowerCase();
      if (rule.isEmpty) continue;
      if (rule == '<local>') {
        if (!h.contains('.')) return true;
        continue;
      }
      // CIDR 网段（macOS 默认的 169.254/16、Clash 写入的 192.168.0.0/16 等）
      final cidr = _Ipv4Cidr.tryParse(rule);
      if (cidr != null) {
        if (cidr.contains(h)) return true;
        continue;
      }
      // 环境变量常见写法「.example.com」：匹配其子域名与自身
      final pattern = rule.startsWith('.') ? '*$rule' : rule;
      final regex = RegExp(
        '^${RegExp.escape(pattern).replaceAll(r'\*', '.*')}\$',
      );
      if (regex.hasMatch(h) || (rule.startsWith('.') && h == rule.substring(1)))
        return true;
    }
    return false;
  }

  /// 解析 Windows 的 ProxyServer：`host:port`（所有协议）或 `http=h:p;https=h:p;socks=h:p`。
  /// SOCKS 不支持（Dart 的 HttpClient 只能走 HTTP 代理），忽略。
  static SystemProxySettings fromWindows({
    required bool enabled,
    required String server,
    String override = '',
  }) {
    if (!enabled || server.trim().isEmpty) return none;
    ProxyEndpoint? http;
    ProxyEndpoint? https;
    if (server.contains('=')) {
      for (final part in server.split(';')) {
        final i = part.indexOf('=');
        if (i < 0) continue;
        final scheme = part.substring(0, i).trim().toLowerCase();
        final endpoint = ProxyEndpoint.tryParse(part.substring(i + 1));
        if (scheme == 'http') http = endpoint;
        if (scheme == 'https') https = endpoint;
      }
    } else {
      http = https = ProxyEndpoint.tryParse(server);
    }
    return SystemProxySettings(
      http: http,
      https: https ?? http,
      bypass: override.split(';'),
    );
  }

  static SystemProxySettings fromEnvironment(Map<String, String> env) {
    String? read(String name) => env[name] ?? env[name.toUpperCase()];
    final http = ProxyEndpoint.tryParse(read('http_proxy') ?? '');
    final https = ProxyEndpoint.tryParse(read('https_proxy') ?? '') ?? http;
    return SystemProxySettings(
      http: http,
      https: https,
      bypass: (read('no_proxy') ?? '').split(','),
    );
  }
}

/// 读取当前系统代理。读失败（无权限、命令不可用）时按「系统未设置代理」处理。
class SystemProxyReader {
  SystemProxyReader._();

  static const String _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// macOS 原生通道的系统代理快照来源（MethodChannel `flutify/system_proxy`）。
  ///
  /// 保持本文件纯 Dart（命令行探针经 network_proxy 复用），由 Flutter 侧在启动时
  /// 注入（`system_proxy_channel.dart` 的 installMacOSSystemProxyReader）；
  /// 纯 Dart 环境下为 null，macOS 走 [read] 里的环境变量回退即可。
  static Future<Map<dynamic, dynamic>?> Function()? macOSSettingsReader;

  static Future<SystemProxySettings> read() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('reg', [
          'query',
          _registryKey,
        ]).timeout(const Duration(seconds: 2));
        if (result.exitCode != 0) return SystemProxySettings.none;
        return parseRegQuery(result.stdout as String);
      } catch (_) {
        return SystemProxySettings.none;
      }
    }
    if (Platform.isMacOS) {
      // 原生通道未接入 / 超时 / 失败：退回环境变量（开发期命令行启动仍可生效）
      final reader = macOSSettingsReader;
      if (reader != null) {
        try {
          final map = await reader().timeout(const Duration(seconds: 2));
          if (map != null) return systemProxySettingsFromMacOS(map);
        } catch (_) {
          // 落到环境变量
        }
      }
    }
    return SystemProxySettings.fromEnvironment(Platform.environment);
  }

  /// `reg query` 的输出：每行「    名称    类型    值」。
  static SystemProxySettings parseRegQuery(String output) {
    final values = <String, String>{};
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final m = RegExp(r'^\s+(\S+)\s+REG_\w+\s+(.*)$').firstMatch(line);
      if (m != null) values[m.group(1)!] = m.group(2)!.trim();
    }
    final enable = values['ProxyEnable'] ?? '0x0';
    return SystemProxySettings.fromWindows(
      enabled: int.tryParse(enable.replaceFirst('0x', ''), radix: 16) == 1,
      server: values['ProxyServer'] ?? '',
      override: values['ProxyOverride'] ?? '',
    );
  }
}

/// IPv4 网段规则：`a.b.c.d/n`，以及 macOS 例外列表里的省略写法 `169.254/16`（缺的段补 0）。
class _Ipv4Cidr {
  final int network;
  final int mask;

  const _Ipv4Cidr(this.network, this.mask);

  static _Ipv4Cidr? tryParse(String rule) {
    final slash = rule.indexOf('/');
    if (slash < 0) return null;
    final bits = int.tryParse(rule.substring(slash + 1));
    final address = _parse(rule.substring(0, slash), allowShort: true);
    if (bits == null || bits < 0 || bits > 32 || address == null) return null;
    final mask = bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
    return _Ipv4Cidr(address & mask, mask);
  }

  bool contains(String host) {
    final address = _parse(host, allowShort: false);
    return address != null && (address & mask) == network;
  }

  static int? _parse(String text, {required bool allowShort}) {
    final parts = text.split('.');
    if (parts.isEmpty || parts.length > 4 || (!allowShort && parts.length != 4))
      return null;
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final octet = i < parts.length ? int.tryParse(parts[i]) : 0;
      if (octet == null || octet < 0 || octet > 255) return null;
      value = (value << 8) | octet;
    }
    return value;
  }
}
