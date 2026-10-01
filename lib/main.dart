import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/theme/system_bars.dart';
import 'core/utils/error_placeholder.dart';
import 'core/utils/orientation_policy.dart';
import 'l10n/app_locale.dart';
import 'models/app_preferences.dart';
import 'providers/appearance_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/connect_provider.dart';
import 'providers/library_provider.dart';
import 'providers/playback_provider.dart';
import 'providers/preferences_provider.dart';
import 'providers/sleep_timer_provider.dart';
import 'providers/spotify_provider.dart';
import 'services/audio_player_service.dart';
import 'services/auth/spotify_auth_service.dart';
import 'services/media_controls/connect_media_source.dart';
import 'services/media_controls/media_controls_sync.dart';
import 'services/media_controls/system_media_controls.dart';
import 'services/network/network_proxy.dart';
import 'services/playback_session_store.dart';
import 'services/protocol/audio_cache_store.dart';
import 'services/protocol/track_audio_loader.dart';
import 'services/spotify_api_service.dart';
import 'services/storage_service.dart';
import 'ui/screens/main_shell.dart';
import 'ui/shell/desktop/desktop_window.dart';
import 'ui/shell/desktop/window_frame.dart';
import 'ui/widgets/dynamic_accent_sync.dart';
import 'ui/widgets/playback_session_keeper.dart';

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

  // 网络代理须在任何网络客户端创建前就位；系统代理最多等 1.5 秒，读不到就先直连、后台补读
  ProxyHttpOverrides.install(NetworkProxy.instance);
  await NetworkProxy.instance
      .configure(AppPreferences.decode(storageService.preferencesJson))
      .timeout(const Duration(milliseconds: 1500), onTimeout: () {});

  final audioPlayerService = AudioPlayerService();
  final spotifyApiService = SpotifyApiService(storageService);
  final authService = SpotifyAuthService(storageService);

  // 完整曲目协议链路：metadata → storage-resolve → AP 音频密钥 → CDN 解密。
  // access_token 每次取用前自动续期（与 API 层同一套凭据）。
  final supportDir = await getApplicationSupportDirectory();
  // 解密放在常驻后台 Isolate：启动时预热，第一次播放不必等它启动
  final decryptBackend = IsolateDecryptBackend();
  unawaited(decryptBackend.warmUp());
  final trackAudioLoader = TrackAudioLoader(
    decryptBackend: decryptBackend,
    cacheDirectory: supportDir.path,
    maxCacheBytes: storageService.audioCacheLimitMb * 1024 * 1024,
    deviceId: storageService.deviceId,
    accessToken: () async {
      try {
        await authService.ensureAccessToken();
      } catch (_) {}
      return storageService.accessToken;
    },
    clientToken: () => authService.ensureClientToken(),
  );

  // 上次播放会话（曲目 / 队列 / 进度）：单独的 JSON 文件，不放进 SharedPreferences
  final sessionStore = FilePlaybackSessionStore(
    File('${supportDir.path}${Platform.pathSeparator}playback_session.json'),
  );

  // 桌面端：隐藏系统标题栏（由顶栏自绘）、设置最小窗口尺寸、还原上次的窗口位置
  await DesktopWindow.init(storageService);

  // 系统媒体控制：Windows SMTC（任务栏 / 锁屏媒体卡片、媒体键），Android / iOS 通知栏与锁屏
  final mediaControls = await SystemMediaControls.create();

  runApp(
    FlutifyApp(
      storageService: storageService,
      audioPlayerService: audioPlayerService,
      spotifyApiService: spotifyApiService,
      authService: authService,
      trackAudioLoader: trackAudioLoader,
      playbackSessionStore: sessionStore,
      mediaControls: mediaControls,
      networkProxy: NetworkProxy.instance,
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

  /// 上次播放会话的存储；为空时不还原、不保存（测试默认）。
  final PlaybackSessionStore? playbackSessionStore;

  /// 系统媒体控制；为空时不接入（测试、不支持的平台）。
  final SystemMediaControls? mediaControls;

  /// 网络代理策略；为空时设置页只显示模式、不探测系统代理（测试默认）。
  final NetworkProxy? networkProxy;

  const FlutifyApp({
    super.key,
    required this.storageService,
    required this.audioPlayerService,
    required this.spotifyApiService,
    this.authService,
    this.trackAudioLoader,
    this.playbackSessionStore,
    this.mediaControls,
    this.networkProxy,
  });

  @override
  Widget build(BuildContext context) {
    // 播放 Provider 创建时生成，Connect Provider 创建时接上远程转发（两个 create 各只执行一次）
    MediaControlsSync? mediaSync;
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<AudioPlayerService>.value(value: audioPlayerService),
        Provider<SpotifyApiService>.value(value: spotifyApiService),
        Provider<NetworkProxy?>.value(value: networkProxy),
        // 非惰性：启动即接入 API 层，首屏请求就能自动续期 access_token
        Provider<SpotifyAuthService>(
          lazy: false,
          create: (_) {
            final auth = authService ?? SpotifyAuthService(storageService);
            spotifyApiService.attachAuth(auth);
            // 关窗时若正好在续期，等新令牌落盘：进程会被立即结束，丢掉轮换后的 refresh_token 就得重新登录
            DesktopWindow.addBeforeCloseHook(auth.settle, timeout: const Duration(seconds: 5));
            return auth;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final playback = PlaybackProvider(
              audioPlayerService,
              storageService,
              audioLoader: trackAudioLoader,
              sessionStore: playbackSessionStore,
            );
            // 关窗前保存进度（进程退出时 Provider 不一定来得及 dispose）
            DesktopWindow.addBeforeCloseHook(playback.flushSession);
            // 与 App 同生命周期，不需要单独释放
            final controls = mediaControls;
            if (controls != null) mediaSync = MediaControlsSync(playback, controls);
            return playback;
          },
        ),
        ChangeNotifierProvider(create: (ctx) => SleepTimerProvider(ctx.read<PlaybackProvider>())),
        ChangeNotifierProvider(create: (_) => LibraryProvider(storageService, source: spotifyApiService.library)),
        ChangeNotifierProvider(create: (_) => SpotifyProvider(spotifyApiService, storageService)),
        ChangeNotifierProvider(create: (_) => AppearanceProvider(storageService)),
        ChangeNotifierProvider(
          create: (_) {
            final preferences = PreferencesProvider(storageService);
            final proxy = networkProxy;
            if (proxy == null) return preferences;
            // 设置页改了代理即时生效（只在代理相关字段变化时重配，避免无谓地重读系统代理）
            var proxyKey = _proxyKey(preferences.prefs);
            preferences.addListener(() {
              final key = _proxyKey(preferences.prefs);
              if (key == proxyKey) return;
              proxyKey = key;
              unawaited(proxy.configure(preferences.prefs));
            });
            return preferences;
          },
        ),
        // 设置页「存储」分组：音频缓存占用 / 上限 / 清除（未接入协议链路时为 null）
        Provider<AudioCacheStore?>.value(
          value: trackAudioLoader is AudioCacheStore ? trackAudioLoader as AudioCacheStore : null,
        ),
        // Spotify Connect 遥控：非惰性，启动即接入（桌面版会话且设置里未关闭），播放栏才能及时显示远程播放
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) {
            final playback = ctx.read<PlaybackProvider>();
            final connect = ConnectProvider(
              spotifyApiService.connect,
              available: () =>
                  spotifyApiService.supportsConnect && ctx.read<PreferencesProvider>().prefs.connectEnabled,
              resolveTrack: spotifyApiService.getTrackByUri,
            );
            // 在其他设备上播放时，系统媒体卡片显示并控制那台设备
            mediaSync?.override = ConnectMediaSource(connect, playback);
            // 本机开始播放 → 控制权回到本机（远程暂停后按键不再发给远程）；两者与 App 同生命周期
            playback.addListener(() {
              if (playback.isPlaying) connect.localPlaybackStarted();
            });
            return connect;
          },
        ),
        // 登录态变化后：重新拉取主页数据与媒体库（未登录时清空），Connect 重新接入或断开
        ChangeNotifierProvider(
          create: (ctx) => AuthProvider(ctx.read<SpotifyAuthService>())
            ..onSessionChanged = () {
              ctx.read<SpotifyProvider>().loadInitialData();
              ctx.read<LibraryProvider>().refresh();
              ctx.read<ConnectProvider>().sessionChanged();
            },
        ),
      ],
      child: const PlaybackSessionKeeper(child: DynamicAccentSync(child: _ThemedApp())),
    );
  }
}

