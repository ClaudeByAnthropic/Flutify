import 'dart:async';

import 'package:flutify_app/core/utils/artwork_palette.dart';
import 'package:flutify_app/l10n/app_localizations.dart';
import 'package:flutify_app/models/connect_cluster.dart';
import 'package:flutify_app/providers/connect_provider.dart';
import 'package:flutify_app/providers/library_provider.dart';
import 'package:flutify_app/providers/playback_provider.dart';
import 'package:flutify_app/providers/spotify_provider.dart';
import 'package:flutify_app/services/connect/connect_service.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/ui/screens/player/device_picker_sheet.dart';
import 'package:flutify_app/ui/screens/player/immersive_lyrics_screen.dart';
import 'package:flutify_app/ui/screens/player/lyrics_sheet.dart';
import 'package:flutify_app/ui/shell/desktop/desktop_window.dart';
import 'package:flutify_app/ui/widgets/connect/remote_mini_player.dart';
import 'package:flutify_app/ui/widgets/connect/remote_player_bar.dart';
import 'package:flutify_app/ui/widgets/desktop_player_bar.dart';
import 'package:flutify_app/ui/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_audio_player_service.dart';

/// 假 Connect 服务：手动推送 cluster，记录收到的命令；[fail] 为 true 时命令全部失败。
class FakeConnectService implements ConnectService {
  final _clusters = StreamController<ConnectCluster>.broadcast();
  final _statuses = StreamController<ConnectStatus>.broadcast();
  final List<String> commands = [];
  bool fail = false;

  @override
  ConnectStatus status = ConnectStatus.idle;

  @override
  ConnectCluster current = ConnectCluster.empty;

  @override
  Stream<ConnectCluster> get clusters => _clusters.stream;

  @override
  Stream<ConnectStatus> get statusChanges => _statuses.stream;

  @override
  int get serverNowMs => current.serverTimestampMs;

  void push(ConnectCluster cluster) {
    current = cluster;
    _clusters.add(cluster);
  }

  void setStatus(ConnectStatus s) {
    status = s;
    _statuses.add(s);
  }

