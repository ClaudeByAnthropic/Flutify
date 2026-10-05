import 'package:flutify_app/l10n/app_locale.dart';
import 'package:flutify_app/models/artist.dart';
import 'package:flutify_app/models/playlist.dart';
import 'package:flutify_app/models/track.dart';
import 'package:flutify_app/providers/library_provider.dart';
import 'package:flutify_app/providers/playback_provider.dart';
import 'package:flutify_app/providers/spotify_provider.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutify_app/ui/screens/search/search_screen.dart';
import 'package:flutify_app/ui/widgets/filter_pill.dart';
import 'package:flutify_app/ui/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/controlled_search_api.dart';
import '../fakes/fake_audio_player_service.dart';
import '../fixtures/search_pages.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('songs can continue past ten results at width $width', (
      tester,
    ) async {
      final api = await pumpSearch(tester, width);
      api.requests.single.result.complete(
        page(tracks: tracks(0, 10), nextTracks: 10),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterPill, 'Songs'));
      await tester.pump();

      final more = find.byKey(const ValueKey('search-load-more-tracks'));
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(more, 300, scrollable: scrollable);
      await tester.tap(more);
      await tester.pump();
      expect(api.requests.last.offset, 10);
      expect(
        find.byKey(const ValueKey('search-loading-tracks')),
        findsOneWidget,
      );
      api.requests.last.result.complete(
        page(tracks: tracks(10, 13), trackOffset: 10),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Track 12'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Track 12'), findsOneWidget);
      expect(more, findsNothing);
      final last = tester.widget<TrackTile>(
        find.ancestor(
          of: find.text('Track 12'),
          matching: find.byType(TrackTile),
        ),
      );
      expect(last.contextQueue, hasLength(13));
      expect(last.playbackContext?.name, 'music');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty parsed results retain continuation for each filter', (
    tester,
  ) async {
    final api = await pumpSearch(tester, 390);
    api.requests.single.result.complete(
      page(nextTracks: 20, nextArtists: 20, nextPlaylists: 20),
    );
    await tester.pump();
    for (final (label, type) in [
      ('Songs', 'tracks'),
      ('Artists', 'artists'),
      ('Playlists', 'playlists'),
    ]) {
      await tester.tap(find.widgetWithText(FilterPill, label));
      await tester.pump();
      final more = find.byKey(ValueKey('search-load-more-$type'));
      expect(more, findsOneWidget);
      await tester.tap(more);
      await tester.pump();
      expect(api.requests.last.type, type);
      expect(api.requests.last.offset, 20);
      api.requests.last.result.complete(switch (type) {
        'tracks' => page(
          tracks: const [SpotifyTrack(id: 'track', name: 'Found song')],
        ),
        'artists' => page(
          artists: const [SpotifyArtist(id: 'artist', name: 'Found artist')],
        ),
        _ => page(
          playlists: const [
            SpotifyPlaylist(id: 'playlist', name: 'Found playlist'),
          ],
        ),
      });
      await tester.pump();
      expect(more, findsNothing);
      expect(
        find.text(
          'Found ${type == 'tracks'
              ? 'song'
              : type == 'artists'
              ? 'artist'
              : 'playlist'}',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('paging error keeps existing results and offers retry', (
    tester,
  ) async {
    final api = await pumpSearch(tester, 390);
    api.requests.single.result.complete(
      page(
        artists: const [SpotifyArtist(id: 'artist', name: 'Existing artist')],
        nextArtists: 10,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-load-more-artists')));
    await tester.pump();
    api.requests.last.result.completeError(StateError('offline'));
    await tester.pump();
    expect(find.text('Existing artist'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    expect(api.requests.last.offset, 10);
    api.requests.last.result.complete(
      page(
        artists: const [SpotifyArtist(id: 'next', name: 'Next artist')],
      ),
    );
    await tester.pump();
    expect(find.text('Next artist'), findsOneWidget);
    expect(find.text('Existing artist'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('initial error is not presented as no results and can retry', (
    tester,
  ) async {
    final api = await pumpSearch(tester, 390);
    api.requests.single.result.completeError(StateError('offline'));
    await tester.pump();
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_off_rounded), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    api.requests.last.result.complete(
      page(
        artists: const [SpotifyArtist(id: 'artist', name: 'Recovered artist')],
      ),
    );
    await tester.pump();
    expect(find.text('Recovered artist'), findsOneWidget);
  });

  testWidgets('signed-out search offers sign in instead of a network retry', (
    tester,
  ) async {
    final api = await pumpSearch(tester, 390, signedIn: false);
    api.requests.single.result.completeError(SpotifyDataException.notSignedIn);
    await tester.pump();
    expect(find.text("Sign in to see what's here"), findsOneWidget);
    final signIn = find.widgetWithText(OutlinedButton, 'Sign in');
    expect(signIn, findsOneWidget);
    expect(tester.widget<OutlinedButton>(signIn).onPressed, isNotNull);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });
}

Future<ControlledSearchApi> pumpSearch(
  WidgetTester tester,
  double width, {
  bool signedIn = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final storage = await StorageService.init();
  final api = ControlledSearchApi(storage, signedIn: signedIn);
  final spotify = SpotifyProvider(api, storage);
  final audio = FakeAudioPlayerService();
  final playback = PlaybackProvider(audio, storage);
  final library = LibraryProvider(storage);
  final controller = TextEditingController(text: 'music');
  addTearDown(() {
    spotify.dispose();
    playback.dispose();
    library.dispose();
    controller.dispose();
    audio.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: spotify),
        ChangeNotifierProvider.value(value: playback),
        ChangeNotifierProvider.value(value: library),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocale.supportedLocales,
        localizationsDelegates: AppLocale.delegates,
        home: SearchScreen(controller: controller),
      ),
    ),
  );
  spotify.performSearch('music');
  await tester.pump(const Duration(milliseconds: 350));
  return api;
}
