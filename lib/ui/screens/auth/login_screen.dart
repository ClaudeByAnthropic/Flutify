import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/md3e_colors.dart';
import '../../../providers/auth_provider.dart';
import 'login_method.dart';
import 'stages/code_stage.dart';
import 'stages/desktop_stage.dart';
import 'stages/import_stage.dart';
import 'stages/oauth_stage.dart';
import 'stages/password_stage.dart';
import 'stages/phone_stage.dart';
import 'stages/token_stage.dart';
import 'widgets/login_method_sheet.dart';

/// Spotify 账号登录页。
///
/// 外壳只负责：选择登录方式、切换阶段（淡入 + 轻微上移）、返回键语义，以及登录成功后关闭页面。
/// 各登录方式的表单在 `stages/` 下；短信验证码阶段由 [AuthProvider.isAwaitingCode] 驱动，
/// 优先于所选方式显示。登录成功（含浏览器授权的异步回调）时关闭本页并返回 true。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// 以全屏对话框形式打开，返回是否登录成功。
  static Future<bool> open(BuildContext context) async {
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LoginScreen()),
    );
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
  final _usernameController = TextEditingController();
  LoginMethod _method = LoginMethod.initial;
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
    // 离开页面时放弃未完成的验证码 / 浏览器授权，避免后台悬挂。
    // dispose 期间组件树已锁定，通知监听者需推迟到微任务
    final auth = _auth;
    Future.microtask(() {
      if (auth.isAwaitingCode) auth.cancelCode();
      if (auth.status == AuthStatus.authorizing) auth.cancelOAuth();
    });
    _usernameController.dispose();
    super.dispose();
  }

  /// 任意方式登录成功后关闭页面。
  void _onAuthChanged() {
    if (_finished || !_auth.isSignedIn || !mounted) return;
    _finished = true;
    TextInput.finishAutofillContext();
    final messenger = ScaffoldMessenger.of(context);
    final name = _auth.displayName;
    Navigator.of(context).pop(true);
    messenger.showSnackBar(SnackBar(content: Text('已登录为 $name')));
  }

  void _switchMethod(LoginMethod method) {
    _auth.clearError();
    setState(() => _method = method);
  }

  Future<void> _showMoreMethods() async {
    final method = await LoginMethodSheet.show(context);
    if (method != null && mounted) _switchMethod(method);
  }

  /// 左上角 / 系统返回：逐级后退（验证码 → 表单；授权等待 → 表单；其他方式 → 浏览器登录；浏览器登录 → 关闭）。
  void _back() {
    if (_auth.isAwaitingCode) {
      _auth.cancelCode();
    } else if (_auth.status == AuthStatus.authorizing) {
      _auth.cancelOAuth();
    } else if (_method != LoginMethod.initial) {
      _switchMethod(LoginMethod.initial);
    } else {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final atRoot = !auth.isAwaitingCode && auth.status != AuthStatus.authorizing && _method == LoginMethod.initial;

    final Widget stage;
    final String stageKey;
    if (auth.isAwaitingCode) {
      stage = CodeStage(onUseAnotherAccount: _auth.cancelCode);
      stageKey = 'code';
    } else {
      stageKey = _method.name;
      stage = switch (_method) {
        LoginMethod.desktop => DesktopStage(onSwitchMethod: _switchMethod, onMoreMethods: _showMoreMethods),
        LoginMethod.password => PasswordStage(
            usernameController: _usernameController,
            onSwitchMethod: _switchMethod,
            onMoreMethods: _showMoreMethods,
          ),
        LoginMethod.phone => const PhoneStage(),
        LoginMethod.oneTimeToken => const TokenStage(),
        LoginMethod.importCredential => const ImportStage(),
        LoginMethod.oauth => const OAuthStage(),
      };
    }

    return PopScope(
      canPop: atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !auth.isBusy) _back();
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
                        icon: Icon(atRoot ? Icons.close_rounded : Icons.arrow_back_rounded),
                        tooltip: atRoot ? '关闭' : '返回',
                        onPressed: auth.isBusy ? null : _back,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
                                child: child,
                              ),
                            ),
                            child: KeyedSubtree(key: ValueKey(stageKey), child: stage),
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

/// 页面顶部的品牌色环境光（极低透明度的径向渐变）。
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -1.1),
              radius: 1.1,
              colors: [MD3EColors.spotifyGreen.withAlpha(34), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}