  Future<void> _record(String command) async {
    if (fail) throw const ConnectException(403, 'synthetic failure');
    commands.add(command);
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> transfer(String toDeviceId, {bool play = true}) => _record('transfer:$toDeviceId');

  @override
  Future<void> pause(String deviceId) => _record('pause:$deviceId');

  @override
  Future<void> resume(String deviceId) => _record('resume:$deviceId');

  @override
  Future<void> skipNext(String deviceId) => _record('next:$deviceId');

  @override
  Future<void> skipPrevious(String deviceId) => _record('prev:$deviceId');

  @override
  Future<void> seekTo(String deviceId, int positionMs) => _record('seek:$deviceId');

  @override
  Future<void> setShuffle(String deviceId, bool value) => _record('shuffle:$value');

  @override
  Future<void> setRepeat(String deviceId, {required bool context, required bool track}) =>
      _record('repeat:$context:$track');

  @override
  Future<void> setVolume(String deviceId, double volume) => _record('volume:$deviceId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 只使用合成数据的 cluster：一台正在播放的音箱 + 一台空闲手机。
ConnectCluster syntheticCluster({bool playing = true, bool withActive = true, bool withOthers = true}) {
  const speaker = ConnectDevice(
    id: 'synthetic-speaker',
    name: 'Synthetic Living Room Speaker With A Long Name',
    type: ConnectDeviceType.speaker,
    volume: 0.4,
    volumeSteps: 64,
  );
  const phone = ConnectDevice(id: 'synthetic-phone', name: 'Synthetic Phone', type: ConnectDeviceType.smartphone);
  return ConnectCluster(
    activeDeviceId: withActive ? speaker.id : '',
    devices: [if (withActive) speaker, if (withOthers) phone],
    serverTimestampMs: 1000000,
    player: withActive
        ? ConnectPlayerState(
            trackUri: 'spotify:track:synthetic0000000000000a',
            title: 'A Synthetic Remote Track With A Fairly Long Title',
            albumTitle: 'Synthetic Album',
            isPlaying: true,
            isPaused: !playing,
            positionMs: 30000,
            timestampMs: 1000000,
            durationMs: 200000,
          )
        : ConnectPlayerState.idle,
  );
}

void main() {
  late FakeConnectService service;
  late AppLocalizations zh;
  late StorageService storage;

  setUp(() {
    service = FakeConnectService();
    zh = lookupAppLocalizations(const Locale('zh'));
    ArtworkPalette.enabled = false;
  });

  Future<void> pumpHost(
    WidgetTester tester,
    Size size,
    Widget child, {
    ConnectCluster? cluster,
    bool available = true,
    double fontScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          // 未登录：歌词请求直接返回空，不联网
          ChangeNotifierProvider(create: (_) => SpotifyProvider(SpotifyApiService(storage), storage)),
          ChangeNotifierProvider(create: (_) => LibraryProvider(storage)),
          ChangeNotifierProvider(create: (_) => PlaybackProvider(FakeAudioPlayerService(), storage)),
          ChangeNotifierProvider(
            create: (_) => ConnectProvider(service, available: () => available, resolveTrack: (_) async => null),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(fontScale)),
            child: c!,
          ),
          home: Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: child),
          ),
        ),
      ),
    );
    if (cluster != null) {
      service.setStatus(ConnectStatus.online);
      service.push(cluster);
    }
    // 音柱持续动画：只推进固定时长，不等 settle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 卸载组件树，让进度定时器与动画随之释放。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  group('desktop player bar', () {
    for (final width in const [900.0, 1280.0, 1920.0]) {
      testWidgets('remote mode at ${width.round()} wide: strip, no overflow', (tester) async {
        await pumpHost(tester, Size(width, 700), const DesktopPlayerBar(), cluster: syntheticCluster());
        expect(find.byType(RemotePlayerBar), findsOneWidget);
        expect(find.text(zh.connectPlayingOn('Synthetic Living Room Speaker With A Long Name')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets('local mode when there is no remote session', (tester) async {
      await pumpHost(
        tester,
        const Size(1280, 700),
        const DesktopPlayerBar(),
        cluster: syntheticCluster(withActive: false),
      );
      expect(find.byType(RemotePlayerBar), findsNothing);
      expect(find.text(zh.playerIdleHint), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('transport buttons send commands to the active device', (tester) async {
      await pumpHost(tester, const Size(1280, 700), const DesktopPlayerBar(), cluster: syntheticCluster());
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pump();
      expect(service.commands, ['pause:synthetic-speaker', 'next:synthetic-speaker', 'shuffle:true']);
      await unmount(tester);
    });

    testWidgets('failed command shows a snackbar', (tester) async {
      await pumpHost(tester, const Size(1280, 700), const DesktopPlayerBar(), cluster: syntheticCluster());
      service.fail = true;
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(zh.connectCommandFailed), findsOneWidget);
      await unmount(tester);
    });
  });

  group('mobile mini player', () {
    for (final fontScale in const [1.0, 1.3]) {
      for (final width in const [320.0, 390.0]) {
        testWidgets('remote capsule at ${width.round()} wide, font ${(fontScale * 100).round()}%', (tester) async {
          await pumpHost(
            tester,
            Size(width, 700),
            const MiniPlayer(),
            cluster: syntheticCluster(playing: false),
            fontScale: fontScale,
          );
          expect(find.byType(RemoteMiniPlayer), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byIcon(Icons.play_arrow_rounded));
          await tester.pump();
          expect(service.commands, ['resume:synthetic-speaker']);
          await unmount(tester);
        });
      }
    }
  });

  group('device picker', () {
    Widget opener() => Builder(
      builder: (context) => TextButton(onPressed: () => DevicePickerSheet.show(context), child: const Text('open')),
    );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final size in const [Size(320, 640), Size(390, 844), Size(1280, 800)]) {
      testWidgets('lists devices without overflow at ${size.width.round()} wide', (tester) async {
        await pumpHost(tester, size, opener(), cluster: syntheticCluster(), fontScale: 1.3);
        await open(tester);
        expect(find.byType(DevicePickerSheet), findsOneWidget);
        expect(find.text('Synthetic Phone'), findsOneWidget);
        expect(find.text(zh.connectThisDevice), findsOneWidget);
        expect(find.byType(Slider), findsOneWidget);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets('tapping another device transfers playback and closes', (tester) async {
      await pumpHost(tester, const Size(1280, 800), opener(), cluster: syntheticCluster());
      await open(tester);
      await tester.tap(find.text('Synthetic Phone'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.commands, ['transfer:synthetic-phone']);
      expect(find.byType(DevicePickerSheet), findsNothing);
      await unmount(tester);
    });

    testWidgets('empty state when no other device is online', (tester) async {
      await pumpHost(tester, const Size(390, 844), opener(), cluster: const ConnectCluster(serverTimestampMs: 1));
      await open(tester);
      expect(find.text(zh.connectNoDevices), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('unavailable for non-desktop sessions', (tester) async {
      await pumpHost(tester, const Size(390, 844), opener(), available: false);
      await open(tester);
      expect(find.text(zh.connectUnavailable), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('connecting status line', (tester) async {
      await pumpHost(tester, const Size(390, 844), opener());
      service.setStatus(ConnectStatus.connecting);
      await open(tester);
      expect(find.text(zh.connectConnecting), findsOneWidget);
      await unmount(tester);
    });
  });

  group('remote lyrics', () {
    const remoteTitle = 'A Synthetic Remote Track With A Fairly Long Title';

    testWidgets('tapping the remote capsule opens lyrics with remote controls', (tester) async {
      await pumpHost(tester, const Size(390, 844), const MiniPlayer(), cluster: syntheticCluster(playing: false));
      await tester.tap(find.byType(RemoteMiniPlayer));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final sheet = find.byType(LyricsSheet);
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text(remoteTitle)), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 玻璃控制台的播放键发给远程设备，而不是本机
      await tester.tap(find.descendant(of: sheet, matching: find.byIcon(Icons.play_arrow_rounded)));
      await tester.pump();
      expect(service.commands, ['resume:synthetic-speaker']);
      await unmount(tester);
    });

    testWidgets('remote position drives the lyrics clock', (tester) async {
      await pumpHost(tester, const Size(390, 844), const SizedBox(), cluster: syntheticCluster());
      final connect = Provider.of<ConnectProvider>(tester.element(find.byType(Scaffold)), listen: false);
      // 快照：30s @ 服务端 1000000；服务端时间以快照为准，推算结果即快照进度
      expect(connect.position.value, const Duration(seconds: 30));
      expect(connect.displayTrack?.name, remoteTitle);
      await unmount(tester);
    });
  });

  group('immersive lyrics', () {
    Widget opener() => Builder(
      builder: (context) =>
          TextButton(onPressed: () => ImmersiveLyricsScreen.open(context), child: const Text('immersive')),
    );

    testWidgets('opens fitted to the window; F11 switches to the whole screen and is remembered', (tester) async {
      await pumpHost(tester, const Size(1280, 800), opener(), cluster: syntheticCluster());
      await tester.tap(find.text('immersive'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ImmersiveLyricsScreen), findsOneWidget);
      expect(find.text('A Synthetic Remote Track With A Fairly Long Title'), findsOneWidget);
      expect(DesktopWindow.immersiveWindow.value, isTrue);
      expect(storage.immersiveScreenFullscreen, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(DesktopWindow.immersiveWindow.value, isFalse);
      expect(storage.immersiveScreenFullscreen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ImmersiveLyricsScreen), findsNothing);
      expect(DesktopWindow.immersiveWindow.value, isFalse);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}
