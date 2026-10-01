import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/theme/system_bars.dart';
import 'core/utils/error_placeholder.dart';
import 'core/utils/orientation_policy.dart';
import 'l10n/app_locale.dart';
import 'providers/appearance_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/library_provider.dart';
import 'providers/playback_provider.dart';
import 'providers/spotify_provider.dart';
import 'services/audio_player_service.dart';
import 'services/auth/spotify_auth_service.dart';
import 'services/protocol/track_audio_loader.dart';
import 'services/spotify_api_service.dart';
import 'services/storage_service.dart';
import 'ui/screens/main_shell.dart';
import 'ui/shell/desktop/desktop_window.dart';
import 'ui/shell/desktop/window_frame.dart';
import 'ui/widgets/dynamic_accent_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorPlaceholder();

  // just_audio 自身没有 Windows / Linux 实现，需在创建任何 AudioPlayer 之前
  // 注册 media_kit 后端；Android / iOS 仍使用 just_audio 原生实现。
  JustAudioMediaKit.ensureInitialized();

  // 系统栏透明、内容铺满（edge-to-edge）；图标深浅由 FlutifyApp 按当前主题设置
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 手机锁定竖屏（平板 / 桌面不限制）
  await OrientationPolicy.apply();

  // Initialize Core Services
  final storageService = await StorageService.init();
  final audioPlayerService = AudioPlayerService();
  final spotifyApiService = SpotifyApiService(storageService);
  final authService = SpotifyAuthService(storageService);

  // 完整曲目协议链路：metadata → storage-resolve → AP 音频密钥 → CDN 解密。
  // access_token 每次取用前自动续期（与 API 层同一套凭据）。
  final supportDir = await getApplicationSupportDirectory();
  final trackAudioLoader = TrackAudioLoader(
    cacheDirectory: supportDir.path,
    deviceId: storageService.deviceId,
    accessToken: () async {
      try {
        await authService.ensureAccessToken();
      } catch (_) {}
      return storageService.accessToken;
    },
    clientToken: () => authService.ensureClientToken(),
  );

  // 桌面端：隐藏系统标题栏（由顶栏自绘）、设置最小窗口尺寸
  await DesktopWindow.init();

  runApp(
    FlutifyApp(
      storageService: storageService,
      audioPlayerService: audioPlayerService,
      spotifyApiService: spotifyApiService,
      authService: authService,
      trackAudioLoader: trackAudioLoader,
    ),
  );
}

class FlutifyApp extends StatelessWidget {
  final StorageService storageService;
  final AudioPlayerService audioPlayerService;
  final SpotifyApiService spotifyApiService;

  /// Login5 鉴权服务；为空时按 [storageService] 默认创建（测试可注入假实现）。
  final SpotifyAuthService? authService;

  /// 完整曲目音频来源（协议链路）；为空时任何曲目都无法播放（PlaybackProvider 报「请先登录」）。
  final TrackAudioSource? trackAudioLoader;

  const FlutifyApp({
    super.key,
    required this.storageService,
    required this.audioPlayerService,
    required this.spotifyApiService,
    this.authService,
    this.trackAudioLoader,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<AudioPlayerService>.value(value: audioPlayerService),
        Provider<SpotifyApiService>.value(value: spotifyApiService),
        // 非惰性：启动即接入 API 层，首屏请求就能自动续期 access_token
        Provider<SpotifyAuthService>(
          lazy: false,
          create: (_) {
            final auth = authService ?? SpotifyAuthService(storageService);
            spotifyApiService.attachAuth(auth);
            return auth;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => PlaybackProvider(
            audioPlayerService,
            storageService,
            audioLoader: trackAudioLoader,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => LibraryProvider(storageService, source: spotifyApiService.library),
        ),
        ChangeNotifierProvider(
          create: (_) => SpotifyProvider(spotifyApiService, storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => AppearanceProvider(storageService),
        ),
        // 登录态变化后：重新拉取主页数据与媒体库（未登录时清空）
        ChangeNotifierProvider(
          create: (ctx) => AuthProvider(ctx.read<SpotifyAuthService>())
            ..onSessionChanged = () {
              ctx.read<SpotifyProvider>().loadInitialData();
              ctx.read<LibraryProvider>().refresh();
            },
        ),
      ],
      child: const DynamicAccentSync(child: _ThemedApp()),
    );
  }
}

/// 按外观设置生成主题；字号缩放与减弱动效通过 MediaQuery 下发给整棵树。
class _ThemedApp extends StatelessWidget {
  const _ThemedApp();

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();
    final settings = appearance.settings;

    return MaterialApp(
      title: 'Flutify',
      debugShowCheckedModeBanner: false,
      // 界面固定简体中文；系统组件文案由 Global*Localizations 提供
      locale: AppLocale.locale,
      supportedLocales: AppLocale.supportedLocales,
      localizationsDelegates: AppLocale.delegates,
      themeMode: settings.themeMode,
      darkTheme: appearance.theme(Brightness.dark),
      theme: appearance.theme(Brightness.light),
      // 不做主题插值动画：默认 200ms 内每帧 lerp 整套 ThemeData 并重建全树，
      // 在设置页切换选项时会明显卡顿；改为单帧切换
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            // 用户字号与系统字号相乘
            textScaler: TextScaler.linear(media.textScaler.scale(1) * settings.fontScale),
            disableAnimations: media.disableAnimations || settings.reduceMotion,
          ),
          // 状态栏 / 导航栏图标随深浅色切换；全屏播放器等深色沉浸页面自行覆盖为浅色图标
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: systemBarsStyle(Theme.of(context).brightness),
            // 桌面：窗口按钮 / 窄窗口标题条覆盖在所有路由之上
            child: WindowFrame(child: child!),
          ),
        );
      },
      home: const MainShell(),
    );
  }
}
