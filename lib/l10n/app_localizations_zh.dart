// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Flutify';

  @override
  String get commonCancel => '取消';

  @override
  String get commonCreate => '创建';

  @override
  String get commonDone => '完成';

  @override
  String get commonClose => '关闭';

  @override
  String get commonClear => '清除';

  @override
  String get commonRemove => '移除';

  @override
  String get commonRetry => '重试';

  @override
  String get commonMoreOptions => '更多选项';

  @override
  String get commonShowAll => '显示全部';

  @override
  String get commonSeeMore => '查看更多';

  @override
  String get commonShowLess => '收起';

  @override
  String get commonSettings => '设置';

  @override
  String get commonShare => '分享';

  @override
  String subtitleJoin(String first, String second) {
    return '$first · $second';
  }

  @override
  String get navHome => '主页';

  @override
  String get navSearch => '搜索';

  @override
  String get navLibrary => '音乐库';

  @override
  String get typeArtist => '艺人';

  @override
  String get typePlaylist => '歌单';

  @override
  String get typeAlbum => '专辑';

  @override
  String get typeSingle => '单曲';

  @override
  String get typeCompilation => '合辑';

  @override
  String get filterAll => '全部';

  @override
  String get filterMusic => '音乐';

  @override
  String get filterPodcasts => '播客';

  @override
  String get filterSongs => '歌曲';

  @override
  String get filterArtists => '艺人';

  @override
  String get filterPlaylists => '歌单';

  @override
  String get filterAlbums => '专辑';

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 首歌曲',
    );
    return '$_temp0';
  }

  @override
  String followerCount(String count) {
    return '$count 位粉丝';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '$minutes 分 $seconds 秒';
  }

  @override
  String countAndDuration(String count, String duration) {
    return '$count，$duration';
  }

  @override
  String get greetingMorning => '早上好';

  @override
  String get greetingAfternoon => '下午好';

  @override
  String get greetingEvening => '晚上好';

  @override
  String get likedSongs => '已点赞的歌曲';

  @override
  String get likedSongsDescription => '你喜欢的所有歌曲都在这里。';

  @override
  String get likeAdd => '添加到已点赞的歌曲';

  @override
  String get likeRemove => '从已点赞的歌曲中移除';

  @override
  String get libraryAdd => '保存到音乐库';

  @override
  String get libraryRemove => '从音乐库中移除';

  @override
  String get homeLoadFailedTitle => '无法加载推荐内容';

  @override
  String get homeLoadFailedMessage => '请检查网络连接或 API 设置。';

  @override
  String get homeMadeForYou => '为你打造';

  @override
  String get homeMadeForYouSubtitle => '每日更新的新鲜音乐与推荐。';

  @override
  String get homePopularReleases => '热门新发行';

  @override
  String get homePopularReleasesSubtitle => '当下最受欢迎的专辑。';

  @override
  String get homePopularArtists => '热门艺人';

  @override
  String get homeNoPodcastsTitle => '暂无播客';

  @override
  String get homeNoPodcastsMessage => '播客节目和单集会显示在这里。';

  @override
  String get searchHint => '你想听什么？';

  @override
  String get searchRecent => '最近搜索';

  @override
  String get searchClearAll => '全部清除';

  @override
  String get searchBrowseAll => '浏览全部';

  @override
  String get searchCategoriesFailedTitle => '无法加载分类';

  @override
  String get searchCategoriesFailedMessage => '请检查网络连接或 API 设置后重试。';

  @override
  String searchNoResultsTitle(String query) {
    return '未找到与“$query”相关的结果';
  }

  @override
  String get searchNoResultsMessage => '请检查拼写，或换个关键词试试。';

  @override
  String get searchFilterEmptyTitle => '该分类下暂无结果';

  @override
  String get searchFilterEmptyMessage => '换个筛选条件，查看更多结果。';

  @override
  String searchCategoryMix(String name) {
    return '$name 精选';
  }

  @override
  String searchCategoryMixDescription(String name) {
    return '精选 $name 好歌，新鲜好听。';
  }

  @override
  String get librarySearchHint => '在音乐库中搜索';

  @override
  String get libraryCloseSearch => '关闭搜索';

  @override
  String get libraryCreatePlaylist => '创建歌单';

  @override
  String get libraryClearFilter => '清除筛选';

  @override
  String get librarySortRecent => '最近添加';

  @override
  String get librarySortAlphabetical => '按字母顺序';

  @override
  String get libraryListView => '列表视图';

  @override
  String get libraryGridView => '网格视图';

  @override
  String get libraryEmptyTitle => '这里还没有内容';

  @override
  String get libraryEmptyMessage => '收藏的歌单、艺人和专辑会显示在这里。';

  @override
  String libraryNewPlaylistName(int number) {
    return '我的歌单 #$number';
  }

  @override
  String get playlistDelete => '删除歌单';

  @override
  String get playlistLikedEmpty => '你点赞的歌曲会显示在这里。\n点按爱心图标即可收藏歌曲。';

  @override
  String get playlistOwnEmpty => '来为你的歌单找些歌曲吧。\n在任意歌曲的菜单中选择“添加到歌单”。';

  @override
  String get playlistEmpty => '这个歌单还没有歌曲。';

  @override
  String get albumNoTracks => '这张专辑暂无可播放的曲目。';

  @override
  String albumMoreBy(String name) {
    return '$name 的更多作品';
  }

  @override
  String get artistPopular => '热门歌曲';

  @override
  String get artistNoPopular => '暂无热门歌曲。';

  @override
  String get artistDiscography => '作品';

  @override
  String get artistFollow => '关注';

  @override
  String get artistFollowing => '已关注';

  @override
  String get playingFromPlaylist => '正在播放歌单';

  @override
  String get playingFromAlbum => '正在播放专辑';

  @override
  String get playingFromArtist => '正在播放艺人';

  @override
  String get playingFromSearch => '正在播放搜索结果';

  @override
  String get playingFromLibrary => '正在播放音乐库';

  @override
  String get nowPlaying => '正在播放';

  @override
  String get openNowPlaying => '打开正在播放';

  @override
  String get playerNothingPlayingTitle => '当前没有播放内容';

  @override
  String get playerNothingPlayingMessage => '选择一首歌曲、专辑或歌单，开始收听吧。';

  @override
  String get playerIdleHint => '暂无播放 — 挑点音乐来听吧';

  @override
  String get playerThisDevice => '正在本设备上收听';

  @override
  String get playerShuffleOn => '开启随机播放';

  @override
  String get playerShuffleOff => '关闭随机播放';

  @override
  String get playerRepeatOn => '开启列表循环';

  @override
  String get playerRepeatOneOn => '开启单曲循环';

  @override
  String get playerRepeatOff => '关闭循环';

  @override
  String get playerNext => '下一首';

  @override
  String get playerPrevious => '上一首';

  @override
  String get playerMute => '静音';

  @override
  String get playerUnmute => '取消静音';

  @override
  String get queueTitle => '播放队列';

  @override
  String get queueNextInQueue => '队列中的下一首';

  @override
  String get queueClear => '清空队列';

  @override
  String get queueNextUp => '接下来播放';

  @override
  String queueNextFrom(String name) {
    return '接下来播放：$name';
  }

  @override
  String get queueEmpty => '队列中暂无待播歌曲';

  @override
  String get lyricsTitle => '歌词';

  @override
  String get lyricsNotPlaying => '未在播放';

  @override
  String get lyricsNothingPlayingMessage => '播放一首歌曲，即可在这里查看歌词。';

  @override
  String get lyricsUnavailableTitle => '暂无歌词';

  @override
  String get lyricsUnavailableMessage => '这首歌还没有歌词。\n尽情享受音乐吧！';

  @override
  String get lyricsUnsynced => '这些歌词尚未与歌曲同步。';

  @override
  String get deviceConnectTitle => '连接到设备';

  @override
  String get deviceConnectDescription =>
      '通过 Spotify Connect，可在电脑、手机或智能音箱上无缝播放。';

  @override
  String get deviceCurrent => '当前收听设备';

  @override
  String get deviceSpotifyConnect => 'Spotify Connect';

  @override
  String get trackAddToPlaylist => '添加到歌单';

  @override
  String get trackAddToQueue => '添加到播放队列';

  @override
  String get trackGoToAlbum => '前往专辑';

  @override
  String trackGoToArtist(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '前往艺人',
    );
    return '$_temp0';
  }

  @override
  String get trackNewPlaylist => '新建歌单';

  @override
  String get toastLikeAdded => '已添加到已点赞的歌曲';

  @override
  String get toastLikeRemoved => '已从已点赞的歌曲中移除';

  @override
  String get toastAddedToQueue => '已添加到播放队列';

  @override
  String get toastLinkCopied => '链接已复制到剪贴板';

  @override
  String toastAddedTo(String name) {
    return '已添加到「$name」';
  }

  @override
  String toastAlreadyIn(String name) {
    return '「$name」中已有这首歌';
  }

  @override
  String get createPlaylistTitle => '为歌单命名';

  @override
  String get createPlaylistHint => '歌单名称';

  @override
  String get createPlaylistDefaultName => '我的歌单';

  @override
  String get settingsSave => '保存设置';

  @override
  String get settingsSaved => 'Spotify API 配置已保存';

  @override
  String get settingsBannerTitle => 'Spotify 逆向工程已就绪';

  @override
  String get settingsBannerMessage =>
      '配置逆向获取的 SpClient 令牌、OAuth 密钥或本地 MITM 代理地址。';

  @override
  String get settingsCredentialsSection => 'API 凭据与代理';

  @override
  String get settingsBaseUrlLabel => 'API 基础地址';

  @override
  String get settingsBaseUrlHint =>
      'https://api.spotify.com/v1 或 http://localhost:8080/v1';

  @override
  String get settingsTokenLabel => 'Spotify 访问令牌（Bearer）';

  @override
  String get settingsTokenHint => 'BQ…（OAuth 访问令牌）';

  @override
  String get settingsTokenManaged => '已登录：令牌由 Login5 自动获取与续期';

  @override
  String get settingsPasteToken => '粘贴令牌';

  @override
  String get settingsSpClientLabel => 'SpClient Cookie（sp_dc / 内部令牌）';

  @override
  String get settingsSpClientHint => '从 Spotify 桌面端 / Android 客户端的 Cookie 中提取';
}
