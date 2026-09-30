import 'package:flutter/material.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/category.dart';
import '../../models/device.dart';
import '../../models/image.dart';
import '../../models/lyrics.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../models/user_profile.dart';

class MockSpotifyData {
  MockSpotifyData._();

  // Current User
  static const currentUser = SpotifyUser(
    id: 'user_flutify_pro',
    displayName: 'Alex Rivers',
    email: 'alex.rivers@example.com',
    product: 'premium',
    country: 'US',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300&q=80'),
    ],
  );

  // Sample Audio URLs (Reliable open test streams)
  static const sampleAudio1 = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
  static const sampleAudio2 = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3';
  static const sampleAudio3 = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3';
  static const sampleAudio4 = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3';

  // Artists
  static const artistTheWeeknd = SpotifyArtist(
    id: '1Xyo4u8uXC1ZmMpatF05PJ',
    name: 'The Weeknd',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&q=80'),
    ],
    genres: ['canadian contemporary r&b', 'pop', 'canadian pop'],
    followers: 114500000,
    popularity: 96,
  );

  static const artistTaylorSwift = SpotifyArtist(
    id: '06HL4z0CvFAxyc27GXpf02',
    name: 'Taylor Swift',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=600&q=80'),
    ],
    genres: ['pop'],
    followers: 121000000,
    popularity: 98,
  );

  static const artistBillieEilish = SpotifyArtist(
    id: '6qqNVTkY8uBg9cP3Jd7DAH',
    name: 'Billie Eilish',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1526478806334-5fd488fcaabc?w=600&q=80'),
    ],
    genres: ['art pop', 'electropop', 'pop'],
    followers: 94000000,
    popularity: 94,
  );

  static const artistDuaLipa = SpotifyArtist(
    id: '6M2wZ9GZgrQXHCFfjv46we',
    name: 'Dua Lipa',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=600&q=80'),
    ],
    genres: ['dance pop', 'pop', 'uk pop'],
    followers: 47000000,
    popularity: 90,
  );

  // Albums
  static const albumAfterHours = SpotifyAlbum(
    id: '4yP0hdKOZPNshxUOjY0cZj',
    name: 'After Hours',
    albumType: 'album',
    releaseDate: '2020-03-20',
    totalTracks: 14,
    artists: [artistTheWeeknd],
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?w=600&q=80'),
    ],
  );

  static const album1989 = SpotifyAlbum(
    id: '1o59UpKw81CVHR0QY2tCGv',
    name: "1989 (Taylor's Version)",
    albumType: 'album',
    releaseDate: '2023-10-27',
    totalTracks: 21,
    artists: [artistTaylorSwift],
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=600&q=80'),
    ],
  );

  static const albumHitMeHard = SpotifyAlbum(
    id: '7aJuG4MyrZwDXBkgnxC4Qw',
    name: 'HIT ME HARD AND SOFT',
    albumType: 'album',
    releaseDate: '2024-05-17',
    totalTracks: 10,
    artists: [artistBillieEilish],
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=600&q=80'),
    ],
  );

  static const albumFutureNostalgia = SpotifyAlbum(
    id: '04uhhcjGVCHiYOL1gqPgt0',
    name: 'Future Nostalgia',
    albumType: 'album',
    releaseDate: '2020-03-27',
    totalTracks: 11,
    artists: [artistDuaLipa],
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=600&q=80'),
    ],
  );

  // Tracks
  static const trackBlindingLights = SpotifyTrack(
    id: '0VjIjW4GlUZAMYd2vXMi3b',
    name: 'Blinding Lights',
    uri: 'spotify:track:0VjIjW4GlUZAMYd2vXMi3b',
    artists: [artistTheWeeknd],
    album: albumAfterHours,
    durationMs: 200040,
    streamUrl: sampleAudio1,
    previewUrl: sampleAudio1,
    explicit: false,
    popularity: 96,
  );

  static const trackCruelSummer = SpotifyTrack(
    id: '1BxfuPKGuaTgP7aM0XbdQA',
    name: 'Cruel Summer',
    uri: 'spotify:track:1BxfuPKGuaTgP7aM0XbdQA',
    artists: [artistTaylorSwift],
    album: album1989,
    durationMs: 178426,
    streamUrl: sampleAudio2,
    previewUrl: sampleAudio2,
    explicit: false,
    popularity: 95,
  );

  static const trackBirdsOfAFeather = SpotifyTrack(
    id: '6dOtVTDmmpzgemJQIjvvzy',
    name: 'BIRDS OF A FEATHER',
    uri: 'spotify:track:6dOtVTDmmpzgemJQIjvvzy',
    artists: [artistBillieEilish],
    album: albumHitMeHard,
    durationMs: 195386,
    streamUrl: sampleAudio3,
    previewUrl: sampleAudio3,
    explicit: false,
    popularity: 97,
  );

  static const trackLevitating = SpotifyTrack(
    id: '463CkQjx2Zk1yXoBuEVdQI',
    name: 'Levitating',
    uri: 'spotify:track:463CkQjx2Zk1yXoBuEVdQI',
    artists: [artistDuaLipa],
    album: albumFutureNostalgia,
    durationMs: 203807,
    streamUrl: sampleAudio4,
    previewUrl: sampleAudio4,
    explicit: false,
    popularity: 88,
  );

  static const trackSaveYourTears = SpotifyTrack(
    id: '5QO792alvyNGqNZowuv2Pt',
    name: 'Save Your Tears',
    uri: 'spotify:track:5QO792alvyNGqNZowuv2Pt',
    artists: [artistTheWeeknd],
    album: albumAfterHours,
    durationMs: 215626,
    streamUrl: sampleAudio1,
    previewUrl: sampleAudio1,
    explicit: false,
    popularity: 91,
  );

  static const trackStyle = SpotifyTrack(
    id: '0ug5MNKbricDYBGwgIQRz3',
    name: "Style (Taylor's Version)",
    uri: 'spotify:track:0ug5MNKbricDYBGwgIQRz3',
    artists: [artistTaylorSwift],
    album: album1989,
    durationMs: 231000,
    streamUrl: sampleAudio2,
    previewUrl: sampleAudio2,
    explicit: false,
    popularity: 89,
  );

  static const trackLunch = SpotifyTrack(
    id: '629DXB9mB0k7N9W8l0qQkY',
    name: 'LUNCH',
    uri: 'spotify:track:629DXB9mB0k7N9W8l0qQkY',
    artists: [artistBillieEilish],
    album: albumHitMeHard,
    durationMs: 179880,
    streamUrl: sampleAudio3,
    previewUrl: sampleAudio3,
    explicit: true,
    popularity: 93,
  );

  static const trackDonotStartNow = SpotifyTrack(
    id: '6WrI0LAC5M1Rw2MnX2ZvEg',
    name: "Don't Start Now",
    uri: 'spotify:track:6WrI0LAC5M1Rw2MnX2ZvEg',
    artists: [artistDuaLipa],
    album: albumFutureNostalgia,
    durationMs: 183293,
    streamUrl: sampleAudio4,
    previewUrl: sampleAudio4,
    explicit: false,
    popularity: 87,
  );

  // All sample tracks
  static const List<SpotifyTrack> allTracks = [
    trackBlindingLights,
    trackCruelSummer,
    trackBirdsOfAFeather,
    trackLevitating,
    trackSaveYourTears,
    trackStyle,
    trackLunch,
    trackDonotStartNow,
  ];

  // Playlists
  static const playlistTodaysTopHits = SpotifyPlaylist(
    id: '37i9dQZF1DXcBWIGoYBM5M',
    name: "Today's Top Hits",
    description: 'Sabrina Carpenter is on top of the Hottest 50! Cover: Sabrina Carpenter',
    ownerName: 'Spotify',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&q=80'),
    ],
    tracks: [
      trackBirdsOfAFeather,
      trackCruelSummer,
      trackBlindingLights,
      trackLunch,
      trackLevitating,
      trackSaveYourTears,
    ],
    totalTracks: 50,
    primaryColor: '#1E3264',
  );

  static const playlistChillHits = SpotifyPlaylist(
    id: '37i9dQZF1DX4WYpdgoIcn6',
    name: 'Chill Hits',
    description: 'Kick back to the best new and recent chill hits.',
    ownerName: 'Spotify',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=600&q=80'),
    ],
    tracks: [
      trackBirdsOfAFeather,
      trackSaveYourTears,
      trackStyle,
      trackCruelSummer,
    ],
    totalTracks: 85,
    primaryColor: '#3C4043',
  );

  static const playlistRapCaviar = SpotifyPlaylist(
    id: '37i9dQZF1DX0XUsuxWHRQd',
    name: 'RapCaviar',
    description: 'Music from Kendrick Lamar, Drake, Metro Boomin and more.',
    ownerName: 'Spotify',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=600&q=80'),
    ],
    tracks: [
      trackLunch,
      trackBlindingLights,
      trackDonotStartNow,
    ],
    totalTracks: 60,
    primaryColor: '#BA5D00',
  );

  static const playlistDiscoverWeekly = SpotifyPlaylist(
    id: '37i9dQZEVXcQ90huJStOUi',
    name: 'Discover Weekly',
    description: 'Your weekly mixtape of fresh music. Enjoy new music and deep cuts picked just for you.',
    ownerName: 'Spotify',
    images: [
      SpotifyImage(url: 'https://images.unsplash.com/photo-1511379938547-c1f69419868d?w=600&q=80'),
    ],
    tracks: [
      trackCruelSummer,
      trackBirdsOfAFeather,
      trackStyle,
      trackLevitating,
    ],
    totalTracks: 30,
    primaryColor: '#477D95',
  );

  static const playlistLikedSongs = SpotifyPlaylist(
    id: 'liked_songs_collection',
    name: 'Liked Songs',
    description: 'All your favorite songs in one place.',
    ownerName: 'Alex Rivers',
    images: [
      SpotifyImage(url: 'https://misc.scdn.co/liked-songs/liked-songs-640.png'),
    ],
    tracks: [
      trackBlindingLights,
      trackBirdsOfAFeather,
      trackCruelSummer,
      trackLevitating,
      trackSaveYourTears,
      trackLunch,
      trackStyle,
      trackDonotStartNow,
    ],
    totalTracks: 8,
    primaryColor: '#450af5',
  );

  static const List<SpotifyPlaylist> allPlaylists = [
    playlistLikedSongs,
    playlistTodaysTopHits,
    playlistChillHits,
    playlistRapCaviar,
    playlistDiscoverWeekly,
  ];

  // Browse Categories
  static const List<SpotifyCategory> categories = [
    SpotifyCategory(
      id: 'pop',
      name: 'Pop',
      iconUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300&q=80',
      color: Color(0xFFE1306C),
    ),
    SpotifyCategory(
      id: 'hiphop',
      name: 'Hip-Hop',
      iconUrl: 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=300&q=80',
      color: Color(0xFFBA5D07),
    ),
    SpotifyCategory(
      id: 'dance',
      name: 'Dance / Electronic',
      iconUrl: 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=300&q=80',
      color: Color(0xFF00B0FF),
    ),
    SpotifyCategory(
      id: 'rock',
      name: 'Rock',
      iconUrl: 'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=300&q=80',
      color: Color(0xFFE91E63),
    ),
    SpotifyCategory(
      id: 'indie',
      name: 'Indie',
      iconUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300&q=80',
      color: Color(0xFF673AB7),
    ),
    SpotifyCategory(
      id: 'chill',
      name: 'Chill',
      iconUrl: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=300&q=80',
      color: Color(0xFF2E7D32),
    ),
    SpotifyCategory(
      id: 'workout',
      name: 'Workout',
      iconUrl: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=300&q=80',
      color: Color(0xFF5D4037),
    ),
    SpotifyCategory(
      id: 'focus',
      name: 'Focus',
      iconUrl: 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=300&q=80',
      color: Color(0xFF455A64),
    ),
    SpotifyCategory(
      id: 'gaming',
      name: 'Gaming',
      iconUrl: 'https://images.unsplash.com/photo-1542751371-adc38448a05e?w=300&q=80',
      color: Color(0xFF7C4DFF),
    ),
    SpotifyCategory(
      id: 'kpop',
      name: 'K-Pop',
      iconUrl: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=300&q=80',
      color: Color(0xFF009688),
    ),
  ];

  // Spotify Connect Devices
  static const List<SpotifyDevice> devices = [
    SpotifyDevice(
      id: 'dev_local_pc',
      name: 'Windows Desktop (Flutify)',
      type: 'Computer',
      isActive: true,
      volumePercent: 85,
    ),
    SpotifyDevice(
      id: 'dev_galaxy_s24',
      name: 'Galaxy S24 Ultra',
      type: 'Smartphone',
      isActive: false,
      volumePercent: 65,
    ),
    SpotifyDevice(
      id: 'dev_living_room',
      name: 'Living Room Echo Studio',
      type: 'Speaker',
      isActive: false,
      volumePercent: 50,
    ),
  ];

  static const List<SpotifyAlbum> allAlbums = [
    albumAfterHours,
    album1989,
    albumHitMeHard,
    albumFutureNostalgia,
  ];

  static const List<SpotifyArtist> allArtists = [
    artistTheWeeknd,
    artistTaylorSwift,
    artistBillieEilish,
    artistDuaLipa,
  ];

  // 关系查询（Mock 模式下模拟 /albums/{id}/tracks、/artists/{id}/top-tracks 等）
  static List<SpotifyTrack> tracksForAlbum(String albumId) =>
      allTracks.where((t) => t.album?.id == albumId).toList();

  static List<SpotifyTrack> tracksForArtist(String artistId) {
    final tracks = allTracks.where((t) => t.artists.any((a) => a.id == artistId)).toList()
      ..sort((a, b) => b.popularity.compareTo(a.popularity));
    return tracks;
  }

  static List<SpotifyAlbum> albumsForArtist(String artistId) =>
      allAlbums.where((a) => a.artists.any((ar) => ar.id == artistId)).toList();

  static SpotifyArtist? findArtist(String id) {
    for (final a in allArtists) {
      if (a.id == id) return a;
    }
    return null;
  }

  // Synchronized Lyrics sample
  static const sampleLyrics = SpotifyLyrics(
    syncType: 'LINE_SYNCED',
    language: 'en',
    lines: [
      LyricLine(startTimeMs: 15000, words: "Yeah, yeah"),
      LyricLine(startTimeMs: 25000, words: "I've been tryna call"),
      LyricLine(startTimeMs: 28000, words: "I've been on my own for long enough"),
      LyricLine(startTimeMs: 33000, words: "Maybe you can show me how to love, maybe"),
      LyricLine(startTimeMs: 40000, words: "I'm going through withdrawals"),
      LyricLine(startTimeMs: 44000, words: "You don't even have to do too much"),
      LyricLine(startTimeMs: 48000, words: "You can turn me on with just a touch, baby"),
      LyricLine(startTimeMs: 55000, words: "I look around and Sin City's cold and empty"),
      LyricLine(startTimeMs: 61000, words: "No one's around to judge me"),
      LyricLine(startTimeMs: 64000, words: "I can't see clearly when you're gone"),
      LyricLine(startTimeMs: 70000, words: "I said, ooh, I'm blinded by the lights"),
      LyricLine(startTimeMs: 78000, words: "No, I can't sleep until I feel your touch"),
      LyricLine(startTimeMs: 86000, words: "I said, ooh, I'm drowning in the night"),
      LyricLine(startTimeMs: 94000, words: "Oh, when I'm like this, you're the one I trust"),
    ],
  );
}
