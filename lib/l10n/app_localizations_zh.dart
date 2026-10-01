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
  String get shellBack => '后退';

  @override
  String get shellForward => '前进';

  @override
  String get shellHome => '主页';

  @override
  String get shellSearchShortcut => 'Ctrl K';

  @override
  String get shellAccountMenu => '账号';

  @override
  String get shellCollapseLibrary => '收起音乐库';

  @override
  String get shellExpandLibrary => '展开音乐库';

  @override
  String get shellPlaybackStatus => '播放状态';

  @override
  String get shellHidePanel => '隐藏';

  @override
  String get shellAboutArtist => '关于艺人';

  @override
  String shellMonthlyFollowers(String count) {
    return '$count 位粉丝';
  }

  @override
  String get shellSignInTitle => '登录后查看你的音乐库';

  @override
  String get shellSignInMessage => '收藏的歌单、专辑和艺人会显示在这里。';

  @override
  String get shellSignIn => '登录';

  @override
  String get windowMinimize => '最小化';

  @override
  String get windowMaximize => '最大化';

  @override
  String get windowRestore => '向下还原';

  @override
  String get windowClose => '关闭';

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
  String get typeTrack => '歌曲';

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
  String get homeLoadFailedMessage => '请检查网络连接后重试。';

  @override
  String get homeEmptyTitle => '这里暂时没有内容';

  @override
  String get homeEmptyMessage => '换个筛选标签看看，或稍后再来。';

  @override
  String get homeClearFilter => '清除筛选';

  @override
  String get homePodcastUnsupported => '暂不支持播客，敬请期待';

  @override
  String get homeTypePodcast => '播客';

  @override
  String get homeTypeEpisode => '单集';

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
  String get searchCategoriesFailedMessage => '请检查网络连接后重试。';

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
  String get playerLyricsFullscreen => '全屏歌词';

  @override
  String get playerSwipeHint => '左右滑动封面切换歌曲';

  @override
  String get playbackErrorSignIn => '登录后才能播放';

  @override
  String playbackErrorUnavailable(String track) {
    return '「$track」暂时无法播放';
  }

  @override
  String playbackErrorSkipped(String track) {
    return '「$track」暂时无法播放，已跳过';
  }

  @override
  String playbackErrorNetwork(String track) {
    return '「$track」加载失败，请检查网络';
  }

  @override
  String playbackErrorAutoPaused(int count) {
    return '连续 $count 首无法播放，已暂停';
  }

  @override
  String get detailSignInRequired => '登录后即可查看这里的内容';

  @override
  String get detailLoadFailed => '暂时无法加载，请检查网络后重试';

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
  String get lyricsImmersive => '沉浸式歌词';

  @override
  String get lyricsExitImmersive => '退出全屏歌词（Esc）';

  @override
  String get lyricsFillScreen => '铺满整个屏幕（F11）';

  @override
  String get lyricsFillWindow => '只铺满窗口（F11）';

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
  String get connectThisDevice => '此设备';

  @override
  String get connectTakeOver => '在此设备继续播放';

  @override
  String connectPlayingOn(String device) {
    return '正在 $device 上播放';
  }

  @override
  String get connectOtherDevices => '选择其他设备';

  @override
  String get connectNoDevices => '没有找到其他设备';

  @override
  String get connectNoDevicesHint => '在手机、电脑或音箱上打开 Spotify，并登录同一账号';

  @override
  String get connectUnavailable => '使用桌面版方式登录后，即可遥控其他设备上的 Spotify';

  @override
  String get connectConnecting => '正在连接 Spotify Connect…';

  @override
  String get connectOffline => '连接已断开，正在重试…';

  @override
  String get connectSameNetwork => '同一网络';

  @override
  String get connectCommandFailed => '操作未成功：免费账号可能不支持远程执行此操作';

  @override
  String get connectVolume => '设备音量';

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
  String get shareCopyLink => '复制链接';

  @override
  String get shareCopyUri => '复制 URI';

  @override
  String get shareOpenWeb => '网页打开';

  @override
  String get shareCopied => '已复制';

  @override
  String get shareEmbedTitle => '嵌入代码';

  @override
  String get shareEmbedSubtitle => '粘贴到网页 HTML 中，即可展示 Spotify 播放器';

  @override
  String get shareEmbedStandard => '标准';

  @override
  String get shareEmbedCompact => '紧凑';

  @override
  String get shareEmbedDark => '深色';

  @override
  String get shareEmbedCopy => '复制代码';

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
  String get settingsAppearanceSection => '外观';

  @override
  String get settingsThemeMode => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsPureBlack => '纯黑背景';

  @override
  String get settingsPureBlackSubtitle => '深色模式下使用纯黑底色，OLED 屏幕更省电';

  @override
  String get settingsAccentSection => '强调色';

  @override
  String get settingsAccentCustom => '自定义颜色';

  @override
  String get settingsDynamicAccent => '跟随封面取色';

  @override
  String get settingsDynamicAccentSubtitle => '强调色随正在播放的专辑封面变化';

  @override
  String get settingsGlassSection => '液态玻璃';

  @override
  String get settingsGlassPreview => '玻璃预览';

  @override
  String get settingsGlassBlur => '模糊强度';

  @override
  String get settingsGlassOpacity => '不透明度';

  @override
  String get settingsTextShapeSection => '文字与形状';

  @override
  String get settingsFontScale => '字号';

  @override
  String get settingsFontPreview => '夜空中最亮的星';

  @override
  String get settingsCornerStyle => '圆角';

  @override
  String get settingsCornerRounded => '圆润';

  @override
  String get settingsCornerStandard => '标准';

  @override
  String get settingsCornerSquare => '方正';

  @override
  String get settingsPlaybackSection => '播放';

  @override
  String get settingsPauseAfterFailures => '连续无法播放时暂停';

  @override
  String settingsPauseAfterFailuresSubtitle(int count) {
    return '连续 $count 首无法播放就停下，不再继续自动跳过';
  }

  @override
  String get settingsMotionSection => '动效';

  @override
  String get settingsReduceMotion => '减弱动效';

  @override
  String get settingsReduceMotionSubtitle => '关闭流动背景、过渡与悬停等装饰性动画';

  @override
  String get settingsResetAppearance => '恢复默认外观';

  @override
  String get settingsCustomColorTitle => '自定义强调色';

  @override
  String get settingsHue => '色相';

  @override
  String get settingsSaturation => '饱和度';

  @override
  String get settingsBrightness => '亮度';

  @override
  String get settingsLanguageSection => '语言';

  @override
  String get settingsLanguage => '界面语言';

  @override
  String get settingsLanguageSubtitle => '同时影响主页推荐等由 Spotify 提供的文案';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageZh => '中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsStorageSection => '存储';

  @override
  String get settingsAudioCache => '音频缓存';

  @override
  String settingsAudioCacheUsage(String used, String limit) {
    return '已用 $used，上限 $limit';
  }

  @override
  String get settingsAudioCacheCalculating => '正在计算…';

  @override
  String get settingsAudioCacheLimit => '缓存上限';

  @override
  String get settingsAudioCacheLimitSubtitle => '超出后自动删除最久没播放的歌曲';

  @override
  String get settingsClearAudioCache => '清除音频缓存';

  @override
  String get settingsClearAudioCacheTitle => '清除音频缓存？';

  @override
  String get settingsClearAudioCacheMessage =>
      '已下载的歌曲会被删除，再次播放时重新下载。正在播放的歌曲会保留。';

  @override
  String settingsAudioCacheCleared(String size) {
    return '已释放 $size';
  }

  @override
  String get settingsLyricsSection => '歌词';

  @override
  String get settingsLyricsSize => '歌词字号';

  @override
  String get settingsLyricsAlign => '对齐方式';

  @override
  String get settingsLyricsAlignLeft => '左对齐';

  @override
  String get settingsLyricsAlignCenter => '居中';

  @override
  String get settingsLyricsBlur => '其他行模糊';

  @override
  String get settingsLyricsImmersiveScreen => '全屏歌词铺满整个屏幕';

  @override
  String get settingsLyricsImmersiveScreenSubtitle =>
      '关闭时只铺满窗口；在全屏歌词里按 F11 也能切换';

  @override
  String get settingsOff => '关';

  @override
  String get settingsNormalize => '音量均衡';

  @override
  String get settingsNormalizeSubtitle => '按 Spotify 提供的响度数据，把偏响的歌调低到一致的音量';

  @override
  String get settingsFade => '歌曲间淡入淡出';

  @override
  String get settingsFadeSubtitle => '结尾逐渐淡出，下一首淡入';

  @override
  String settingsSeconds(int count) {
    return '$count 秒';
  }

  @override
  String get settingsStartupSection => '启动';

  @override
  String get settingsStartPage => '启动时打开';

  @override
  String get settingsStartPageHome => '主页';

  @override
  String get settingsStartPageLibrary => '音乐库';

  @override
  String get settingsStartPageLast => '上次位置';

  @override
  String get settingsRememberWindow => '记住窗口大小和位置';

  @override
  String get settingsRememberWindowSubtitle => '下次启动时还原；显示器变化导致窗口不可见时回到屏幕中央';

  @override
  String get settingsConnectSection => 'Spotify Connect';

  @override
  String get settingsConnectEnabled => '启用 Spotify Connect';

  @override
  String get settingsConnectEnabledSubtitle => '显示并遥控同一账号在其他设备上的播放';

  @override
  String get settingsRemoteLyricsLead => '远程歌词提前';

  @override
  String get settingsRemoteLyricsLeadSubtitle => '其他设备上播放时，歌词比演唱慢就调大，快就调小';

  @override
  String get settingsPrivacySection => '隐私';

  @override
  String get settingsClearSearchHistory => '清除搜索记录';

  @override
  String settingsSearchHistoryCount(int count) {
    return '$count 条记录';
  }

  @override
  String get settingsSearchHistoryEmpty => '没有搜索记录';

  @override
  String get settingsClearLyricsCache => '清除歌词缓存';

  @override
  String get settingsClearLyricsCacheSubtitle => '清除后重新从 Spotify 获取歌词';

  @override
  String get settingsCleared => '已清除';

  @override
  String get settingsAboutSection => '关于';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsShortcuts => '键盘快捷键';

  @override
  String get settingsLicenses => '开源许可';

  @override
  String get shortcutPlayPause => '播放 / 暂停';

  @override
  String get shortcutNext => '下一首';

  @override
  String get shortcutPrevious => '上一首';

  @override
  String get shortcutVolumeUp => '调高音量';

  @override
  String get shortcutVolumeDown => '调低音量';

  @override
  String get shortcutShuffle => '随机播放';

  @override
  String get shortcutRepeat => '切换循环模式';

  @override
  String get shortcutSearch => '搜索';

  @override
  String get shortcutBack => '后退';

  @override
  String get shortcutForward => '前进';

  @override
  String get shortcutImmersive => '全屏歌词';

  @override
  String get shortcutImmersiveMode => '全屏歌词中：切换铺满屏幕 / 窗口';

  @override
  String get shortcutExitImmersive => '退出全屏歌词';

  @override
  String get accountTitle => 'Spotify 账号';

  @override
  String get accountSignedOutMessage => '登录后同步你的音乐库';

  @override
  String get accountSignIn => '登录';

  @override
  String get accountSignOut => '退出登录';

  @override
  String get accountSignOutTitle => '退出登录？';

  @override
  String get accountSignOutMessage => '将清除本机保存的登录信息与媒体库缓存，退出后需重新登录才能播放和查看媒体库。';

  @override
  String get accountSignOutConfirm => '退出';
}
