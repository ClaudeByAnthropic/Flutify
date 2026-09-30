import 'package:flutify_app/core/constants/mock_spotify_data.dart';
import 'package:flutify_app/providers/spotify_provider.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SpotifyProvider spotify;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.init();
    spotify = SpotifyProvider(SpotifyApiService(storage), storage);
  });

  tearDown(() => spotify.dispose());

  test('rapid typing only applies the latest query', () async {
    spotify.performSearch('b');
    spotify.performSearch('bl');
    spotify.performSearch('cruel');
    expect(spotify.isSearching, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(spotify.isSearching, isFalse);
    expect(spotify.searchTracks.map((t) => t.id), [MockSpotifyData.trackCruelSummer.id]);
  });

  test('recent searches are deduplicated and persisted', () {
    spotify.commitRecentSearch('weeknd');
    spotify.commitRecentSearch('dua');
    spotify.commitRecentSearch('weeknd');

    expect(spotify.recentSearches, ['weeknd', 'dua']);
    expect(storage.recentSearches, ['weeknd', 'dua']);
  });

  test('lyrics are cached after the first fetch', () async {
    final id = MockSpotifyData.trackBlindingLights.id;
    expect(spotify.cachedLyrics(id), isNull);

    final lyrics = await spotify.fetchLyrics(id);
    expect(lyrics.lines, isNotEmpty);
    expect(identical(spotify.cachedLyrics(id), lyrics), isTrue);
  });
}
