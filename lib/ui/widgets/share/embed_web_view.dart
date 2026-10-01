import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../models/share_target.dart';
import 'embed_preview.dart';

/// 嵌入播放器的真实渲染：用 WebView 直接加载官方嵌入页，所见即贴到网页后的效果。
///
/// - 高度为真实的 352 / 152；切换「深色」时重新加载对应地址，切换尺寸只改高度（嵌入页自适应）；
/// - 加载完成前显示示意预览 [EmbedPreview]，完成后淡入；
/// - 不支持 WebView（测试环境、Linux、Windows 缺 WebView2 运行时）或加载失败时，一直显示示意预览；
/// - 嵌入页内的跳转（「在 Spotify 中打开」等）交给系统浏览器，不在面板里导航走。
class EmbedWebView extends StatefulWidget {
  final ShareTarget target;
  final EmbedSize size;
  final bool dark;

  const EmbedWebView({super.key, required this.target, required this.size, required this.dark});

  /// 平台是否可能提供 WebView；Widget 测试中关闭（测试宿主同样是 Windows）。
  static bool enabled =
      !kIsWeb &&
      (Platform.isWindows || Platform.isAndroid || Platform.isIOS || Platform.isMacOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  /// Windows 需要 WebView2 运行时；只检测一次，结果缓存。
  static Future<bool>? _available;

  static Future<bool> _checkAvailable() => _available ??= () async {
    if (!enabled) return false;
    if (!Platform.isWindows) return true;
    try {
      return await WebViewEnvironment.getAvailableVersion() != null;
    } catch (_) {
      return false;
    }
  }();

  @override
  State<EmbedWebView> createState() => _EmbedWebViewState();
}

class _EmbedWebViewState extends State<EmbedWebView> {
  /// null = 检测中；false = 不可用，只显示示意预览。
  bool? _available;
  bool _loaded = false;
  bool _failed = false;
  InAppWebViewController? _controller;

  String get _url => widget.target.embedUrl(dark: widget.dark);

  @override
  void initState() {
    super.initState();
    EmbedWebView._checkAvailable().then((ok) {
      if (mounted) setState(() => _available = ok);
    });
  }

  @override
  void didUpdateWidget(EmbedWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlChanged = oldWidget.dark != widget.dark || oldWidget.target.id != widget.target.id;
    if (urlChanged && _controller != null && !_failed) {
      setState(() => _loaded = false);
      _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(_url)));
    }
  }

  /// 只允许停留在嵌入页本身；其他地址（含新窗口）用系统浏览器打开。
  bool _isEmbedPage(WebUri? uri) =>
      uri == null || uri.scheme == 'about' || (uri.host == 'open.spotify.com' && uri.path.startsWith('/embed'));

  void _openExternally(WebUri? uri) {
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http' || uri.scheme == 'spotify')) return;
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false));
  }

  @override
  Widget build(BuildContext context) {
    final fallback = EmbedPreview(target: widget.target, size: widget.size, dark: widget.dark);
    if (_available != true || _failed) return fallback;

    final duration = context.motion(const Duration(milliseconds: 320));
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      height: widget.size.height.toDouble(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 加载期间的占位：示意预览顶对齐，WebView 完成后盖在上面
            if (!_loaded) Align(alignment: Alignment.topCenter, child: fallback),
            AnimatedOpacity(
              duration: duration,
              opacity: _loaded ? 1 : 0,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_url)),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  disableContextMenu: true,
                  supportZoom: false,
                  useShouldOverrideUrlLoading: true,
                  mediaPlaybackRequiresUserGesture: true,
                ),
                onWebViewCreated: (controller) => _controller = controller,
                onLoadStop: (_, _) {
                  if (mounted) setState(() => _loaded = true);
                },
                onReceivedError: (_, request, _) {
                  if ((request.isForMainFrame ?? true) && mounted) setState(() => _failed = true);
                },
                shouldOverrideUrlLoading: (_, action) async {
                  final uri = action.request.url;
                  if (_isEmbedPage(uri)) return NavigationActionPolicy.ALLOW;
                  _openExternally(uri);
                  return NavigationActionPolicy.CANCEL;
                },
                onCreateWindow: (_, action) async {
                  _openExternally(action.request.url);
                  return false;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
