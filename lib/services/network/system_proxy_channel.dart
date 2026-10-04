import 'dart:io';

import 'package:flutter/services.dart';

import 'system_proxy.dart';

/// macOS 系统代理的原生通道注入（MethodChannel `flutify/system_proxy`）。
///
/// GUI 应用不继承 shell 的 `http_proxy` 环境变量，macOS 上须先调用本函数，
/// [SystemProxyReader] 才会经原生端（macos/Runner/SystemProxyChannel.swift）
/// 读取「系统设置 → 网络 → 代理」里的 CFNetworkCopySystemProxySettings 快照；
/// 调用须在 ProxyHttpOverrides.install 之前（main.dart 的网络代理段）。
void installMacOSSystemProxyReader() {
  if (!Platform.isMacOS) return;
  const channel = MethodChannel('flutify/system_proxy');
  SystemProxyReader.macOSSettingsReader = () async {
    try {
      return await channel.invokeMethod<Map<dynamic, dynamic>>(
        'getSystemProxySettings',
      );
    } on MissingPluginException {
      return null; // 原生端未注册（测试环境、旧 runner）：走环境变量回退
    } on PlatformException {
      return null;
    }
  };
}
