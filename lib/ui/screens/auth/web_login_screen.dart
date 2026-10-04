import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/auth/web_login_flow.dart';
import '../../../services/auth/web_token_service.dart';
import '../../../services/eme/eme_player.dart';
import '../../shell/desktop/desktop_window.dart';

export '../../../services/auth/web_login_flow.dart' show WebLoginStage;

/// 统一登录页：在内嵌 WebView2 里完成一次 Web 登录，其余全部自动收尾。
///
/// 1. 用户在 WebView 里登录 open.spotify.com（唯一有感知的一步）；
/// 2. 登录完成自动捕获 `sp_dc`（Web 会话凭据，httpOnly）并铸 Web token——**自动获取需要的内容**；
/// 3. 桌面 OAuth 若还没做，**后台无感补上**：同一 WebView 会话打开授权页（已登录自动过），
///    回环收 code、换令牌，全程不需要用户操作。
///
/// sp_dc 是铸造「Web 播放器 access_token」（Widevine 真密钥所需）的唯一凭据；
/// 桌面 OAuth 管媒体库 / API / Connect。一次登录两样都齐。
///
/// 性能说明：这是**用户主动打开的一次性登录页**，不是后台常驻渲染 open.spotify.com；
/// 登录完成即销毁 WebView。
class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  /// 打开统一登录页。返回登录结果（用户取消 / 跳过返回 null）。
  static Future<WebLoginResult?> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<WebLoginResult?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const WebLoginScreen(),
      ),
    );
  }

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

/// 登录结果：[spDc] 非空即 Web 会话已就绪；[desktopAuthorized] 表示桌面 OAuth 也已完成。
class WebLoginResult {
  final String? spDc;
  final bool desktopAuthorized;
  const WebLoginResult({this.spDc, this.desktopAuthorized = false});

  bool get webSignedIn => spDc != null && spDc!.isNotEmpty;
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  InAppWebViewController? _controller;
  late final WebLoginFlow _flow;
  AuthProvider? _auth;

  Timer? _pollTimer;
  Timer? _consentTimer;
  Timer? _revealTimer;

  /// 页面已结束（pop 过），后续回调全部忽略。
  bool _done = false;

  /// 后台桌面授权是否已露出 WebView（自动过不去时兜底让用户手点「同意」）。
  bool _revealed = false;

  /// 最近一次页面地址（同意页自动点击的判定依据）。
  String? _currentUrl;

