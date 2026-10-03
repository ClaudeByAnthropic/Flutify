import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'core/utils/file_log.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/theme/system_bars.dart';
import 'core/utils/error_placeholder.dart';
import 'core/utils/orientation_policy.dart';
import 'l10n/app_locale.dart';
import 'models/app_preferences.dart';
import 'models/playback_state.dart';
import 'providers/appearance_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/connect_provider.dart';
import 'providers/library_provider.dart';
import 'providers/playback_provider.dart';
import 'providers/preferences_provider.dart';
import 'providers/sleep_timer_provider.dart';
import 'providers/spotify_provider.dart';
import 'services/audio/audio_engine.dart';
import 'services/audio/routed_audio_engine.dart';
import 'services/audio_player_service.dart';
import 'services/auth/spotify_auth_service.dart';
import 'services/auth/web_token_service.dart';
import 'services/eme/eme_audio_engine.dart';
import 'services/eme/eme_player.dart';
import 'services/eme/license_client.dart';
import 'services/eme/native_drm_audio_engine.dart';
import 'services/eme/native_drm_player.dart';
import 'services/connect/connect_play_request.dart';
import 'services/connect/connect_service.dart';
import 'services/connect/receiver/connect_receiver.dart';
import 'services/connect/receiver/playback_receiver_host.dart';
import 'services/lyrics/lrclib_client.dart';
import 'services/lyrics/lrclib_lyrics_source.dart';
import 'services/lyrics/lyrics_disk_cache.dart';
import 'services/lyrics/lyrics_resolver.dart';
import 'services/media_controls/connect_media_source.dart';
import 'services/media_controls/media_controls_sync.dart';
import 'services/media_controls/multi_media_controls.dart';
import 'services/media_controls/system_media_controls.dart';
import 'services/network/network_proxy.dart';
import 'services/playback_session_store.dart';
import 'services/protocol/audio_cache_store.dart';
import 'services/protocol/eme_track_audio_source.dart';
import 'services/protocol/track_audio_loader.dart';
import 'services/spotify_api_service.dart';
import 'services/storage_service.dart';
import 'services/taskbar_lyrics/taskbar_lyrics_channel.dart';
import 'services/taskbar_lyrics/taskbar_lyrics_controls.dart';
import 'ui/screens/main_shell.dart';
import 'ui/shell/desktop/desktop_window.dart';
import 'ui/shell/desktop/window_frame.dart';
import 'ui/widgets/dynamic_accent_sync.dart';
import 'ui/widgets/playback_session_keeper.dart';
import 'ui/widgets/taskbar_lyrics_binding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installFileLog();
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
  final initialPrefs = AppPreferences.decode(storageService.preferencesJson);
  await NetworkProxy.instance
      .configure(
        mode: initialPrefs.proxyMode,
        proxyHost: initialPrefs.proxyHost,
        proxyPort: initialPrefs.proxyPort,
      )
      .timeout(const Duration(milliseconds: 1500), onTimeout: () {});

  final audioPlayerService = AudioPlayerService();
  final spotifyApiService = SpotifyApiService(storageService);
  final authService = SpotifyAuthService(storageService);

  // --- EME（Widevine）全曲播放链路 ---
  // Web token 服务：sp_dc + TOTP 铸造 Web 播放器 access_token（Widevine 真密钥所需）
  final webTokenService = WebTokenService(storageService);
  // 本地回环服务宿主：两类 DRM 引擎共用（清单/加密音频供给 + license·证书反代）
  final emePlayer = EmePlayer();
  await emePlayer.init(); // 先起本地服务
  // license 反代：CDM 请求体 → Spotify（用 Web token + client-token）。
  // 多入口：手机网络下 gae2-spclient 等域名会被掐 TLS 握手，spclient.wg 实测可达，
  // WidevineLicenseClient 按入口列表换域名重试（同一服务，路径一致）。
  final licenseClient = WidevineLicenseClient(
    webToken: webTokenService.ensureWebAccessToken,
    clientToken: authService.ensureClientToken,
  );
  // DRM 播放引擎按平台选：
  // - Android 真机证实 WebView EME 不可用（createMediaKeys 永不 settle），
  //   走原生 ExoPlayer + MediaDrm（下载/协议/反代层全复用，WebView 不起）；
  // - 桌面照旧无头 WebView2 + HLS.js。
  final AudioEngine drmEngine;
  if (Platform.isAndroid) {
    drmEngine = NativeDrmAudioEngine(
      server: emePlayer,
      player: NativeDrmPlayer(),
      licensePoster: licenseClient.postLicense,
      certFetcher: licenseClient.fetchCert,
    );
  } else {
    // 加载 HLS.js 引擎（资产打包，供隐藏页用）
    EmePlayer.hlsJsSource = await rootBundle.loadString('assets/js/hls.min.js');
    // 自定义 WebView2 环境（关自动播放手势限制，无头页无用户手势）
    await EmePlayer.ensureEnvironment();
    await emePlayer.start(); // 启动无头 WebView（窗口缩放/布局切换不影响播放）
    drmEngine = EmeAudioEngine(
      player: emePlayer,
      licensePoster: licenseClient.postLicense,
      certFetcher: licenseClient.fetchCert,
    );
  }
  // 路由引擎：本地文件/流式 → just_audio；DRM 曲目 → EME / 原生 DRM
  final audioEngine = RoutedAudioEngine(local: audioPlayerService, eme: drmEngine);

  // 上次播放会话（曲目 / 队列 / 进度）：单独的 JSON 文件，不放进 SharedPreferences
  final supportDir = await getApplicationSupportDirectory();
  final sessionStore = FilePlaybackSessionStore(
    File('${supportDir.path}${Platform.pathSeparator}playback_session.json'),
  );

  // 桌面端：隐藏系统标题栏（由顶栏自绘）、设置最小窗口尺寸、还原上次的窗口位置
  await DesktopWindow.init(storageService);

  // 系统媒体控制：Windows SMTC（任务栏 / 锁屏媒体卡片、媒体键），Android / iOS 通知栏与锁屏。
  // Windows 上再挂一个任务栏歌词，二者共用同一套本机 / 远程切换与按键路由
  final systemControls = await SystemMediaControls.create();
  final taskbarLyrics = Platform.isWindows
      ? TaskbarLyricsControls(MethodChannelTaskbarLyrics())
      : null;
  final mediaControls = taskbarLyrics == null
      ? systemControls
      : MultiMediaControls([?systemControls, taskbarLyrics]);

  // 歌词补全：Spotify 没有逐行同步歌词时查 LRCLIB，选中的歌词缓存在应用数据目录
  final lyricsFallback = LrclibLyricsSource(
    LrclibClient(http.Client()),
    cache: LyricsDiskCache(
      Directory('${supportDir.path}${Platform.pathSeparator}lyrics_lrc'),
    ),
  );

  // EME 曲目源（Widevine 全曲播放）：AP 密钥被拒的 DRM 曲目走这里。
  // 当前账号 AP RequestKey 全线被拒，EME 是全曲播放的主链路。
  final emeTrackSource = EmeTrackAudioSource(
    cacheDirectory: supportDir.path,
    // 缺 sp_dc（Web 登录态）时在下载前拦截，引导用户完成 Web 登录
    webSessionReady: () => webTokenService.hasSpDc,
    accessToken: () async {
      try {
        await authService.ensureAccessToken();
      } catch (_) {}
      return storageService.accessToken;
    },
    clientToken: () => authService.ensureClientToken(),
  );

  runApp(
    FlutifyApp(
      storageService: storageService,
      audioEngine: audioEngine,
      emePlayer: emePlayer,
      spotifyApiService: spotifyApiService,
      authService: authService,
      webTokenService: webTokenService,
      trackAudioLoader: emeTrackSource,
      playbackSessionStore: sessionStore,
      mediaControls: mediaControls,
      networkProxy: NetworkProxy.instance,
      lyricsFallback: lyricsFallback,
      taskbarLyrics: taskbarLyrics,
    ),
  );
}

