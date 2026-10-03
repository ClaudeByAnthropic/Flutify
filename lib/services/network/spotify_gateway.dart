/// HTTPS reverse proxy for Spotify APIs/media; browser login remains on Spotify.
class SpotifyGateway {
  final bool enabled;
  final String baseUrl;
  final String username;
  final String password;

  const SpotifyGateway({
    this.enabled = false,
    this.baseUrl = '',
    this.username = '',
    this.password = '',
  });

  Uri? get base {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.where((s) => s.isNotEmpty).length != 1 ||
        uri.pathSegments.any((s) => !RegExp(r'^[a-zA-Z0-9_-]*$').hasMatch(s)))
      return null;
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  bool get isValid =>
      base != null && _headerValue(username) && _headerValue(password);
  static bool _headerValue(String s) =>
      s.isNotEmpty && s.codeUnits.every((c) => c >= 32 && c <= 126);

  Map<String, String> get headers => {
    'X-Proxy-User': username,
    'X-Proxy-Pass': password,
  };

  static bool supports(Uri uri) {
    if (!const ['http', 'https', 'ws', 'wss'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty)
      return false;
    if (uri.hasPort &&
        uri.port != (uri.scheme == 'http' || uri.scheme == 'ws' ? 80 : 443))
      return false;
    final host = uri.host.toLowerCase();
    // Only token API calls go through accounts; never the browser login flow.
    if (host == 'accounts.spotify.com') return uri.path == '/api/token';
    if (host == 'open.spotify.com') {
      return const {'/api/token', '/api/server-time'}.contains(uri.path);
    }
    if (isWidevineProvisioning(uri)) return true;
    if (const {
      'api.spotify.com',
      'apresolve.spotify.com',
      'api-partner.spotify.com',
      'clienttoken.spotify.com',
      'spclient.wg.spotify.com',
      'betamax.akamaized.net',
    }.contains(host))
      return true;
    if (const [
      'spclient.spotify.com',
      'scdn.co',
      'spotifycdn.com',
    ].any((d) => host == d || host.endsWith('.$d')))
      return true;
    return RegExp(
          r'^[a-z0-9-]*(spclient|dealer|audio|video)[a-z0-9-]*(\.[a-z0-9-]+)*\.spotify\.com$',
        ).hasMatch(host) ||
        RegExp(
          r'^[a-z0-9-]*spotify[a-z0-9-]*\.[a-z0-9.-]*akamaized\.net$',
        ).hasMatch(host);
  }

  static bool isWidevineProvisioning(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (uri.host == 'www.googleapis.com' &&
              uri.path ==
                  '/certificateprovisioning/v1/devicecertificates/create' ||
          uri.host == 'provisioning.googleapis.com' &&
              uri.path == '/v1/devicecertificates/create');

  Uri route(Uri original) {
    if (!enabled || !supports(original)) return original;
    if (!isValid)
      throw const FormatException('Invalid Spotify gateway configuration');
    final prefix = base!;
    // Interpolate encoded path/query, preserving signed CDN URLs byte for byte.
    return Uri.parse(
      '${prefix.origin}${prefix.path}/${original.host}${original.path.isEmpty ? '/' : original.path}${original.hasQuery ? '?${original.query}' : ''}',
    ).replace(
      scheme: original.scheme == 'ws' || original.scheme == 'wss'
          ? 'wss'
          : 'https',
    );
  }

  Uri tunnel(String host, int port) {
    if (!isValid)
      throw const FormatException('Invalid Spotify gateway configuration');
    if (!RegExp(
          r'^(ap(-[a-z0-9]+)?\.spotify\.com|[a-z0-9.-]*accesspoint[a-z0-9.-]*\.spotify\.com|[a-z0-9.-]+\.ap\.spotify\.com)$',
        ).hasMatch(host) ||
        !const [80, 443, 4070].contains(port))
      throw const FormatException('Unsupported Spotify access point');
    return Uri.parse(
      '${base!.origin}${base!.path}/__tunnel/$host:$port',
    ).replace(scheme: 'wss');
  }

  SpotifyGateway copyWith({
    bool? enabled,
    String? baseUrl,
    String? username,
    String? password,
  }) => SpotifyGateway(
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl ?? this.baseUrl,
    username: username ?? this.username,
    password: password ?? this.password,
  );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
  };
  factory SpotifyGateway.fromJson(Object? value) {
    if (value is! Map) return const SpotifyGateway();
    String read(String key) => value[key] is String ? value[key] as String : '';
    return SpotifyGateway(
      enabled: value['enabled'] == true,
      baseUrl: read('baseUrl'),
      username: read('username'),
      password: read('password'),
    );
  }
  @override
  bool operator ==(Object other) =>
      other is SpotifyGateway &&
      other.enabled == enabled &&
      other.baseUrl == baseUrl &&
      other.username == username &&
      other.password == password;
  @override
  int get hashCode => Object.hash(enabled, baseUrl, username, password);
  @override
  String toString() => 'SpotifyGateway(enabled: $enabled)';
}
