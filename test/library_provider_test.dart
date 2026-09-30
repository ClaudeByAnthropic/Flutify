import 'package:flutify_app/core/constants/mock_spotify_data.dart';
import 'package:flutify_app/providers/library_provider.dart';
import 'package:flutify_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('liked songs persist across provider instances, newest first', () async {
    final storage = await StorageService.init();
    final library = LibraryProvider(storage);
    const track = MockSpotifyData.trackLevitating;

    if (library.isLiked(track.id)) library.toggleLike(track);
    library.toggleLike(track);
    expect(library.likedTracks.first.id, track.id);

    final reloaded = LibraryProvider(storage);
    expect(reloaded.isLiked(track.id), isTrue);
    expect(reloaded.likedTracks.first.id, track.id);
    expect(reloaded.likedTracks.first.album?.coverUrl, track.album?.coverUrl);
  });

  test('lists keep identity until they change (safe for context.select)', () async {
    final library = LibraryProvider(await StorageService.init());
    final before = library.playlists;
    final likedBefore = library.likedSongsPlaylist;

    library.toggleFollowArtist(MockSpotifyData.artistDuaLipa);
    expect(identical(library.playlists, before), isTrue);
    expect(identical(library.likedSongsPlaylist, likedBefore), isTrue);

    library.createPlaylist('Road Trip');
    expect(identical(library.playlists, before), isFalse);
  });

  test('own playlists accept tracks once and adopt the first cover', () async {
    final library = LibraryProvider(await StorageService.init());
    final created = library.createPlaylist('Focus');
    const track = MockSpotifyData.trackCruelSummer;

    expect(library.addTrackToPlaylist(created.id, track), isTrue);
    expect(library.addTrackToPlaylist(created.id, track), isFalse);

    final updated = library.findPlaylist(created.id)!;
    expect(updated.tracks.single.id, track.id);
    expect(updated.coverUrl, track.coverUrl);
    expect(library.ownPlaylists.map((p) => p.id), contains(created.id));
  });
}