class FlutifyApp extends StatelessWidget {
  final StorageService storageService;
  final AudioEngine audioEngine;

  /// EME 播放器（无头 WebView2，不进 widget 树）。
  final EmePlayer emePlayer;
  final SpotifyApiService spotifyApiService;

  /// Login5 鉴权服务；为空时按 [storageService] 默认创建（测试可注入假实现）。
  final SpotifyAuthService? authService;

  /// Web token 服务（sp_dc + TOTP 铸 Web access_token）；为空时设置页不显示 Web 登录入口（测试默认）。
  final WebTokenService? webTokenService;

  /// 完整曲目音频来源（协议链路）；为空时任何曲目都无法播放（PlaybackProvider 报「请先登录」）。
  final TrackAudioSource? trackAudioLoader;

  /// 上次播放会话的存储；为空时不还原、不保存（测试默认）。
  final PlaybackSessionStore? playbackSessionStore;

  /// 系统媒体控制；为空时不接入（测试、不支持的平台）。
  final SystemMediaControls? mediaControls;

  /// 网络代理策略；为空时设置页只显示模式、不探测系统代理（测试默认）。
  final NetworkProxy? networkProxy;

  /// LRCLIB 歌词补全；为空时只用 Spotify 官方歌词（测试默认）。
  final LrclibLyricsSource? lyricsFallback;

