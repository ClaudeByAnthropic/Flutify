import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pathfinder_operations.dart';

/// GraphQL Pathfinder 客户端（`api-partner.spotify.com/pathfinder/v2/query`）。
///
/// 与桌面版一致使用 v2：POST JSON `{variables, operationName, extensions.persistedQuery}`。
/// 请求头（Bearer、client-token、桌面 UA / app-platform）由 [headers] 提供，保证与会话身份一致。
class PathfinderClient {
  static const String endpoint = 'https://api-partner.spotify.com/pathfinder/v2/query';

  final http.Client _client;
  final Future<Map<String, String>> Function() headers;

  PathfinderClient(this._client, {required this.headers});

  /// 执行查询并返回 `data`；HTTP 非 200 或响应含 errors 且无 data 时抛 [PathfinderException]。
  Future<Map<String, dynamic>> query(PathfinderOperation op, Map<String, Object?> variables) async {
    final res = await _client.post(
      Uri.parse(endpoint),
      headers: {...await headers(), 'content-type': 'application/json;charset=UTF-8'},
      body: jsonEncode({
        'variables': variables,
        'operationName': op.name,
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': op.sha256Hash},
        },
      }),
    );

    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    final data = json is Map<String, dynamic> ? json['data'] : null;
    if (res.statusCode != 200 || data is! Map<String, dynamic>) {
      final errors = json is Map<String, dynamic> ? json['errors'] : null;
      throw PathfinderException(op.name, res.statusCode, errors?.toString() ?? '');
    }
    return data;
  }
}

class PathfinderException implements Exception {
  final String operation;
  final int statusCode;
  final String detail;

  const PathfinderException(this.operation, this.statusCode, this.detail);

  @override
  String toString() => 'Pathfinder $operation 失败（HTTP $statusCode）$detail';
}
