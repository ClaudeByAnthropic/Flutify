import 'dart:convert';
import 'dart:typed_data';

/// 用户粘贴内容的解析：可复用凭据（StoredCredential）与一次性令牌。
class CredentialParsers {
  CredentialParsers._();

  /// librespot `AuthenticationType.AUTHENTICATION_STORED_SPOTIFY_CREDENTIALS`。
  static const int _storedCredentialsAuthType = 1;

  /// 解析 librespot `credentials.json`：`{"username", "auth_type", "auth_data", ["device_id"]}`。
  /// 也接受 `stored_credential` / `credentials` / `data` 作为凭据字段名。
  static ImportedCredential parseCredentialsJson(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text.trim());
    } catch (_) {
      throw const FormatException('不是有效的 JSON');
    }
    if (decoded is! Map<String, dynamic>) throw const FormatException('JSON 顶层应为对象');

    final authType = decoded['auth_type'];
    if (authType is num && authType.toInt() != _storedCredentialsAuthType) {
      throw const FormatException('该文件保存的不是可复用凭据（auth_type 应为 1）');
    }

    final username = (decoded['username'] as String?)?.trim() ?? '';
    final blob = (decoded['auth_data'] ?? decoded['stored_credential'] ?? decoded['credentials'] ?? decoded['data'])
        as String?;
    return build(username: username, blobBase64: blob ?? '', deviceId: decoded['device_id'] as String?);
  }

  /// 由手动填写的字段构造并校验。
  static ImportedCredential build({required String username, required String blobBase64, String? deviceId}) {
    if (username.trim().isEmpty) throw const FormatException('缺少用户名');
    final blob = decodeBase64(blobBase64);
    if (blob.isEmpty) throw const FormatException('凭据内容为空或不是有效的 Base64');
    final device = deviceId?.trim() ?? '';
    if (device.isNotEmpty && !RegExp(r'^[0-9a-zA-Z_-]{16,64}$').hasMatch(device)) {
      throw const FormatException('设备 ID 格式不正确');
    }
    return ImportedCredential(username: username.trim(), blob: blob, deviceId: device.isEmpty ? null : device);
  }

  /// 同时兼容标准 / URL 安全 Base64，缺失的填充自动补齐；失败返回空数组。
  static Uint8List decodeBase64(String input) {
    var s = input.trim().replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
    if (s.isEmpty) return Uint8List(0);
    s = s.padRight(s.length + (4 - s.length % 4) % 4, '=');
    try {
      return base64Decode(s);
    } catch (_) {
      return Uint8List(0);
    }
  }

  /// 从登录链接或原始文本中提取一次性令牌。
  ///
  /// 链接中常见的参数名：`token`、`ott`、`one_time_token`、`login_token`；
  /// 不是链接时，把去掉空白后的整段文本视为令牌。
  static String extractOneTimeToken(String input) {
    final text = input.trim();
    if (text.isEmpty) return '';
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final params = {...uri.queryParameters, ..._fragmentParams(uri)};
      for (final key in const ['token', 'ott', 'one_time_token', 'login_token']) {
        final value = params[key];
        if (value != null && value.isNotEmpty) return value;
      }
      return '';
    }
    return text.contains(RegExp(r'\s')) ? '' : text;
  }

  static Map<String, String> _fragmentParams(Uri uri) {
    if (uri.fragment.isEmpty || !uri.fragment.contains('=')) return const {};
    try {
      return Uri.splitQueryString(uri.fragment);
    } catch (_) {
      return const {};
    }
  }
}

/// 导入的可复用凭据。
class ImportedCredential {
  final String username;
  final Uint8List blob;

  /// 凭据绑定的设备 ID；提供时会替换本机 device_id（凭据跨设备通常无效）。
  final String? deviceId;

  const ImportedCredential({required this.username, required this.blob, this.deviceId});
}