  /// 桌面授权阶段的兜底等待：超过该时长仍没完成就露出 WebView 让用户手动确认。
  static const Duration _manualFallbackDelay = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    final tokens = context.read<WebTokenService>();
    final auth = context.read<AuthProvider?>();
    _auth = auth;
    _flow = WebLoginFlow(
      // 关键：CookieManager 必须与 WebView 同一个 WebViewEnvironment。
      // 用默认环境会与 EME 的自定义环境（同 user data 目录、不同浏览器参数）冲突，
      // 创建即 ERROR_INVALID_STATE，读 cookie 永远抛异常 —— 登录完卡在 open.spotify.com 的根因。
      readSpDc: _readSpDc,
      saveSpDc: tokens.setSpDc,
      prepareWebToken: () =>
          tokens.mintAccessToken().timeout(const Duration(seconds: 15)),
      // 没有 AuthProvider（测试）时视为桌面已登录，只做 Web 会话部分
      desktopSignedIn: () => auth?.isSignedIn ?? true,
      beginDesktopOAuth: () async => auth?.beginOAuth(),
      cancelDesktopOAuth: () async => auth?.cancelOAuth(),
      onAuthorizeUrl: _loadAuthorizeUrl,
      onFinished: (_) => _finish(
        WebLoginResult(
          spDc: _flow.spDc,
          desktopAuthorized: _flow.desktopAuthorized,
        ),
      ),
    );
    _flow.addListener(_onFlowChanged);
    auth?.addListener(_onAuthChanged);
    // 兜底：每 2 秒推一次流程（读 sp_dc 的轮询；跳转路径不固定，不能只靠导航事件）
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _flow.poll(),
    );
    // 同意页自动点击：React 页面的按钮晚于 onLoadStop 渲染，按小周期多试几次
    _consentTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _tryAutoApprove(),
    );
    // 立即跑一次（WebView 会话里可能已经登录过）
    unawaited(_flow.poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _consentTimer?.cancel();
    _revealTimer?.cancel();
    _flow.removeListener(_onFlowChanged);
    _auth?.removeListener(_onAuthChanged);
    // 关页时放弃未完成的桌面授权，避免回环端口在后台悬挂
    unawaited(_flow.cancel());
    _flow.dispose();
    super.dispose();
  }

  void _finish(WebLoginResult? result) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context, rootNavigator: true).pop(result);
  }

  // ---------------------------------------------------------------------------
  // 流程推进
  // ---------------------------------------------------------------------------

  void _onFlowChanged() {
    if (!mounted || _done) return;
    setState(() {});
  }

  /// AuthProvider 状态 → 流程：已登录即桌面授权完成；失败带错误信息回流程。
  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || _done) return;
    if (auth.isSignedIn) {
      _flow.onDesktopAuthorized();
    } else if (_flow.waitingForDesktop &&
        auth.status == AuthStatus.signedOut &&
        (auth.error?.isNotEmpty ?? false)) {
      _flow.onDesktopFailed(auth.error!);
    }
  }

  /// 读 sp_dc：多来源各试一遍（cookie 域绑定可能落在 accounts 或 open 上）。
  Future<String?> _readSpDc() async {
    final manager = CookieManager.instance(
      webViewEnvironment: EmePlayer.cachedEnvironment,
    );
    for (final url in const [
      'https://open.spotify.com',
      'https://accounts.spotify.com',
    ]) {
      try {
        final cookie = await manager.getCookie(url: WebUri(url), name: 'sp_dc');
        final value = cookie?.value?.toString() ?? '';
        if (value.isNotEmpty) return value;
      } catch (_) {
        // 环境未就绪 / 登录未完成：换下一个来源或下个轮询周期
      }
    }
    return null;
  }

  /// 桌面授权页装载进 WebView（被进度浮层盖住，用户无感）。
  void _loadAuthorizeUrl(Uri url) {
    if (!mounted || _done) return;
    setState(() {
      _revealed = false;
      _currentUrl = url.toString();
    });
    _revealTimer?.cancel();
    _revealTimer = Timer(_manualFallbackDelay, _revealForManual);
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url.toString())));
  }

  /// 自动授权超时兜底：露出 WebView，让用户手动点「同意」。
  void _revealForManual() {
    if (!mounted || _done || !_flow.waitingForDesktop) return;
    setState(() => _revealed = true);
  }

  /// 同意页自动点击（后台无感完成授权的关键一步）。
  Future<void> _tryAutoApprove() async {
    final controller = _controller;
    if (controller == null ||
        _done ||
        !(_flow.waitingForDesktop || _flow.stage == WebLoginStage.webSignIn))
      return;
    if (!isSpotifyAccountsPageUrl(_currentUrl)) return;
    try {
      await controller.evaluateJavascript(source: kConsentAutoApproveScript);
    } catch (_) {
      // 页面正处在跳转中，下个周期再试
    }
  }

  void _onNav(String? url) {
    if (url == null || _done) return;
    _currentUrl = url;
    // 回环回调到达 = 授权码已交给本机服务，等 AuthProvider 换完令牌即可
    if (!isLoopbackRedirect(url)) _tryAutoApprove();
  }

  // ---------------------------------------------------------------------------
  // 界面
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final stage = _flow.stage;
    final showOverlay =
        !_revealed &&
        (stage == WebLoginStage.preparing ||
            stage == WebLoginStage.desktopAuthorize);

    // macOS 原生交通灯浮在窗口左上角：标题栏整体下移一条交通灯高度，关闭按钮不再与之重叠；
    // 下移出的这条与标题栏同色、可拖动窗口
    final media = MediaQuery.of(context);
    final macInset = DesktopWindow.macNativeWindow ? _macTitleInset : 0.0;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('全曲播放：Web 登录'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '关闭',
          onPressed: () => _finish(null),
        ),
        flexibleSpace: macInset > 0
            ? const WindowDragArea(child: SizedBox.expand())
            : null,
      ),
      body: Column(
        children: [
          if (stage != WebLoginStage.done)
            const LinearProgressIndicator(minHeight: 2),
          if (stage == WebLoginStage.webSignIn) const _GoogleAccountHint(),
          if (_flow.notice != null)
            _NoticeBar(text: _flow.notice!, icon: Icons.info_outline_rounded),
          if (stage == WebLoginStage.failed)
            _NoticeBar(
              text: _flow.error ?? '登录失败',
              icon: Icons.error_outline_rounded,
              actionLabel: '重试',
              onAction: () => _flow.retry(),
            ),
          if (_revealed && _flow.waitingForDesktop)
            const _NoticeBar(
              text: '如果页面在等你确认，请点「同意」完成授权；其余步骤已自动完成',
              icon: Icons.touch_app_rounded,
            ),
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  // 复用 EME 的自定义环境：同一用户数据目录只允许一个环境实例，
                  // 不传会触发插件再建环境（ERROR_INVALID_STATE）导致 WebView 创建失败
                  webViewEnvironment: EmePlayer.cachedEnvironment,
                  initialUrlRequest: URLRequest(
                    url: WebUri(
                      'https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F',
                    ),
                  ),
                  initialSettings: InAppWebViewSettings(
                    disableContextMenu: true,
                    supportZoom: false,
                    // 伪装成纯 Chrome（去掉 WebView2 的 Edg 标识）：Google 按 UA 封嵌入
                    // WebView（disallowed_useragent），伪装后有概率直接放行 Google 登录
                    userAgent:
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
                  ),
                  onWebViewCreated: (controller) => _controller = controller,
                  onUpdateVisitedHistory: (_, url, _) =>
                      _onNav(url?.toString()),
                  onLoadStop: (_, url) => _onNav(url?.toString()),
                ),
                if (showOverlay) _ProgressOverlay(stage: stage),
              ],
            ),
          ),
        ],
      ),
    );
    if (macInset == 0) return scaffold;
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(top: media.padding.top + macInset),
      ),
      child: scaffold,
    );
  }

  /// macOS 交通灯所在那一行的高度（隐藏标题栏时的系统标题栏高度）。
  static const double _macTitleInset = 28;
}

/// 后台收尾阶段盖住 WebView 的进度浮层：用户只看到「登录完成，正在收尾」。
class _ProgressOverlay extends StatelessWidget {
  final WebLoginStage stage;
  const _ProgressOverlay({required this.stage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = switch (stage) {
      WebLoginStage.preparing => '正在获取播放凭据…',
      WebLoginStage.desktopAuthorize => '正在完成账号授权…',
      _ => '正在完成登录…',
    };
    return Positioned.fill(
      child: ColoredBox(
        color: colorScheme.surface,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 4),
            ),
            const SizedBox(height: 24),
            Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '登录已完成，剩下的步骤在后台自动进行',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google 账号提示：Google 注册的账号在本页用「邮箱 + 密码」登录。
class _GoogleAccountHint extends StatelessWidget {
  const _GoogleAccountHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.secondaryContainer.withAlpha(120),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '用 Google 注册的账号：请在此处使用「邮箱 + 密码」登录；'
              '没有密码可先在 Spotify 官网「忘记密码」设置一个。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部信息条（非致命提示 / 错误 + 动作）。
class _NoticeBar extends StatelessWidget {
  final String text;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _NoticeBar({
    required this.text,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer.withAlpha(90),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