  /// 任务栏歌词（Windows）；已包含在 [mediaControls] 里，这里供界面层绑定设置与歌词来源。
  final TaskbarLyricsControls? taskbarLyrics;

  const FlutifyApp({
    super.key,
    required this.storageService,
    required this.audioEngine,
    required this.emePlayer,
    required this.spotifyApiService,
    this.authService,
    this.webTokenService,
    this.trackAudioLoader,
    this.playbackSessionStore,
    this.mediaControls,
    this.networkProxy,
    this.lyricsFallback,
    this.taskbarLyrics,
  });

  @override
  Widget build(BuildContext context) {
    // 播放 Provider 创建时生成，Connect Provider 创建时接上远程转发（两个 create 各只执行一次）
    MediaControlsSync? mediaSync;
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<AudioEngine>.value(value: audioEngine),
        Provider<EmePlayer>.value(value: emePlayer),
        Provider<SpotifyApiService>.value(value: spotifyApiService),
        if (webTokenService != null) Provider<WebTokenService>.value(value: webTokenService!),
        Provider<NetworkProxy?>.value(value: networkProxy),
        // 非惰性：启动即接入 API 层，首屏请求就能自动续期 access_token
        Provider<SpotifyAuthService>(
          lazy: false,
          create: (_) {
            final auth = authService ?? SpotifyAuthService(storageService);
            spotifyApiService.attachAuth(auth);
            // 关窗时若正好在续期，等新令牌落盘：进程会被立即结束，丢掉轮换后的 refresh_token 就得重新登录
            DesktopWindow.addBeforeCloseHook(
              auth.settle,
              timeout: const Duration(seconds: 5),
            );
            return auth;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final playback = PlaybackProvider(
              audioEngine,
              storageService,
              audioLoader: trackAudioLoader,
              sessionStore: playbackSessionStore,
            );
            // 关窗前保存进度（进程退出时 Provider 不一定来得及 dispose）
            DesktopWindow.addBeforeCloseHook(playback.flushSession);
            // 与 App 同生命周期，不需要单独释放
            final controls = mediaControls;
            if (controls != null)
              mediaSync = MediaControlsSync(playback, controls);
            return playback;
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) => SleepTimerProvider(ctx.read<PlaybackProvider>()),
        ),
        ChangeNotifierProvider(
          create: (_) => LibraryProvider(
            storageService,
            source: spotifyApiService.library,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AppearanceProvider(storageService),
        ),
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
              unawaited(
                proxy.configure(
                  mode: preferences.prefs.proxyMode,
                  proxyHost: preferences.prefs.proxyHost,
                  proxyPort: preferences.prefs.proxyPort,
                ),
              );
            });
            return preferences;
          },
        ),
        // 在 PreferencesProvider 之后创建：歌词补全开关在每次取歌词时读取
        ChangeNotifierProvider(
          create: (ctx) => SpotifyProvider(
            spotifyApiService,
            storageService,
            lyrics: LyricsResolver(
              spotifyApiService.getLyrics,
              fallback: lyricsFallback,
              fallbackEnabled: () =>
                  ctx.read<PreferencesProvider>().prefs.lyricsFallback,
            ),
          ),
        ),
        Provider<TaskbarLyricsControls?>.value(value: taskbarLyrics),
        // 设置页「存储」分组：音频缓存占用 / 上限 / 清除
        Provider<AudioCacheStore?>.value(
          value: trackAudioLoader is AudioCacheStore
              ? trackAudioLoader as AudioCacheStore
              : null,
        ),
        // Spotify Connect 遥控：非惰性，启动即接入（桌面版会话且设置里未关闭），播放栏才能及时显示远程播放
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) {
            final playback = ctx.read<PlaybackProvider>();
            final connect = ConnectProvider(
              spotifyApiService.connect,
              available: () =>
                  spotifyApiService.supportsConnect &&
                  ctx.read<PreferencesProvider>().prefs.connectEnabled,
              resolveTrack: spotifyApiService.getTrackByUri,
            );
            // 在其他设备上播放时，系统媒体卡片显示并控制那台设备
            mediaSync?.override = ConnectMediaSource(connect, playback);
            // 本机开始播放 → 控制权回到本机（远程暂停后按键不再发给远程）；两者与 App 同生命周期
            playback.addListener(() {
              if (playback.isPlaying) connect.localPlaybackStarted();
            });
            // 播放栏处于远程模式时，点歌默认在那台设备上播放；无法远程（本地文件）或命令失败时回到本机播放
            playback.remotePlay = (context, tracks, start) async {
              // 存在活动的远程设备且本机没在出声就一律走远程。不再依赖 controlsRemote 的“最后出声方”推断：
              // 切换曲目瞬间远程会短暂处于暂停 / 缓冲状态，那会误判为本机并回退到本机播放。
              final request = ConnectPlayRequest.from(
                context: context,
                tracks: tracks,
                start: start,
                username: ctx.read<SpotifyAuthService>().username,
              );
              final toRemote = connect.activeDevice != null && !playback.isPlaying;
              debugPrint(
                '[Connect] 点歌：request=${request == null ? 'null' : 'ok'} '
                'active=${connect.activeDevice?.name} localPlaying=${playback.isPlaying} '
                'receiverOnline=${connect.receiverOnline}',
              );
              if (request == null) return false;
              if (!toRemote) {
                // 本机播放端在线：经 Connect 下发给自己，同账号其他设备才能同步看到
                if (!connect.receiverOnline) {
                  debugPrint(
                    '[Connect] 本机播放端不在设备列表（${connect.receiverDeviceId}），'
                    '列表：${connect.cluster.devices.map((d) => '${d.name}=${d.id}').join(', ')}',
                  );
                  return false;
                }
                try {
                  await connect.playOnReceiver(request);
                  return true;
                } on ConnectException catch (e) {
                  debugPrint('[Connect] 下发到本机播放端失败，直接本机播放：$e');
                  return false;
                }
              }
              try {
                await connect.play(request);
                return true;
              } on ConnectException catch (e) {
                debugPrint('[Connect] 远程播放失败，改在本机播放：$e');
                return false;
              }
            };
            _startConnectReceiver(ctx, connect, playback);
            return connect;
          },
        ),
        // 登录态变化后：重新拉取主页数据与媒体库（未登录时清空），Connect 重新接入或断开
        ChangeNotifierProvider(
          create: (ctx) {
            late final AuthProvider auth;
            auth = AuthProvider(ctx.read<SpotifyAuthService>())
              ..onSessionChanged = () {
                ctx.read<SpotifyProvider>().loadInitialData();
                ctx.read<LibraryProvider>().refresh();
                ctx.read<ConnectProvider>().sessionChanged();
                // 登出 / 切换账号：上次播放会话属于旧账号，随登录态一起清除
                if (!auth.isSignedIn) {
                  unawaited(ctx.read<PlaybackProvider>().discardSession());
                }
              };
            return auth;
          },
        ),
      ],
      child: const PlaybackSessionKeeper(
        child: DynamicAccentSync(child: _ThemedApp()),
      ),
    );
  }
}

