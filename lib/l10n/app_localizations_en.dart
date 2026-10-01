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
  String get shellBack => 'Go back';

  @override
  String get shellForward => 'Go forward';

  @override
  String get shellHome => 'Home';

  @override
  String get shellSearchShortcut => 'Ctrl K';

  @override
  String get shellAccountMenu => 'Account';

  @override
  String get shellCollapseLibrary => 'Collapse Your Library';

  @override
  String get shellExpandLibrary => 'Expand Your Library';

  @override
  String get shellPlaybackStatus => 'Playback status';

  @override
  String get shellHidePanel => 'Hide';

  @override
  String get shellAboutArtist => 'About the artist';

  @override
  String shellMonthlyFollowers(String count) {
    return '$count followers';
  }

  @override
  String get shellSignInTitle => 'Sign in to see your library';

  @override
  String get shellSignInMessage =>
      'Saved playlists, albums and artists will show up here.';

  @override
  String get shellSignIn => 'Sign in';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close';

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
  String get typeTrack => 'Song';

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
  String get homeLoadFailedMessage => 'Check your connection and try again.';

  @override
  String get authSessionExpiredTitle => 'Your session has expired';

  @override
  String get authSessionExpiredMessage =>
      'Spotify ended this sign-in (for example, you signed out everywhere or changed your password). Please sign in again.';

  @override
  String get authSignInAgain => 'Sign in again';

  @override
  String get homeEmptyTitle => 'Nothing here yet';

  @override
  String get homeEmptyMessage => 'Try another filter, or check back later.';

  @override
  String get homeClearFilter => 'Clear filter';

  @override
  String get homePodcastUnsupported => 'Podcasts aren\'t supported yet';

  @override
  String get homeTypePodcast => 'Podcast';

  @override
  String get homeTypeEpisode => 'Episode';

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
      'Check your connection and try again.';

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
  String get playerLyricsFullscreen => 'Full-screen lyrics';

  @override
  String get playerSwipeHint => 'Swipe the artwork to change songs';

  @override
  String get playbackErrorSignIn => 'Sign in to play music';

  @override
  String playbackErrorUnavailable(String track) {
    return '\"$track\" isn\'t available right now';
  }

  @override
  String playbackErrorSkipped(String track) {
    return '\"$track\" isn\'t available right now, skipped';
  }

  @override
  String playbackErrorNetwork(String track) {
    return 'Couldn\'t load \"$track\". Check your connection.';
  }

  @override
  String playbackErrorAutoPaused(int count) {
    return '$count songs in a row couldn\'t play, so playback paused';
  }

  @override
  String get detailSignInRequired => 'Sign in to see what\'s here';

  @override
  String get detailLoadFailed =>
      'Couldn\'t load this. Check your connection and try again.';

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
  String get lyricsImmersive => 'Immersive lyrics';

  @override
  String get lyricsExpand => 'Expand lyrics';

  @override
  String get lyricsCollapse => 'Collapse lyrics';

  @override
  String get lyricsExitImmersive => 'Exit lyrics (Esc)';

  @override
  String get lyricsFillScreen => 'Fill the screen (F11)';

  @override
  String get lyricsFillWindow => 'Fit to window (F11)';

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
  String get connectThisDevice => 'This device';

  @override
  String get connectTakeOver => 'Continue playing here';

  @override
  String connectPlayingOn(String device) {
    return 'Playing on $device';
  }

  @override
  String get connectOtherDevices => 'Select another device';

  @override
  String get connectNoDevices => 'No other devices found';

  @override
  String get connectNoDevicesHint =>
      'Open Spotify on a phone, computer or speaker signed in to the same account';

  @override
  String get connectUnavailable =>
      'Sign in with the desktop method to control Spotify on your other devices';

  @override
  String get connectConnecting => 'Connecting to Spotify Connect…';

  @override
  String get connectOffline => 'Connection lost, retrying…';

  @override
  String get connectSameNetwork => 'Same network';

  @override
  String get connectCommandFailed =>
      'That didn\'t work: free accounts may not support this remote action';

  @override
  String connectVolumeUnsupported(String device) {
    return '$device doesn\'t support remote volume control';
  }

  @override
  String get connectVolume => 'Device volume';

  @override
  String get trackAddToPlaylist => 'Add to playlist';

  @override
  String get trackAddToQueue => 'Add to queue';

  @override
  String get trackGoToAlbum => 'Go to album';

  @override
  String get trackGoToRadio => 'Go to song radio';

  @override
  String get trackViewCredits => 'View credits';

  @override
  String get creditsTitle => 'Credits';

  @override
  String get creditsSources => 'Sources';

  @override
  String get creditsEmpty => 'No credits available for this song';

  @override
  String get radioUnavailable => 'No song radio available for this song';

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
  String get shareCopyLink => 'Copy link';

  @override
  String get shareCopyUri => 'Copy URI';

  @override
  String get shareOpenWeb => 'Open web';

  @override
  String get shareCopied => 'Copied';

  @override
  String get shareEmbedTitle => 'Embed';

  @override
  String get shareEmbedSubtitle =>
      'Paste into your page\'s HTML to show a Spotify player';

  @override
  String get shareEmbedStandard => 'Standard';

  @override
  String get shareEmbedCompact => 'Compact';

  @override
  String get shareEmbedDark => 'Dark';

  @override
  String get shareEmbedCopy => 'Copy code';

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
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsThemeMode => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsPureBlack => 'Pure black';

  @override
  String get settingsPureBlackSubtitle =>
      'Use true black in dark mode to save power on OLED screens';

  @override
  String get settingsAccentSection => 'Accent colour';

  @override
  String get settingsAccentCustom => 'Custom colour';

  @override
  String get settingsDynamicAccent => 'Match album artwork';

  @override
  String get settingsDynamicAccentSubtitle =>
      'The accent follows the artwork of what\'s playing';

  @override
  String get settingsGlassSection => 'Liquid glass';

  @override
  String get settingsGlassPreview => 'Glass preview';

  @override
  String get settingsGlassBlur => 'Blur';

  @override
  String get settingsGlassOpacity => 'Opacity';

  @override
  String get settingsTextShapeSection => 'Text & shape';

  @override
  String get settingsFontScale => 'Text size';

  @override
  String get settingsFontPreview => 'The brightest star in the night sky';

  @override
  String get settingsCornerStyle => 'Corners';

  @override
  String get settingsCornerRounded => 'Rounded';

  @override
  String get settingsCornerStandard => 'Standard';

  @override
  String get settingsCornerSquare => 'Square';

  @override
  String get settingsPlaybackSection => 'Playback';

  @override
  String get settingsPauseAfterFailures => 'Pause when songs keep failing';

  @override
  String settingsPauseAfterFailuresSubtitle(int count) {
    return 'Stop auto-skipping after $count unplayable songs in a row';
  }

  @override
  String get settingsMotionSection => 'Motion';

  @override
  String get settingsReduceMotion => 'Reduce motion';

  @override
  String get settingsReduceMotionSubtitle =>
      'Turns off flowing backgrounds, transitions and hover animations';

  @override
  String get settingsResetAppearance => 'Reset appearance';

  @override
  String get settingsCustomColorTitle => 'Custom accent colour';

  @override
  String get settingsHue => 'Hue';

  @override
  String get settingsSaturation => 'Saturation';

  @override
  String get settingsBrightness => 'Brightness';

  @override
  String get settingsLanguageSection => 'Language';

  @override
  String get settingsLanguage => 'App language';

  @override
  String get settingsLanguageSubtitle =>
      'Also changes text provided by Spotify, such as home feed titles';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageZh => '中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsStorageSection => 'Storage';

  @override
  String get settingsAudioCache => 'Audio cache';

  @override
  String settingsAudioCacheUsage(String used, String limit) {
    return '$used of $limit used';
  }

  @override
  String get settingsAudioCacheCalculating => 'Calculating…';

  @override
  String get settingsAudioCacheLimit => 'Cache limit';

  @override
  String get settingsAudioCacheLimitSubtitle =>
      'Songs you haven\'t played for the longest are removed first';

  @override
  String get settingsClearAudioCache => 'Clear audio cache';

  @override
  String get settingsClearAudioCacheTitle => 'Clear audio cache?';

  @override
  String get settingsClearAudioCacheMessage =>
      'Downloaded songs will be deleted and downloaded again when you play them. The song that\'s playing is kept.';

  @override
  String settingsAudioCacheCleared(String size) {
    return 'Freed $size';
  }

  @override
  String get settingsLyricsSection => 'Lyrics';

  @override
  String get settingsLyricsSize => 'Lyrics size';

  @override
  String get settingsLyricsAlign => 'Alignment';

  @override
  String get settingsLyricsAlignLeft => 'Left';

  @override
  String get settingsLyricsAlignCenter => 'Centre';

  @override
  String get settingsLyricsBlur => 'Blur other lines';

  @override
  String get settingsLyricsImmersiveScreen =>
      'Full-screen lyrics fill the screen';

  @override
  String get settingsLyricsImmersiveScreenSubtitle =>
      'When off, they fill only the window. Press F11 in full-screen lyrics to switch';

  @override
  String get settingsOff => 'Off';

  @override
  String get settingsNormalize => 'Normalize volume';

  @override
  String get settingsNormalizeSubtitle =>
      'Uses Spotify\'s loudness data to turn loud songs down to a consistent level';

  @override
  String get settingsFade => 'Fade between songs';

  @override
  String get settingsFadeSubtitle =>
      'Fades out at the end of a song and fades the next one in';

  @override
  String settingsSeconds(int count) {
    return '$count s';
  }

  @override
  String get settingsStartupSection => 'Startup';

  @override
  String get settingsStartPage => 'Open at launch';

  @override
  String get settingsStartPageHome => 'Home';

  @override
  String get settingsStartPageLibrary => 'Library';

  @override
  String get settingsStartPageLast => 'Last page';

  @override
  String get settingsRememberWindow => 'Remember window size and position';

  @override
  String get settingsRememberWindowSubtitle =>
      'Restored at next launch; centred again if the screen it was on is gone';

  @override
  String get settingsConnectSection => 'Spotify Connect';

  @override
  String get settingsConnectEnabled => 'Enable Spotify Connect';

  @override
  String get settingsConnectEnabledSubtitle =>
      'Show and control playback on your other devices';

  @override
  String get settingsRemoteLyricsLead => 'Remote lyrics lead';

  @override
  String get settingsRemoteLyricsLeadSubtitle =>
      'When another device is playing: raise it if lyrics lag behind the singing, lower it if they run ahead';

  @override
  String get settingsNetworkSection => 'Network';

  @override
  String get settingsProxy => 'Proxy';

  @override
  String get settingsProxySystem => 'System';

  @override
  String get settingsProxyNone => 'None';

  @override
  String get settingsProxyManual => 'Manual';

  @override
  String settingsProxySystemDetected(String endpoint) {
    return 'System proxy: $endpoint';
  }

  @override
  String get settingsProxySystemEmpty =>
      'No system proxy set — connecting directly';

  @override
  String get settingsProxyNoneSubtitle =>
      'All requests connect directly, without a proxy';

  @override
  String get settingsProxyManualSubtitle =>
      'Enter the address and port of an HTTP proxy';

  @override
  String get settingsProxyServer => 'Proxy server';

  @override
  String get settingsProxyHostHint => '127.0.0.1';

  @override
  String get settingsProxyPortHint => 'Port';

  @override
  String get settingsProxyInvalid =>
      'Enter a valid address and a port between 1 and 65535';

  @override
  String get settingsProxyTest => 'Test connection';

  @override
  String get settingsProxyTesting => 'Connecting to Spotify…';

  @override
  String settingsProxyTestOk(int ms) {
    return 'Connected in $ms ms';
  }

  @override
  String settingsProxyTestFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get settingsProxyFootnote =>
      'Only HTTP proxies are supported (the mixed port of Clash, v2rayN, etc. works). The sign-in page always follows the system proxy settings.';

  @override
  String get settingsPrivacySection => 'Privacy';

  @override
  String get settingsClearSearchHistory => 'Clear search history';

  @override
  String settingsSearchHistoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count searches',
      one: '1 search',
    );
    return '$_temp0';
  }

  @override
  String get settingsSearchHistoryEmpty => 'No search history';

  @override
  String get settingsClearLyricsCache => 'Clear lyrics cache';

  @override
  String get settingsClearLyricsCacheSubtitle =>
      'Lyrics will be fetched from Spotify again';

  @override
  String get settingsCleared => 'Cleared';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsShortcuts => 'Keyboard shortcuts';

  @override
  String get settingsLicenses => 'Open-source licences';

  @override
  String get shortcutPlayPause => 'Play / pause';

  @override
  String get shortcutNext => 'Next song';

  @override
  String get shortcutPrevious => 'Previous song';

  @override
  String get shortcutVolumeUp => 'Volume up';

  @override
  String get shortcutVolumeDown => 'Volume down';

  @override
  String get shortcutShuffle => 'Shuffle';

  @override
  String get shortcutRepeat => 'Change repeat mode';

  @override
  String get shortcutSearch => 'Search';

  @override
  String get shortcutBack => 'Back';

  @override
  String get shortcutForward => 'Forward';

  @override
  String get shortcutImmersive => 'Full-screen lyrics';

  @override
  String get shortcutImmersiveMode =>
      'In full-screen lyrics: fill screen / window';

  @override
  String get shortcutExitImmersive => 'Exit full-screen lyrics';

  @override
  String get accountTitle => 'Spotify account';

  @override
  String get accountSignedOutMessage => 'Sign in to sync your library';

  @override
  String get accountSignIn => 'Sign in';

  @override
  String get accountSignOut => 'Sign out';

  @override
  String get accountSignOutTitle => 'Sign out?';

  @override
  String get accountSignOutMessage =>
      'Your saved sign-in and library cache will be removed from this device. You\'ll need to sign in again to play music and view your library.';

  @override
  String get accountSignOutConfirm => 'Sign out';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String sleepTimerMinutes(int count) {
    return '$count minutes';
  }

  @override
  String get sleepTimerHour => '1 hour';

  @override
  String get sleepTimerEndOfTrack => 'End of track';

  @override
  String get sleepTimerOff => 'Turn off timer';

  @override
  String sleepTimerRemaining(String time) {
    return 'Sleep timer: $time left';
  }

  @override
  String get sleepTimerEndOfTrackActive =>
      'Sleep timer: pausing at end of track';

  @override
  String toastSleepTimerSet(String label) {
    return 'Sleep timer set: $label';
  }

  @override
  String get toastSleepTimerOff => 'Sleep timer turned off';

  @override
  String shortcutOnHoveredTrack(String action) {
    return 'Hovered track: $action';
  }

  @override
  String get trackColumnTitle => 'Title';

  @override
  String get trackColumnArtist => 'Artist';

  @override
  String get trackColumnAlbum => 'Album';

  @override
  String get trackColumnAddedAt => 'Date added';

  @override
  String get trackColumnDuration => 'Duration';

  @override
  String get trackSortBy => 'Sort by';

  @override
  String get trackSortCustom => 'Custom order';

  @override
  String get trackViewAs => 'View as';

  @override
  String get trackViewList => 'List';

  @override
  String get trackViewCompact => 'Compact';

  @override
  String get trackSearchHint => 'Search in playlist';

  @override
  String get trackSearchClose => 'Close search';

  @override
  String trackSearchNoResults(String query) {
    return 'Couldn\'t find \"$query\"';
  }

  @override
  String get addedToday => 'Today';

  @override
  String addedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String addedWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks ago',
      one: '1 week ago',
    );
    return '$_temp0';
  }
}
