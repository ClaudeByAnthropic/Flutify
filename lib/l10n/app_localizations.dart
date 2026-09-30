import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Flutify'**
  String get appTitle;

  /// No description provided for @shellBack.
  ///
  /// In zh, this message translates to:
  /// **'后退'**
  String get shellBack;

  /// No description provided for @shellForward.
  ///
  /// In zh, this message translates to:
  /// **'前进'**
  String get shellForward;

  /// No description provided for @shellHome.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get shellHome;

  /// No description provided for @shellSearchShortcut.
  ///
  /// In zh, this message translates to:
  /// **'Ctrl K'**
  String get shellSearchShortcut;

  /// No description provided for @shellAccountMenu.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get shellAccountMenu;

  /// No description provided for @shellCollapseLibrary.
  ///
  /// In zh, this message translates to:
  /// **'收起音乐库'**
  String get shellCollapseLibrary;

  /// No description provided for @shellExpandLibrary.
  ///
  /// In zh, this message translates to:
  /// **'展开音乐库'**
  String get shellExpandLibrary;

  /// No description provided for @shellNowPlayingView.
  ///
  /// In zh, this message translates to:
  /// **'正在播放视图'**
  String get shellNowPlayingView;

  /// No description provided for @shellHidePanel.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get shellHidePanel;

  /// No description provided for @shellAboutArtist.
  ///
  /// In zh, this message translates to:
  /// **'关于艺人'**
  String get shellAboutArtist;

  /// No description provided for @shellMonthlyFollowers.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位粉丝'**
  String shellMonthlyFollowers(String count);

  /// No description provided for @shellSignInTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录后查看你的音乐库'**
  String get shellSignInTitle;

  /// No description provided for @shellSignInMessage.
  ///
  /// In zh, this message translates to:
  /// **'收藏的歌单、专辑和艺人会显示在这里。'**
  String get shellSignInMessage;

  /// No description provided for @shellSignIn.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get shellSignIn;

  /// No description provided for @windowMinimize.
  ///
  /// In zh, this message translates to:
  /// **'最小化'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In zh, this message translates to:
  /// **'最大化'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In zh, this message translates to:
  /// **'向下还原'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get windowClose;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get commonCreate;

  /// No description provided for @commonDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get commonDone;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @commonClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get commonClear;

  /// No description provided for @commonRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get commonRemove;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonMoreOptions.
  ///
  /// In zh, this message translates to:
  /// **'更多选项'**
  String get commonMoreOptions;

  /// No description provided for @commonShowAll.
  ///
  /// In zh, this message translates to:
  /// **'显示全部'**
  String get commonShowAll;

  /// No description provided for @commonSeeMore.
  ///
  /// In zh, this message translates to:
  /// **'查看更多'**
  String get commonSeeMore;

  /// No description provided for @commonShowLess.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get commonShowLess;

  /// No description provided for @commonSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get commonSettings;

  /// No description provided for @commonShare.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get commonShare;

  /// 副标题中两段信息的连接，如「歌单 · Spotify」
  ///
  /// In zh, this message translates to:
  /// **'{first} · {second}'**
  String subtitleJoin(String first, String second);

  /// No description provided for @navHome.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get navHome;

  /// No description provided for @navSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get navSearch;

  /// No description provided for @navLibrary.
  ///
  /// In zh, this message translates to:
  /// **'音乐库'**
  String get navLibrary;

  /// No description provided for @typeArtist.
  ///
  /// In zh, this message translates to:
  /// **'艺人'**
  String get typeArtist;

  /// No description provided for @typePlaylist.
  ///
  /// In zh, this message translates to:
  /// **'歌单'**
  String get typePlaylist;

  /// No description provided for @typeAlbum.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get typeAlbum;

  /// No description provided for @typeSingle.
  ///
  /// In zh, this message translates to:
  /// **'单曲'**
  String get typeSingle;

  /// No description provided for @typeCompilation.
  ///
  /// In zh, this message translates to:
  /// **'合辑'**
  String get typeCompilation;

  /// No description provided for @filterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get filterAll;

  /// No description provided for @filterMusic.
  ///
  /// In zh, this message translates to:
  /// **'音乐'**
  String get filterMusic;

  /// No description provided for @filterPodcasts.
  ///
  /// In zh, this message translates to:
  /// **'播客'**
  String get filterPodcasts;

  /// No description provided for @filterSongs.
  ///
  /// In zh, this message translates to:
  /// **'歌曲'**
  String get filterSongs;

  /// No description provided for @filterArtists.
  ///
  /// In zh, this message translates to:
  /// **'艺人'**
  String get filterArtists;

  /// No description provided for @filterPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'歌单'**
  String get filterPlaylists;

  /// No description provided for @filterAlbums.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get filterAlbums;

  /// No description provided for @songCount.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{{count} 首歌曲}}'**
  String songCount(int count);

  /// 粉丝数，count 为已格式化的紧凑数字（如 1.2 万）
  ///
  /// In zh, this message translates to:
  /// **'{count} 位粉丝'**
  String followerCount(String count);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时 {minutes} 分钟'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @durationMinutesSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分 {seconds} 秒'**
  String durationMinutesSeconds(int minutes, int seconds);

  /// 歌曲数与总时长的连接，如「12 首歌曲，45 分 12 秒」
  ///
  /// In zh, this message translates to:
  /// **'{count}，{duration}'**
  String countAndDuration(String count, String duration);

  /// No description provided for @greetingMorning.
  ///
  /// In zh, this message translates to:
  /// **'早上好'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In zh, this message translates to:
  /// **'下午好'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In zh, this message translates to:
  /// **'晚上好'**
  String get greetingEvening;

  /// No description provided for @likedSongs.
  ///
  /// In zh, this message translates to:
  /// **'已点赞的歌曲'**
  String get likedSongs;

  /// No description provided for @likedSongsDescription.
  ///
  /// In zh, this message translates to:
  /// **'你喜欢的所有歌曲都在这里。'**
  String get likedSongsDescription;

  /// No description provided for @likeAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加到已点赞的歌曲'**
  String get likeAdd;

  /// No description provided for @likeRemove.
  ///
  /// In zh, this message translates to:
  /// **'从已点赞的歌曲中移除'**
  String get likeRemove;

  /// No description provided for @libraryAdd.
  ///
  /// In zh, this message translates to:
  /// **'保存到音乐库'**
  String get libraryAdd;

  /// No description provided for @libraryRemove.
  ///
  /// In zh, this message translates to:
  /// **'从音乐库中移除'**
  String get libraryRemove;

  /// No description provided for @homeLoadFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'无法加载推荐内容'**
  String get homeLoadFailedTitle;

  /// No description provided for @homeLoadFailedMessage.
  ///
  /// In zh, this message translates to:
  /// **'请检查网络连接或 API 设置。'**
  String get homeLoadFailedMessage;

  /// No description provided for @homeMadeForYou.
  ///
  /// In zh, this message translates to:
  /// **'为你打造'**
  String get homeMadeForYou;

  /// No description provided for @homeMadeForYouSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'每日更新的新鲜音乐与推荐。'**
  String get homeMadeForYouSubtitle;

  /// No description provided for @homePopularReleases.
  ///
  /// In zh, this message translates to:
  /// **'热门新发行'**
  String get homePopularReleases;

  /// No description provided for @homePopularReleasesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'当下最受欢迎的专辑。'**
  String get homePopularReleasesSubtitle;

  /// No description provided for @homePopularArtists.
  ///
  /// In zh, this message translates to:
  /// **'热门艺人'**
  String get homePopularArtists;

  /// No description provided for @homeNoPodcastsTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂无播客'**
  String get homeNoPodcastsTitle;

  /// No description provided for @homeNoPodcastsMessage.
  ///
  /// In zh, this message translates to:
  /// **'播客节目和单集会显示在这里。'**
  String get homeNoPodcastsMessage;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'你想听什么？'**
  String get searchHint;

  /// No description provided for @searchRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近搜索'**
  String get searchRecent;

  /// No description provided for @searchClearAll.
  ///
  /// In zh, this message translates to:
  /// **'全部清除'**
  String get searchClearAll;

  /// No description provided for @searchBrowseAll.
  ///
  /// In zh, this message translates to:
  /// **'浏览全部'**
  String get searchBrowseAll;

  /// No description provided for @searchCategoriesFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'无法加载分类'**
  String get searchCategoriesFailedTitle;

  /// No description provided for @searchCategoriesFailedMessage.
  ///
  /// In zh, this message translates to:
  /// **'请检查网络连接或 API 设置后重试。'**
  String get searchCategoriesFailedMessage;

  /// No description provided for @searchNoResultsTitle.
  ///
  /// In zh, this message translates to:
  /// **'未找到与“{query}”相关的结果'**
  String searchNoResultsTitle(String query);

  /// No description provided for @searchNoResultsMessage.
  ///
  /// In zh, this message translates to:
  /// **'请检查拼写，或换个关键词试试。'**
  String get searchNoResultsMessage;

  /// No description provided for @searchFilterEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'该分类下暂无结果'**
  String get searchFilterEmptyTitle;

  /// No description provided for @searchFilterEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'换个筛选条件，查看更多结果。'**
  String get searchFilterEmptyMessage;

  /// No description provided for @searchCategoryMix.
  ///
  /// In zh, this message translates to:
  /// **'{name} 精选'**
  String searchCategoryMix(String name);

  /// No description provided for @searchCategoryMixDescription.
  ///
  /// In zh, this message translates to:
  /// **'精选 {name} 好歌，新鲜好听。'**
  String searchCategoryMixDescription(String name);

  /// No description provided for @librarySearchHint.
  ///
  /// In zh, this message translates to:
  /// **'在音乐库中搜索'**
  String get librarySearchHint;

  /// No description provided for @libraryCloseSearch.
  ///
  /// In zh, this message translates to:
  /// **'关闭搜索'**
  String get libraryCloseSearch;

  /// No description provided for @libraryCreatePlaylist.
  ///
  /// In zh, this message translates to:
  /// **'创建歌单'**
  String get libraryCreatePlaylist;

  /// No description provided for @libraryClearFilter.
  ///
  /// In zh, this message translates to:
  /// **'清除筛选'**
  String get libraryClearFilter;

  /// No description provided for @librarySortRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近添加'**
  String get librarySortRecent;

  /// No description provided for @librarySortAlphabetical.
  ///
  /// In zh, this message translates to:
  /// **'按字母顺序'**
  String get librarySortAlphabetical;

  /// No description provided for @libraryListView.
  ///
  /// In zh, this message translates to:
  /// **'列表视图'**
  String get libraryListView;

  /// No description provided for @libraryGridView.
  ///
  /// In zh, this message translates to:
  /// **'网格视图'**
  String get libraryGridView;

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'这里还没有内容'**
  String get libraryEmptyTitle;

  /// No description provided for @libraryEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'收藏的歌单、艺人和专辑会显示在这里。'**
  String get libraryEmptyMessage;

  /// No description provided for @libraryNewPlaylistName.
  ///
  /// In zh, this message translates to:
  /// **'我的歌单 #{number}'**
  String libraryNewPlaylistName(int number);

  /// No description provided for @playlistDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除歌单'**
  String get playlistDelete;

  /// No description provided for @playlistLikedEmpty.
  ///
  /// In zh, this message translates to:
  /// **'你点赞的歌曲会显示在这里。\n点按爱心图标即可收藏歌曲。'**
  String get playlistLikedEmpty;

  /// No description provided for @playlistOwnEmpty.
  ///
  /// In zh, this message translates to:
  /// **'来为你的歌单找些歌曲吧。\n在任意歌曲的菜单中选择“添加到歌单”。'**
  String get playlistOwnEmpty;

  /// No description provided for @playlistEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个歌单还没有歌曲。'**
  String get playlistEmpty;

  /// No description provided for @albumNoTracks.
  ///
  /// In zh, this message translates to:
  /// **'这张专辑暂无可播放的曲目。'**
  String get albumNoTracks;

  /// No description provided for @albumMoreBy.
  ///
  /// In zh, this message translates to:
  /// **'{name} 的更多作品'**
  String albumMoreBy(String name);

  /// No description provided for @artistPopular.
  ///
  /// In zh, this message translates to:
  /// **'热门歌曲'**
  String get artistPopular;

  /// No description provided for @artistNoPopular.
  ///
  /// In zh, this message translates to:
  /// **'暂无热门歌曲。'**
  String get artistNoPopular;

  /// No description provided for @artistDiscography.
  ///
  /// In zh, this message translates to:
  /// **'作品'**
  String get artistDiscography;

  /// No description provided for @artistFollow.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get artistFollow;

  /// No description provided for @artistFollowing.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get artistFollowing;

  /// No description provided for @playingFromPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'正在播放歌单'**
  String get playingFromPlaylist;

  /// No description provided for @playingFromAlbum.
  ///
  /// In zh, this message translates to:
  /// **'正在播放专辑'**
  String get playingFromAlbum;

  /// No description provided for @playingFromArtist.
  ///
  /// In zh, this message translates to:
  /// **'正在播放艺人'**
  String get playingFromArtist;

  /// No description provided for @playingFromSearch.
  ///
  /// In zh, this message translates to:
  /// **'正在播放搜索结果'**
  String get playingFromSearch;

  /// No description provided for @playingFromLibrary.
  ///
  /// In zh, this message translates to:
  /// **'正在播放音乐库'**
  String get playingFromLibrary;

  /// No description provided for @nowPlaying.
  ///
  /// In zh, this message translates to:
  /// **'正在播放'**
  String get nowPlaying;

  /// No description provided for @openNowPlaying.
  ///
  /// In zh, this message translates to:
  /// **'打开正在播放'**
  String get openNowPlaying;

  /// No description provided for @playerNothingPlayingTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前没有播放内容'**
  String get playerNothingPlayingTitle;

  /// No description provided for @playerNothingPlayingMessage.
  ///
  /// In zh, this message translates to:
  /// **'选择一首歌曲、专辑或歌单，开始收听吧。'**
  String get playerNothingPlayingMessage;

  /// No description provided for @playerIdleHint.
  ///
  /// In zh, this message translates to:
  /// **'暂无播放 — 挑点音乐来听吧'**
  String get playerIdleHint;

  /// No description provided for @playerThisDevice.
  ///
  /// In zh, this message translates to:
  /// **'正在本设备上收听'**
  String get playerThisDevice;

  /// No description provided for @playerShuffleOn.
  ///
  /// In zh, this message translates to:
  /// **'开启随机播放'**
  String get playerShuffleOn;

  /// No description provided for @playerShuffleOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭随机播放'**
  String get playerShuffleOff;

  /// No description provided for @playerRepeatOn.
  ///
  /// In zh, this message translates to:
  /// **'开启列表循环'**
  String get playerRepeatOn;

  /// No description provided for @playerRepeatOneOn.
  ///
  /// In zh, this message translates to:
  /// **'开启单曲循环'**
  String get playerRepeatOneOn;

  /// No description provided for @playerRepeatOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭循环'**
  String get playerRepeatOff;

  /// No description provided for @playerNext.
  ///
  /// In zh, this message translates to:
  /// **'下一首'**
  String get playerNext;

  /// No description provided for @playerPrevious.
  ///
  /// In zh, this message translates to:
  /// **'上一首'**
  String get playerPrevious;

  /// No description provided for @playerMute.
  ///
  /// In zh, this message translates to:
  /// **'静音'**
  String get playerMute;

  /// No description provided for @playerUnmute.
  ///
  /// In zh, this message translates to:
  /// **'取消静音'**
  String get playerUnmute;

  /// No description provided for @playerLyricsFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'全屏歌词'**
  String get playerLyricsFullscreen;

  /// No description provided for @playerSwipeHint.
  ///
  /// In zh, this message translates to:
  /// **'左右滑动封面切换歌曲'**
  String get playerSwipeHint;

  /// No description provided for @playbackErrorSignIn.
  ///
  /// In zh, this message translates to:
  /// **'登录后才能播放'**
  String get playbackErrorSignIn;

  /// No description provided for @playbackErrorUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'「{track}」暂时无法播放'**
  String playbackErrorUnavailable(String track);

  /// No description provided for @playbackErrorSkipped.
  ///
  /// In zh, this message translates to:
  /// **'「{track}」暂时无法播放，已跳过'**
  String playbackErrorSkipped(String track);

  /// No description provided for @playbackErrorNetwork.
  ///
  /// In zh, this message translates to:
  /// **'「{track}」加载失败，请检查网络'**
  String playbackErrorNetwork(String track);

  /// No description provided for @detailSignInRequired.
  ///
  /// In zh, this message translates to:
  /// **'登录后即可查看这里的内容'**
  String get detailSignInRequired;

  /// No description provided for @detailLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法加载，请检查网络后重试'**
  String get detailLoadFailed;

  /// No description provided for @queueTitle.
  ///
  /// In zh, this message translates to:
  /// **'播放队列'**
  String get queueTitle;

  /// No description provided for @queueNextInQueue.
  ///
  /// In zh, this message translates to:
  /// **'队列中的下一首'**
  String get queueNextInQueue;

  /// No description provided for @queueClear.
  ///
  /// In zh, this message translates to:
  /// **'清空队列'**
  String get queueClear;

  /// No description provided for @queueNextUp.
  ///
  /// In zh, this message translates to:
  /// **'接下来播放'**
  String get queueNextUp;

  /// No description provided for @queueNextFrom.
  ///
  /// In zh, this message translates to:
  /// **'接下来播放：{name}'**
  String queueNextFrom(String name);

  /// No description provided for @queueEmpty.
  ///
  /// In zh, this message translates to:
  /// **'队列中暂无待播歌曲'**
  String get queueEmpty;

  /// No description provided for @lyricsTitle.
  ///
  /// In zh, this message translates to:
  /// **'歌词'**
  String get lyricsTitle;

  /// No description provided for @lyricsNotPlaying.
  ///
  /// In zh, this message translates to:
  /// **'未在播放'**
  String get lyricsNotPlaying;

  /// No description provided for @lyricsNothingPlayingMessage.
  ///
  /// In zh, this message translates to:
  /// **'播放一首歌曲，即可在这里查看歌词。'**
  String get lyricsNothingPlayingMessage;

  /// No description provided for @lyricsUnavailableTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂无歌词'**
  String get lyricsUnavailableTitle;

  /// No description provided for @lyricsUnavailableMessage.
  ///
  /// In zh, this message translates to:
  /// **'这首歌还没有歌词。\n尽情享受音乐吧！'**
  String get lyricsUnavailableMessage;

  /// No description provided for @lyricsUnsynced.
  ///
  /// In zh, this message translates to:
  /// **'这些歌词尚未与歌曲同步。'**
  String get lyricsUnsynced;

  /// No description provided for @deviceConnectTitle.
  ///
  /// In zh, this message translates to:
  /// **'连接到设备'**
  String get deviceConnectTitle;

  /// No description provided for @deviceConnectDescription.
  ///
  /// In zh, this message translates to:
  /// **'通过 Spotify Connect，可在电脑、手机或智能音箱上无缝播放。'**
  String get deviceConnectDescription;

  /// No description provided for @deviceCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前收听设备'**
  String get deviceCurrent;

  /// No description provided for @deviceSpotifyConnect.
  ///
  /// In zh, this message translates to:
  /// **'Spotify Connect'**
  String get deviceSpotifyConnect;

  /// No description provided for @trackAddToPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'添加到歌单'**
  String get trackAddToPlaylist;

  /// No description provided for @trackAddToQueue.
  ///
  /// In zh, this message translates to:
  /// **'添加到播放队列'**
  String get trackAddToQueue;

  /// No description provided for @trackGoToAlbum.
  ///
  /// In zh, this message translates to:
  /// **'前往专辑'**
  String get trackGoToAlbum;

  /// No description provided for @trackGoToArtist.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, other{前往艺人}}'**
  String trackGoToArtist(int count);

  /// No description provided for @trackNewPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'新建歌单'**
  String get trackNewPlaylist;

  /// No description provided for @toastLikeAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加到已点赞的歌曲'**
  String get toastLikeAdded;

  /// No description provided for @toastLikeRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已从已点赞的歌曲中移除'**
  String get toastLikeRemoved;

  /// No description provided for @toastAddedToQueue.
  ///
  /// In zh, this message translates to:
  /// **'已添加到播放队列'**
  String get toastAddedToQueue;

  /// No description provided for @toastLinkCopied.
  ///
  /// In zh, this message translates to:
  /// **'链接已复制到剪贴板'**
  String get toastLinkCopied;

  /// No description provided for @toastAddedTo.
  ///
  /// In zh, this message translates to:
  /// **'已添加到「{name}」'**
  String toastAddedTo(String name);

  /// No description provided for @toastAlreadyIn.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」中已有这首歌'**
  String toastAlreadyIn(String name);

  /// No description provided for @createPlaylistTitle.
  ///
  /// In zh, this message translates to:
  /// **'为歌单命名'**
  String get createPlaylistTitle;

  /// No description provided for @createPlaylistHint.
  ///
  /// In zh, this message translates to:
  /// **'歌单名称'**
  String get createPlaylistHint;

  /// No description provided for @createPlaylistDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'我的歌单'**
  String get createPlaylistDefaultName;

  /// No description provided for @settingsSave.
  ///
  /// In zh, this message translates to:
  /// **'保存设置'**
  String get settingsSave;

  /// No description provided for @settingsSaved.
  ///
  /// In zh, this message translates to:
  /// **'Spotify API 配置已保存'**
  String get settingsSaved;

  /// No description provided for @settingsBannerTitle.
  ///
  /// In zh, this message translates to:
  /// **'Spotify 逆向工程已就绪'**
  String get settingsBannerTitle;

  /// No description provided for @settingsBannerMessage.
  ///
  /// In zh, this message translates to:
  /// **'配置逆向获取的 SpClient 令牌、OAuth 密钥或本地 MITM 代理地址。'**
  String get settingsBannerMessage;

  /// No description provided for @settingsCredentialsSection.
  ///
  /// In zh, this message translates to:
  /// **'API 凭据与代理'**
  String get settingsCredentialsSection;

  /// No description provided for @settingsBaseUrlLabel.
  ///
  /// In zh, this message translates to:
  /// **'API 基础地址'**
  String get settingsBaseUrlLabel;

  /// No description provided for @settingsBaseUrlHint.
  ///
  /// In zh, this message translates to:
  /// **'https://api.spotify.com/v1 或 http://localhost:8080/v1'**
  String get settingsBaseUrlHint;

  /// No description provided for @settingsTokenLabel.
  ///
  /// In zh, this message translates to:
  /// **'Spotify 访问令牌（Bearer）'**
  String get settingsTokenLabel;

  /// No description provided for @settingsTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'BQ…（OAuth 访问令牌）'**
  String get settingsTokenHint;

  /// No description provided for @settingsTokenManaged.
  ///
  /// In zh, this message translates to:
  /// **'已登录：令牌由 Login5 自动获取与续期'**
  String get settingsTokenManaged;

  /// No description provided for @settingsPasteToken.
  ///
  /// In zh, this message translates to:
  /// **'粘贴令牌'**
  String get settingsPasteToken;

  /// No description provided for @settingsSpClientLabel.
  ///
  /// In zh, this message translates to:
  /// **'SpClient Cookie（sp_dc / 内部令牌）'**
  String get settingsSpClientLabel;

  /// No description provided for @settingsSpClientHint.
  ///
  /// In zh, this message translates to:
  /// **'从 Spotify 桌面端 / Android 客户端的 Cookie 中提取'**
  String get settingsSpClientHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