/// Connect 播放端：让 Flutify 出现在其他设备的设备列表里。
/// 需要 Web 登录态（sp_dc），随设置里的「Spotify Connect」开关启停；关窗前注销设备。
void _startConnectReceiver(
  BuildContext ctx,
  ConnectProvider connect,
  PlaybackProvider playback,
) {
  final tokens = ctx.read<WebTokenService?>();
  if (tokens == null) return;
  final preferences = ctx.read<PreferencesProvider>();
  final deviceId =
      md5.convert(utf8.encode('flutify-receiver:${Platform.localHostname}')).toString() +
      sha1.convert(utf8.encode('flutify')).toString().substring(0, 8);
  final host = PlaybackReceiverHost(playback);
  String nameOf() {
    final name = preferences.prefs.connectDeviceName;
    return name.isEmpty ? ConnectReceiver.defaultDeviceName : name;
  }

  final receiver = ConnectReceiver(
    host: host,
    deviceName: nameOf,
    client: http.Client(),
    webToken: tokens.ensureWebAccessToken,
    deviceId: deviceId,
  );
  host.receiver = receiver;
  connect.receiverDeviceId = deviceId;
  Future<void> handOver(int positionMs, {bool paused = false}) async {
    final current = playback.currentTrack;
    if (current == null || !connect.receiverOnline) return;
    final request = ConnectPlayRequest.from(
      context: playback.playbackContext,
      tracks: [current, for (final e in playback.upNext) e.track],
      start: current,
      username: ctx.read<SpotifyAuthService>().username,
    );
    if (request == null) return;
    debugPrint('[Receiver] 交接给 Connect：${current.name} @${positionMs}ms paused=$paused');
    try {
      await connect.playOnReceiver(request, seekToMs: positionMs, paused: paused);
    } catch (e) {
      debugPrint('[Receiver] 交接失败：$e');
    }
  }

  host.handOver = handOver;
  host.onLocalOptions = (shuffle, repeat) {
    unawaited(
      connect
          .setReceiverOptions(
            shuffle: shuffle,
            repeatContext: repeat != SpotifyRepeatMode.off,
            repeatTrack: repeat == SpotifyRepeatMode.track,
          )
          .catchError((Object e) => debugPrint('[Receiver] 同步随机 / 循环失败：$e')),
    );
  };

  // 「启动时同步播放状态」：每次启动只做一次。注册后要等设备出现在 cluster 里（推送有延迟），
  // 本机未播放、其他设备也没在出声时，把上次的曲目以暂停状态同步出去
  var launchSynced = false;
  receiver.onRegistered = () async {
    if (launchSynced || !preferences.prefs.connectReportOnLaunch) return;
    launchSynced = true;
    for (var i = 0; i < 20 && !connect.receiverOnline; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final remoteAudible = connect.activeDevice != null && connect.player.isAudible;
    if (playback.isPlaying || receiver.isActive || remoteAudible) return;
    await handOver(playback.position.inMilliseconds, paused: true);
  };

  var running = false;
  var name = nameOf();
  void apply() {
    final want = tokens.hasSpDc && preferences.prefs.connectEnabled;
    // 改名：注销后用新名字重新注册
    if (running && want && nameOf() != name) {
      name = nameOf();
      unawaited(receiver.stop().then((_) => receiver.start()));
      return;
    }
    name = nameOf();
    if (want == running) return;
    running = want;
    unawaited(want ? receiver.start() : receiver.stop());
  }

  preferences.addListener(apply);
  apply();
  DesktopWindow.addBeforeCloseHook(
    receiver.stop,
    timeout: const Duration(seconds: 3),
  );
}

/// 代理相关偏好的指纹，用于判断是否需要重配 [NetworkProxy]。
(ProxyMode, String, int) _proxyKey(AppPreferences prefs) =>
    (prefs.proxyMode, prefs.proxyHost, prefs.proxyPort);

/// 按外观设置生成主题；字号缩放与减弱动效通过 MediaQuery 下发给整棵树。
class _ThemedApp extends StatelessWidget {
  const _ThemedApp();

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceProvider>();
    final settings = appearance.settings;
    final language = context.select<PreferencesProvider, AppLanguage>(
      (p) => p.prefs.language,
    );

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
            textScaler: TextScaler.linear(
              media.textScaler.scale(1) * settings.fontScale,
            ),
            disableAnimations: media.disableAnimations || settings.reduceMotion,
          ),
          // 状态栏 / 导航栏图标随深浅色切换；全屏播放器等深色沉浸页面自行覆盖为浅色图标
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: systemBarsStyle(Theme.of(context).brightness),
            // 桌面：窗口按钮 / 窄窗口标题条覆盖在所有路由之上
            child: TaskbarLyricsBinding(
              child: WindowFrame(child: child!),
            ),
          ),
        );
      },
      home: const MainShell(),
    );
  }
}
