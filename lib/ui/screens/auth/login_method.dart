import 'package:flutter/material.dart';

/// 登录页可选的登录方式（短信验证码是这些方式的后续阶段，不在此列）。
enum LoginMethod {
  desktop(Icons.open_in_browser_rounded, '在浏览器中登录', '与官方桌面版相同，风控风险最低'),
  password(Icons.password_rounded, '账号密码', '以 Android 客户端身份直连，可能触发风控'),
  phone(Icons.phone_iphone_rounded, '手机号', '接收短信验证码登录'),
  oneTimeToken(Icons.link_rounded, '登录链接 / 一次性令牌', '粘贴 Spotify 发送的登录链接'),
  importCredential(Icons.key_rounded, '导入已保存凭据', '复用 librespot 的登录凭据，免密登录'),
  oauth(Icons.developer_mode_rounded, '开发者应用授权', '使用你自己的 Client ID，仅公开接口');

  final IconData icon;
  final String title;
  final String description;

  const LoginMethod(this.icon, this.title, this.description);

  /// 登录页的起始方式。
  static const LoginMethod initial = desktop;

  /// "更多方式"面板中列出的方式。
  static const List<LoginMethod> more = [phone, oneTimeToken, importCredential, oauth];
}
