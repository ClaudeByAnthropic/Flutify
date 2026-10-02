/// HTTP 代理地址（主机 + 端口）。
///
/// 保持纯 Dart（不引入 Flutter）：命令行探针经 network_proxy → 本文件联网。
class ProxyEndpoint {
  final String host;
  final int port;

  const ProxyEndpoint(this.host, this.port);

  /// 宽松解析「host:port」「http://host:port/」「[::1]:port」；无效时返回 null。
  /// 不用 [Uri]：它会把 http 的 80、https 的 443 当默认端口丢掉。
  static ProxyEndpoint? tryParse(String raw) {
    var s = raw.trim();
    final scheme = s.indexOf('://');
    if (scheme >= 0) s = s.substring(scheme + 3);
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    final m = RegExp(
      r'^(?:\[([^\]]+)\]|([^:\s\[\]]+)):(\d{1,5})$',
    ).firstMatch(s);
    if (m == null) return null;
    final port = int.parse(m.group(3)!);
    if (port <= 0 || port > 65535) return null;
    return ProxyEndpoint(m.group(1) ?? m.group(2)!, port);
  }

  /// HttpClient.findProxy 的写法（IPv6 需要方括号）。
  @override
  String toString() => host.contains(':') ? '[$host]:$port' : '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is ProxyEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}
