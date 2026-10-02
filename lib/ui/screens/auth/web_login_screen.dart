import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../../services/auth/web_token_service.dart';
import '../../../services/eme/eme_player.dart';

/// Web 登录页：在内嵌 WebView2 里登录 open.spotify.com，捕获 `sp_dc` cookie。
///
/// sp_dc 是铸造「Web 播放器 access_token」（Widevine 真密钥所需）的唯一凭据，
/// 与桌面 OAuth（管媒体库 / API / Connect，走系统浏览器）互补，不互相替代。
///
/// 为什么桌面登录不也放在这个 WebView 里：用户可能在浏览器里用 Google 等第三方
/// 登录，凭据不应交给应用内 WebView；因此桌面登录一律走系统浏览器（回环回调），
/// 本页只负责 Web 登录态。Google 注册的账号在本页用「邮箱 + 密码」登录即可。
///
/// 性能说明：这是**用户主动打开的一次性登录页**，不是后台常驻渲染 open.spotify.com；
/// 登录完成即销毁 WebView。
class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  /// 打开 Web 登录页。返回登录结果（用户取消 / 跳过返回 null）。
  static Future<WebLoginResult?> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<WebLoginResult?>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const WebLoginScreen()),
    );
  }

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

/// Web 登录结果：[spDc] 非空即成功。
class WebLoginResult {
  final String? spDc;

  /// 保留字段：桌面授权是否也已完成（当前桌面登录一律走浏览器，此处恒为 false）。
  final bool desktopAuthorized;
  const WebLoginResult({this.spDc, this.desktopAuthorized = false});

  bool get webSignedIn => spDc != null && spDc!.isNotEmpty;
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  bool _checking = false;
  Timer? _pollTimer;

  /// 页面已结束（pop 过），后续回调全部忽略。
  bool _done = false;

  // 登录完成判定：跳到 open.spotify.com 且能读到 sp_dc
  static final Uri _homeHost = Uri.parse('https://open.spotify.com');

  @override
  void initState() {
    super.initState();
    // 兜底：每 2 秒主动查一次 sp_dc（某些跳转路径不触发 onUpdateVisitedHistory）
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _tryCapture());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _finish(WebLoginResult? result) {
    if (_done || !mounted) return;
    _done = true;
    _pollTimer?.cancel();
    Navigator.of(context).pop(result);
  }

  Future<void> _tryCapture() async {
    if (_checking || _done) return;
    _checking = true;
    try {
      final cookie = await CookieManager.instance().getCookie(
        url: WebUri('https://open.spotify.com'),
        name: 'sp_dc',
      );
      final value = cookie?.value?.toString() ?? '';
      if (value.isNotEmpty && mounted && !_done) {
        // 立即经插件保存（不手动写 shared_preferences 文件，避免被整文件重写覆盖）
        await context.read<WebTokenService>().setSpDc(value);
        _finish(WebLoginResult(spDc: value));
      }
    } catch (_) {
      // 读取失败（登录未完成）继续等
    } finally {
      _checking = false;
    }
  }

  void _onNav(String? url) {
    if (url == null || _done) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // 进入 open.spotify.com（登录成功跳转）即开始尝试捕获
    if (uri.host == _homeHost.host) {
      _tryCapture();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('全曲播放：Web 登录'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _finish(null),
        ),
      ),
      body: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2),
          // Google 账号提示：桌面登录已在浏览器完成，这里只需要 Spotify 的 Web 会话
          Container(
            width: double.infinity,
            color: colorScheme.secondaryContainer.withAlpha(120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: colorScheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '用 Google 注册的账号：请在此处使用「邮箱 + 密码」登录；'
                    '没有密码可先在 Spotify 官网「忘记密码」设置一个。',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              // 复用 EME 的自定义环境：同一用户数据目录只允许一个环境实例，
              // 不传会触发插件再建环境（ERROR_INVALID_STATE）导致 WebView 创建失败
              webViewEnvironment: EmePlayer.cachedEnvironment,
              initialUrlRequest: URLRequest(
                url: WebUri('https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F'),
              ),
              initialSettings: InAppWebViewSettings(
                disableContextMenu: true,
                supportZoom: false,
                // 伪装成纯 Chrome（去掉 WebView2 的 Edg 标识）：Google 按 UA 封嵌入
                // WebView（disallowed_useragent），伪装后有概率直接放行 Google 登录
                userAgent:
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
              ),
              onUpdateVisitedHistory: (_, url, _) => _onNav(url?.toString()),
              onLoadStop: (_, url) => _onNav(url?.toString()),
            ),
          ),
        ],
      ),
    );
  }
}
