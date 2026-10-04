import 'package:flutify_app/core/utils/artwork_palette.dart';
import 'package:flutify_app/main.dart';
import 'package:flutify_app/models/playback_context.dart';
import 'package:flutify_app/models/track.dart';
import 'package:flutify_app/providers/playback_provider.dart';
import 'package:flutify_app/services/eme/eme_player.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/ui/screens/main_shell.dart';
import 'package:flutify_app/ui/screens/player/full_player_sheet.dart';
import 'package:flutify_app/ui/screens/player/lyrics/lyrics_view.dart';
import 'package:flutify_app/ui/screens/player/queue_list.dart';
import 'package:flutify_app/ui/screens/player/widgets/swipeable_artwork.dart';
import 'package:flutify_app/ui/shell/mobile/mobile_bottom_bar.dart';
import 'package:flutify_app/ui/widgets/mini_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_audio_player_service.dart';
import '../fakes/fake_track_audio_source.dart';

/// 移动端第 5 步界面：毛玻璃底部导航、胶囊迷你播放器、全屏播放器的内嵌视图与滑动切歌。
/// 只使用本文件内的合成曲目，不依赖任何账号或示例数据。
void main() {
  const tracks = [
    SpotifyTrack(id: 'synthetic-1', name: 'Synthetic One', durationMs: 180000),
    SpotifyTrack(id: 'synthetic-2', name: 'Synthetic Two', durationMs: 200000),
    SpotifyTrack(
      id: 'synthetic-3',
      name: 'Synthetic Three',
      durationMs: 220000,
    ),
  ];

  Future<PlaybackProvider> pumpPlaying(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ArtworkPalette.enabled = false;

    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    await tester.pumpWidget(
      FlutifyApp(
        storageService: storage,
        audioEngine: FakeAudioPlayerService(),
        emePlayer: EmePlayer(),
        spotifyApiService: SpotifyApiService(storage),
        trackAudioLoader: FakeTrackAudioSource(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final playback = Provider.of<PlaybackProvider>(
      tester.element(find.byType(MainShell)),
      listen: false,
    );
    await playback.playTrack(
      tracks.first,
      contextQueue: tracks,
      context: const PlaybackContext.playlist(
        'Synthetic Mix',
        uri: 'spotify:playlist:synthetic',
      ),
    );
    await settle(tester);
    return playback;
  }

  testWidgets('glass navigation bar with the pill mini player above it', (
    tester,
  ) async {
    await pumpPlaying(tester);

    final bar = find.byType(MobileBottomBar);
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.byType(MiniPlayer)),
      findsOneWidget,
    );
    // 迷你播放器在导航栏上方
    expect(
      tester.getBottomLeft(find.byType(MiniPlayer)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );
    expect(find.text('Synthetic One'), findsWidgets);
  });

  testWidgets('full player switches between artwork, lyrics and queue inline', (
    tester,
  ) async {
    await pumpPlaying(tester);

    await tester.tap(find.byType(MiniPlayer));
    await settle(tester);
    final player = find.byType(FullPlayerSheet);
    expect(
      find.descendant(of: player, matching: find.byType(SwipeableArtwork)),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: player, matching: find.byTooltip('播放队列')),
    );
    await settle(tester);
    expect(
      find.descendant(of: player, matching: find.byType(QueueList)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: player, matching: find.byType(SwipeableArtwork)),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: player, matching: find.byTooltip('歌词')),
    );
    await settle(tester);
    expect(
      find.descendant(of: player, matching: find.byType(LyricsView)),
      findsOneWidget,
    );
    expect(find.byTooltip('全屏歌词'), findsNothing);

    // 再点一次当前视图的按钮回到封面
    await tester.tap(
      find.descendant(of: player, matching: find.byTooltip('歌词')),
    );
    await settle(tester);
    expect(
      find.descendant(of: player, matching: find.byType(SwipeableArtwork)),
      findsOneWidget,
    );
  });

  testWidgets(
    'navigation pill reserves the bottom inset only outside its contents',
    (tester) async {
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 34);
      await pumpPlaying(tester);
      final nav = find.byType(NavigationBar);
      final pill = tester.getRect(nav);
      expect(pill.height, 64);
      expect(844 - pill.bottom, 34 + 12);
      for (final element in find.byType(NavigationDestination).evaluate()) {
        final destination = tester.getRect(find.byWidget(element.widget));
        expect(destination.center.dy, pill.center.dy);
      }
      await tester.tap(find.byIcon(Icons.search_rounded).first);
      await settle(tester);
      expect(tester.widget<NavigationBar>(nav).selectedIndex, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('swiping the artwork changes tracks', (tester) async {
    final playback = await pumpPlaying(tester);

    await tester.tap(find.byType(MiniPlayer));
    await settle(tester);

    await tester.drag(find.byType(SwipeableArtwork), const Offset(-220, 0));
    await settle(tester);
    expect(playback.currentTrack?.id, 'synthetic-2');

    // 小幅拖动不切歌，松手回弹
    await tester.drag(find.byType(SwipeableArtwork), const Offset(-20, 0));
    await settle(tester);
    expect(playback.currentTrack?.id, 'synthetic-2');
  });

  testWidgets('swiping lyrics down removes the sheet and its modal barrier', (
    tester,
  ) async {
    final playback = await pumpPlaying(tester);
    final originalBarriers = find.byType(ModalBarrier).evaluate().length;
    await tester.tap(find.byType(MiniPlayer));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(FullPlayerSheet),
        matching: find.byTooltip('歌词'),
      ),
    );
    await settle(tester);
    final close = find.descendant(
      of: find.byType(FullPlayerSheet),
      matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
    );
    await tester.fling(close, const Offset(0, 650), 1500);
    await playback.nextTrack();
    await settle(tester);
    expect(find.byType(FullPlayerSheet), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(originalBarriers));
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid repeated opens cannot leave a second player modal underneath',
    (tester) async {
      await pumpPlaying(tester);
      final originalBarriers = find.byType(ModalBarrier).evaluate().length;
      final context = tester.element(find.byType(MiniPlayer));
      FullPlayerSheet.show(context);
      FullPlayerSheet.show(context);
      await settle(tester);
      expect(find.byType(FullPlayerSheet, skipOffstage: false), findsOneWidget);
      await tester.fling(
        find.byIcon(Icons.keyboard_arrow_down_rounded).last,
        const Offset(0, 650),
        1500,
      );
      await settle(tester);
      expect(find.byType(ModalBarrier), findsNWidgets(originalBarriers));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('player opened from the mini player respects display cutouts', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 34);
    await pumpPlaying(tester);

    await tester.tap(find.byType(MiniPlayer));
    await settle(tester);
    final close = find.descendant(
      of: find.byType(FullPlayerSheet),
      matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
    );
    expect(tester.getTopLeft(close).dy, greaterThanOrEqualTo(48));

    await tester.tap(close);
    await settle(tester);
    expect(find.byType(FullPlayerSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'android: full player squares its top corners so they cover the screen',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpPlaying(tester);
      await tester.tap(find.byType(MiniPlayer));
      await settle(tester);
      debugDefaultTargetPlatformOverride = null;

      final clip = tester.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(FullPlayerSheet),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(clip.borderRadius, BorderRadius.zero);
      expect(tester.takeException(), isNull);
    },
  );

  for (final startsAsDialog in [false, true]) {
    testWidgets(
      'android: corners follow the open route after resize (dialog=$startsAsDialog)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await pumpPlaying(
          tester,
          size: startsAsDialog ? const Size(900, 1000) : const Size(700, 1000),
        );
        FullPlayerSheet.show(tester.element(find.byType(MainShell)));
        await settle(tester);
        BorderRadiusGeometry radius() => tester
            .widget<ClipRRect>(
              find
                  .descendant(
                    of: find.byType(FullPlayerSheet),
                    matching: find.byType(ClipRRect),
                  )
                  .first,
            )
            .borderRadius;
        final initialRadius = radius();
        expect(initialRadius == BorderRadius.zero, !startsAsDialog);
        tester.view.physicalSize = startsAsDialog
            ? const Size(700, 1000)
            : const Size(1000, 700);
        await settle(tester);
        debugDefaultTargetPlatformOverride = null;
        expect(
          find.byType(startsAsDialog ? Dialog : BottomSheet),
          findsOneWidget,
        );
        expect(radius(), initialRadius);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('other platforms keep the rounded top corners', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpPlaying(tester);
    await tester.tap(find.byType(MiniPlayer));
    await settle(tester);
    debugDefaultTargetPlatformOverride = null;

    final clip = tester.widget<ClipRRect>(
      find
          .descendant(
            of: find.byType(FullPlayerSheet),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(clip.borderRadius, isNot(BorderRadius.zero));
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
