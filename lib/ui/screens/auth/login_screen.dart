import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../widgets/toast/app_toast.dart';
import 'widgets/login_intro_view.dart';
import 'widgets/oauth_waiting_view.dart';

/// Spotify 账号登录页（唯一方式：在浏览器中登录）。
///
/// 外壳只负责：在「介绍」与「等待浏览器授权」两态间切换（淡入 + 轻微上移 + 缩放）、
/// 返回键语义，以及登录成功（浏览器回调异步到达）时关闭页面、返回 true 并提示。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// 以全屏对话框形式打开，返回是否登录成功。
  static Future<bool> open(BuildContext context) async {
    final result = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LoginScreen()));
    return result ?? false;
  }

  /// 登录已过期时「重新登录」：先清掉失效的会话（登录页只在未登录状态下工作），再打开登录页。
  static Future<bool> signInAgain(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    await context.read<AuthProvider>().signOut();
    final result = await navigator.push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LoginScreen()),
    );
    return result ?? false;
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthProvider _auth = context.read<AuthProvider>();
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    // 离开页面时放弃未完成的浏览器授权，避免回环端口在后台悬挂。
    // dispose 期间组件树已锁定，通知监听者需推迟到微任务
    final auth = _auth;
    Future.microtask(() {
      if (auth.isAuthorizing) auth.cancelOAuth();
    });
    super.dispose();
  }

  /// 登录成功后关闭页面，并在下层页面上提示登录身份。
  void _onAuthChanged() {
    if (_finished || !_auth.isSignedIn || !mounted) return;
    _finished = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = _auth.displayName;
    Navigator.of(context).pop(true);
    AppToast.showOn(messenger, '已登录为 $name', icon: Icons.person_rounded, tone: ToastTone.success);
  }

  /// 左上角 / 系统返回：等待授权时先退回介绍态，否则关闭页面。
  void _back() {
    if (_auth.isAuthorizing) {
      _auth.cancelOAuth();
    } else {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authorizing = context.select<AuthProvider, bool>((a) => a.isAuthorizing);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return PopScope(
      canPop: !authorizing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: Stack(
          children: [
            const _AmbientGlow(),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton(
                        icon: Icon(authorizing ? Icons.arrow_back_rounded : Icons.close_rounded),
                        tooltip: authorizing ? '返回' : '关闭',
                        onPressed: _back,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: AnimatedSwitcher(
                            duration: Duration(milliseconds: reduceMotion ? 0 : 420),
                            reverseDuration: Duration(milliseconds: reduceMotion ? 0 : 200),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.6)),
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
                                child: ScaleTransition(
                                  scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                                  child: child,
                                ),
                              ),
                            ),
                            child: authorizing
                                ? const OAuthWaitingView(key: ValueKey('waiting'))
                                : const LoginIntroView(key: ValueKey('intro')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页面背景的主题色环境光：顶部一团低透明度径向渐变，底部再补一抹更淡的次要色，
/// 让大面积留白不至于单调。
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.1),
                  radius: 1.1,
                  colors: [colorScheme.primary.withAlpha(40), colorScheme.primary.withAlpha(0)],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.1, 1.2),
                  radius: 0.9,
                  colors: [colorScheme.tertiary.withAlpha(22), colorScheme.tertiary.withAlpha(0)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
