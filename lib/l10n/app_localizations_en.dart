// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Flutify';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonDone => 'Done';

  @override
  String get commonClose => 'Close';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonMoreOptions => 'More options';

  @override
  String get commonShowAll => 'Show all';

  @override
  String get commonSeeMore => 'See more';

  @override
  String get commonShowLess => 'Show less';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonShare => 'Share';

  @override
  String subtitleJoin(String first, String second) {
    return '$first • $second';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navLibrary => 'Your Library';

  @override
  String get typeArtist => 'Artist';

  @override
  String get typePlaylist => 'Playlist';

  @override
  String get typeAlbum => 'Album';

  @override
  String get typeSingle => 'Single';

  @override
  String get typeCompilation => 'Compilation';

  @override
  String get filterAll => 'All';

  @override
  String get filterMusic => 'Music';

  @override
  String get filterPodcasts => 'Podcasts';

  @override
  String get filterSongs => 'Songs';

  @override
  String get filterArtists => 'Artists';

  @override
  String get filterPlaylists => 'Playlists';

  @override
  String get filterAlbums => 'Albums';

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
    );
    return '$_temp0';
  }

  @override
  String followerCount(String count) {
    return '$count followers';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours hr $minutes min';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '$minutes min $seconds sec';
  }

  @override
  String countAndDuration(String count, String duration) {
    return '$count, $duration';
  }

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get likedSongs => 'Liked Songs';

  @override
  String get likedSongsDescription => 'All your favorite songs in one place.';

  @override
  String get likeAdd => 'Save to Liked Songs';

  @override
  String get likeRemove => 'Remove from Liked Songs';

  @override
  String get libraryAdd => 'Save to Your Library';

  @override
  String get libraryRemove => 'Remove from Your Library';

  @override
  String get homeLoadFailedTitle => 'Couldn\'t load recommendations';

  @override
  String get homeLoadFailedMessage => 'Check your connection or API settings.';

  @override
  String get homeMadeForYou => 'Made For You';

  @override
  String get homeMadeForYouSubtitle =>
      'Get fresh music and recommendations updated daily.';

  @override
  String get homePopularReleases => 'Popular Releases';

  @override
  String get homePopularReleasesSubtitle => 'The biggest albums out right now.';

  @override
  String get homePopularArtists => 'Popular Artists';

  @override
  String get homeNoPodcastsTitle => 'No podcasts yet';

  @override
  String get homeNoPodcastsMessage =>
      'Podcast shows and episodes will appear here.';

  @override
  String get searchHint => 'What do you want to listen to?';

  @override
  String get searchRecent => 'Recent searches';

  @override
  String get searchClearAll => 'Clear all';

  @override
  String get searchBrowseAll => 'Browse all';

  @override
  String get searchCategoriesFailedTitle => 'Couldn\'t load categories';

  @override
  String get searchCategoriesFailedMessage =>
      'Check your connection or API settings, then try again.';

  @override
  String searchNoResultsTitle(String query) {
    return 'No results found for \"$query\"';
  }

  @override
  String get searchNoResultsMessage =>
      'Please check the spelling or search for something else.';

  @override
  String get searchFilterEmptyTitle => 'Nothing in this category';

  @override
  String get searchFilterEmptyMessage =>
      'Try another filter to see more results.';

  @override
  String searchCategoryMix(String name) {
    return '$name Mix';
  }

  @override
  String searchCategoryMixDescription(String name) {
    return 'Best of $name curated with fresh vibes.';
  }

  @override
  String get librarySearchHint => 'Search in Your Library';

  @override
  String get libraryCloseSearch => 'Close search';

  @override
  String get libraryCreatePlaylist => 'Create playlist';

  @override
  String get libraryClearFilter => 'Clear filter';

  @override
  String get librarySortRecent => 'Recently added';

  @override
  String get librarySortAlphabetical => 'Alphabetical';

  @override
  String get libraryListView => 'List view';

  @override
  String get libraryGridView => 'Grid view';

  @override
  String get libraryEmptyTitle => 'Nothing here yet';

  @override
  String get libraryEmptyMessage =>
      'Saved playlists, artists and albums will show up here.';

  @override
  String libraryNewPlaylistName(int number) {
    return 'My Playlist #$number';
  }

  @override
  String get playlistDelete => 'Delete playlist';

  @override
  String get playlistLikedEmpty =>
      'Songs you like will appear here.\nSave songs by tapping the heart icon.';

  @override
  String get playlistOwnEmpty =>
      'Let\'s find something for your playlist.\nUse \"Add to playlist\" from any song\'s menu.';

  @override
  String get playlistEmpty => 'This playlist is empty.';

  @override
  String get albumNoTracks => 'No tracks available for this album.';

  @override
  String albumMoreBy(String name) {
    return 'More by $name';
  }

  @override
  String get artistPopular => 'Popular';

  @override
  String get artistNoPopular => 'No popular tracks yet.';

  @override
  String get artistDiscography => 'Discography';

  @override
  String get artistFollow => 'Follow';

  @override
  String get artistFollowing => 'Following';

  @override
  String get playingFromPlaylist => 'PLAYING FROM PLAYLIST';

  @override
  String get playingFromAlbum => 'PLAYING FROM ALBUM';

  @override
  String get playingFromArtist => 'PLAYING FROM ARTIST';

  @override
  String get playingFromSearch => 'PLAYING FROM SEARCH';

  @override
  String get playingFromLibrary => 'PLAYING FROM YOUR LIBRARY';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get openNowPlaying => 'Open Now Playing';

  @override
  String get playerNothingPlayingTitle => 'Nothing playing';

  @override
  String get playerNothingPlayingMessage =>
      'Pick a song, album or playlist to start listening.';

  @override
  String get playerIdleHint => 'Nothing playing — pick something to listen to';

  @override
  String get playerThisDevice => 'Listening on this device';

  @override
  String get playerShuffleOn => 'Enable shuffle';

  @override
  String get playerShuffleOff => 'Disable shuffle';

  @override
  String get playerRepeatOn => 'Enable repeat';

  @override
  String get playerRepeatOneOn => 'Enable repeat one';

  @override
  String get playerRepeatOff => 'Disable repeat';

  @override
  String get playerNext => 'Next';

  @override
  String get playerPrevious => 'Previous';

  @override
  String get playerMute => 'Mute';

  @override
  String get playerUnmute => 'Unmute';

  @override
  String get queueTitle => 'Queue';

  @override
  String get queueNextInQueue => 'Next in queue';

  @override
  String get queueClear => 'Clear queue';

  @override
  String get queueNextUp => 'Next up';

  @override
  String queueNextFrom(String name) {
    return 'Next from: $name';
  }

  @override
  String get queueEmpty => 'Nothing queued up next';

  @override
  String get lyricsTitle => 'Lyrics';

  @override
  String get lyricsNotPlaying => 'Not playing';

  @override
  String get lyricsNothingPlayingMessage =>
      'Play a song to see its lyrics here.';

  @override
  String get lyricsUnavailableTitle => 'Lyrics aren\'t available';

  @override
  String get lyricsUnavailableMessage =>
      'We don\'t have lyrics for this song yet.\nEnjoy the music!';

  @override
  String get lyricsUnsynced => 'These lyrics aren\'t synced to the song yet.';

  @override
  String get deviceConnectTitle => 'Connect to a device';

  @override
  String get deviceConnectDescription =>
      'Spotify Connect allows you to seamlessly stream to your PC, phone, or smart speakers.';

  @override
  String get deviceCurrent => 'Current Listening Device';

  @override
  String get deviceSpotifyConnect => 'Spotify Connect';

  @override
  String get trackAddToPlaylist => 'Add to playlist';

  @override
  String get trackAddToQueue => 'Add to queue';

  @override
  String get trackGoToAlbum => 'Go to album';

  @override
  String trackGoToArtist(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Go to artists',
      one: 'Go to artist',
    );
    return '$_temp0';
  }

  @override
  String get trackNewPlaylist => 'New playlist';

  @override
  String get toastLikeAdded => 'Added to Liked Songs';

  @override
  String get toastLikeRemoved => 'Removed from Liked Songs';

  @override
  String get toastAddedToQueue => 'Added to queue';

  @override
  String get toastLinkCopied => 'Link copied to clipboard';

  @override
  String toastAddedTo(String name) {
    return 'Added to $name';
  }

  @override
  String toastAlreadyIn(String name) {
    return 'Already in $name';
  }

  @override
  String get createPlaylistTitle => 'Give your playlist a name';

  @override
  String get createPlaylistHint => 'Playlist name';

  @override
  String get createPlaylistDefaultName => 'My Playlist';

  @override
  String get settingsSave => 'Save Settings';

  @override
  String get settingsSaved => 'Spotify API configuration saved!';

  @override
  String get settingsBannerTitle => 'Spotify Reverse Engineering Ready';

  @override
  String get settingsBannerMessage =>
      'Configure your reverse-engineered SpClient tokens, OAuth keys, or local MITM proxy URL.';

  @override
  String get settingsCredentialsSection => 'API Credentials & Proxy';

  @override
  String get settingsBaseUrlLabel => 'API Base URL';

  @override
  String get settingsBaseUrlHint =>
      'https://api.spotify.com/v1 or http://localhost:8080/v1';

  @override
  String get settingsTokenLabel => 'Spotify Access Token (Bearer)';

  @override
  String get settingsTokenHint => 'BQ... (OAuth Access Token)';

  @override
  String get settingsTokenManaged =>
      'Signed in: the token is fetched and renewed by Login5';

  @override
  String get settingsPasteToken => 'Paste token';

  @override
  String get settingsSpClientLabel =>
      'SpClient Cookie (sp_dc / internal token)';

  @override
  String get settingsSpClientHint =>
      'Extracted from Spotify Desktop / Android app cookies';
}