/// 代理相关偏好的指纹，用于判断是否需要重配 [NetworkProxy]。
(ProxyMode, String, int) _proxyKey(AppPreferences prefs) => (prefs.proxyMode, prefs.proxyHost, prefs.proxyPort);

/// 按外观设置生成主题；字号缩放与减弱动效通过 MediaQuery 下发给整棵树。
class _ThemedApp extends StatelessWidget {
  const _ThemedApp();

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();
    final settings = appearance.settings;
    final language = context.select<PreferencesProvider, AppLanguage>((p) => p.prefs.language);

    return MaterialApp(
      title: 'Flutify',
      debugShowCheckedModeBanner: false,
      // 默认简体中文，可在设置里改为跟随系统 / English；系统组件文案由 Global*Localizations 提供
      locale: AppLocale.localeFor(language),
      supportedLocales: AppLocale.supportedLocales,
      localizationsDelegates: AppLocale.delegates,
      themeMode: settings.themeMode,
      darkTheme: appearance.theme(Brightness.dark),
      theme: appearance.theme(Brightness.light),
      // 不做主题插值动画：默认 200ms 内每帧 lerp 整套 ThemeData 并重建全树，
      // 在设置页切换选项时会明显卡顿；改为单帧切换
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        // 实际生效的界面语言决定请求 Spotify 时的 Accept-Language（主页文案等随之本地化）
        AppLocale.resolved(Localizations.localeOf(context));
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
