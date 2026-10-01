# Flutify 进度与待办（2026-10-01 更新）

> 新对话开始时先读本文件与 `README.md`。Flutter SDK：`D:\flutter-sdk\3.44.0\flutter\bin\flutter.bat`。
> Git 仓库在 `D:\Flutify\app`（基线提交 `6c8e00a`，之后按「后端 / 前端」分两次提交）。
> API 文档：`D:\Flutify\SpotifyApi\api-docs`（Android/spclient）、`D:\Flutify\SpotifyApi\desktop-api-docs`（桌面端）。

## 已完成

- [x] 桌面版 OAuth 登录（默认），客户端身份一致性（`lib/services/auth/client_profile.dart`）
- [x] 桌面会话数据层改走 Pathfinder GraphQL + spclient（`lib/services/pathfinder/`），解析器测试 `test/pathfinder_parsers_test.dart`
- [x] 简体中文（gen-l10n，`lib/l10n/app_zh.arb` 为模板，`app_en.arb` 同步）+ MiSans 字体（4 个字重，`assets/fonts/MiSans/`）
- [x] Git 初始化

## 已完成 ①：真实数据与播放（代码完成，**真实账号未实测**）

- [x] 真实播放链路（AP → 音频密钥 → storage-resolve → CDN 解密 → just_audio），不可播放 / DRM 曲目抛 `TrackPlaybackException`，
      `PlaybackProvider.playbackError` / `playbackErrors` 暴露错误，「不可播放」自动跳下一首
- [x] 删除 `mock_spotify_data.dart` 与全部 Mock 兜底；设置页去掉「示例数据」开关与 API 调试区
- [x] 媒体库接真实接口（`lib/services/library/`），未登录为空；歌词走 color-lyrics（`lyrics_service.dart`）
- [x] 测试改用 `test/fixtures/sample_catalog.dart` 的合成数据；`tool/` 探针整理完毕
- [x] 界面接住错误：播放失败浮动提示（`playback_error_listener.dart`，未登录带「登录」、网络错误带「重试」）；
      歌单详情 `SpotifyDataException` → 登录 / 重试占位；专辑 / 艺人未登录时显示登录引导；主页未登录提示登录

### 待实测 / 待改进（依赖真实账号，需要用户在本机运行 `tool/live_probe.dart`）

- [ ] 实测完整播放：`dart run tool/live_probe.dart play`，确认音频密钥 → CDN 解密 → 可播放
- [ ] 实测媒体库：`dart run tool/live_probe.dart library`，核对 `collection/v2/paging` 的 protobuf 字段号与 rootlist 结构（目前按桌面端 xpui 定义推断，未验证）
- [ ] 主页「热门专辑 / 艺人」货架目前以用户媒体库内容填充，应改为取主页官方分区
- [ ] 分类页（browsePage）尚未接入，点分类目前打开空歌单
- [ ] 歌单的新建 / 保存 / 取消保存尚未同步到账号（Playlist4 写协议未验证）；目前仅本机
- [ ] 完整曲目整首下载完才开始播放，后续可改流式（StreamAudioSource）
- [ ] 专辑 / 艺人曲目请求失败时数据层返回空列表，界面只能显示「没有曲目」；如需区分网络错误，数据层要改为抛异常

## 已完成 ②：界面重设计（测试全部通过，**实机外观待用户查看**）

Spotify 新版桌面三栏布局 + MD3E 质感；跟随系统深浅色；自绘标题栏（window_manager）。详见 README「响应式外壳」。

- [x] 三栏外壳（`lib/ui/shell/`）：自绘标题栏、顶栏、音乐库左栏（拖宽 / 收起 72px）、右栏（≥ 1280 停靠，1100 – 1280 浮层默认关闭、Esc / 点空白关闭）
- [x] 底部播放栏按宽度依次隐藏音量条、音量键，不再溢出；左栏收起动画期间按实际宽度切换紧凑模式
- [x] 第 4 步：详情页大头图 `collection_hero.dart`（主色一直延伸到操作行、自适应字号标题、吸顶标题栏带播放键）；
      卡片悬停播放键（按下形变）；曲目行悬停 ▶ / 收藏 / ⋯；右键菜单 `track_menu.dart`（加入歌单二级菜单）
- [x] 浅色模式：药丸、播放键（统一亮绿 + 黑图标）、详情页头部、全屏播放器（强制深色）逐页修正
- [x] 第 5 步：毛玻璃底部导航 + 悬浮胶囊迷你播放器（`shell/mobile/mobile_bottom_bar.dart`）；全屏播放器内嵌歌词 / 队列、左右滑动切歌
      （`player/widgets/swipeable_artwork.dart`）；状态栏图标随背景（`core/theme/system_bars.dart`）；页面底部留白 `ContentBottomSpacer`
- [x] 第 6 步：`test/ui/` 覆盖 1440 / 1024 / 390 三种宽度、悬停与右键、移动端播放器、错误状态；README / TODO 已更新

### 需要用户在实机上看的（自动化测试覆盖不到）

- [ ] 标题栏拖动 / 双击最大化、窗口按钮；左栏拖宽和收起；右栏停靠 ↔ 浮层切换
- [ ] 深浅色切换后各页观感；详情页头图主色是否自然；悬停动效节奏
- [ ] Android：毛玻璃导航的模糊性能、状态栏图标颜色、滑动切歌手感

## 已完成 ③：自定义主题 / 液态玻璃歌词 / 手机竖屏（测试全部通过，**实机外观待用户查看**）

- [x] 外观设置（`models/appearance.dart` + `providers/appearance_provider.dart`，持久化键 `ui_appearance`）：
      主题模式、强调色（7 预设 + HSV 自定义）、跟随封面取色、玻璃模糊 / 不透明度、纯黑背景、字号、圆角风格、减弱动效
- [x] 主题令牌 `core/theme/flutify_tokens.dart`（ThemeExtension）：`context.tokens.accent / radius() / pill / glassSigma`、
      `context.motion()`；按钮、药丸、卡片、封面、面板、迷你播放器、全屏播放器均已接入
- [x] 设置页重写为 iOS 分组样式（`settings/sections/` + `settings/widgets/`），删除逆向横幅、手动凭据区、令牌信息与「刷新令牌」；
      登录页底部协议 / 风控说明删除；账号卡片文案迁入 ARB
- [x] 所有歌词液态玻璃化：共用 `player/lyrics/lyrics_backdrop.dart`、`lyrics_glass_controls.dart`、`glass_icon_button.dart`；
      全屏播放器歌词视图背景交叉淡入流动封面、控件收进玻璃；桌面右栏歌词同款背景 + 「沉浸式」入口
- [x] 桌面沉浸式歌词 `player/immersive_lyrics_screen.dart`：窗口系统全屏，左封面 + 控制台、右大字号歌词；
      Esc / F11 退出，鼠标静止 3 秒隐藏光标与按钮；入口：播放栏、右栏歌词、全屏播放器歌词、F11
- [x] 手机锁定竖屏（`core/utils/orientation_policy.dart`，最短边 < 600 才锁）；离屏渲染审查 `test/audit/`（默认跳过，见 README）

### 需要用户在实机上看的

- [ ] 沉浸式歌词进入 / 退出系统全屏是否顺滑（Windows），退出后窗口是否回到原大小
- [ ] 玻璃模糊调到最大时 Android 上的流畅度；跟随封面取色在浅色主题下的对比度

## 已完成 ④：实机反馈修复（测试全部通过，**待用户实机复测**）

- [x] 桌面版会话缺用户名 → 「已点赞歌曲」/ 歌单根列表为空：登录后用令牌登录 AP 取 canonical username
      （`SpotifyAuthService._usernameFromAccessPoint`，可注入 `usernameResolver` 便于测试）；旧会话启动时自动补齐并重载媒体库
- [x] 昵称显示成别人（Micael Widell）：`profile/me` 是用户名为 "me" 的账号，改为 `profile/{用户名}`
- [x] 桌面设置页嵌入内容区（保留顶栏、窗口按钮），大标题 + 横向设置行，内容区够宽时双栏
- [x] 窗口外框 `shell/desktop/window_frame.dart`：窗口按钮在所有路由之上；最小窗口 360×600，窄窗口为移动端布局 + 32px 标题条
- [x] 设置页卡顿：关闭主题插值动画（`themeAnimationDuration: Duration.zero`）；滑杆拖动只局部预览、松手提交
- [x] 播放失败提示改为 MD3E 悬浮卡（`snackBarTheme` + 错误类型图标），桌面端居中在播放栏之上

- [x] 连续 3 首无法播放自动暂停（设置 →「播放」，默认开启，提示带「下一首」）
- [x] 布局兜底：强调色色板临界宽度溢出修复；主页快捷网格行高随字号放大；
      `test/ui/layout_sweep_test.dart` 在 320 – 1440 共 15 个宽度 × 两档字号下检查溢出
- [x] 底部提示兜底：位置改由外壳决定（桌面播放栏作 bottomNavigationBar + 主题限宽 440），
      不再在弹出时按窗口宽度算死边距；带按钮的提示 7 秒自动收起；
      `test/ui/snackbar_sweep_test.dart` 弹出后拖过断点 / 最小窗口，检查文字可读、卡片不出界
- [x] 头像统一为 `widgets/user_avatar.dart`：无头像时首字 + 按用户名固定的底色，不随强调色 / 封面取色变化
- [x] 歌单封面：支持上传封面 `attributes.picture`（Base64 图片 ID）；无封面的自建歌单用前几首曲目专辑封面拼四宫格
      （`services/library/playlist_cover.dart`）
- [x] 主页按官方结构重做（`services/pathfinder/home_parser.dart` + `ui/screens/home/widgets/`）：
      吸顶筛选标签（服务端 homeChips，含二级标签）、快捷入口（最多 8 个）、普通卡架（艺人头像 / 显示全部）、
      最近播放、推荐流网格（FeedBaseline 合并 + 推荐理由，只显示整行）；请求带 `Accept-Language: zh-CN`，
      问候语 / 分区标题 / 标签由服务端本地化；`test/ui/home_layout_test.dart` 填满数据扫 15 宽度 × 两档字号
- [x] 退出沉浸式全屏后的大片黑边：window_manager 只在 SIZE_MAXIMIZED 时记为全屏，从普通窗口进入时退出不刷新子视图；
      `DesktopWindow._refreshFrame` 退出后宽度 +1 再还原，强制重排
- [x] 分享面板 MD3E 化（`ui/widgets/share/`）：复制链接 / URI / 网页打开 + iframe 嵌入代码（尺寸、深色、预览），
      就地「已复制」反馈；歌单 / 专辑 / 艺人详情页新增分享按钮；`test/ui/share_sheet_test.dart` 6 种窗口 × 两档字号
- [x] 嵌入预览改为真实 WebView（`share/embed_web_view.dart`），外链交给系统浏览器；不可用时退回示意预览
- [x] Spotify Connect 遥控（只做免费账号可用的部分）：隐藏观察者接入、设备面板 MD3E 重做、转移播放 / 此设备继续、
      远程模式播放栏与迷你播放器（播放暂停 / 切歌 / 进度 / 随机 / 循环 / 音量）；
      `test/connect/` 覆盖协议层（假 dealer），`test/ui/connect_ui_test.dart` 覆盖界面（合成设备，多宽度 × 两档字号）

### 需要用户在实机上看的

- [ ] 沉浸式歌词退出后黑边是否消失（含进入前为最大化 / 普通窗口两种情况）
- [ ] 分享面板「网页打开」能否拉起默认浏览器；嵌入页 WebView 是否正常显示、深色切换是否刷新
- [ ] Connect：设备面板能否列出手机 / 其他电脑；手机播放时 Flutify 播放栏是否切成远程模式、进度是否同步；
      免费账号下哪些命令被拒（转移 / 暂停 / 切歌 / 进度 / 音量），被拒时是否有提示

- [ ] 重启后昵称 / 头像是否为本人、「已点赞歌曲」是否出现
- [ ] 主页 / 音乐库里之前没图的两个歌单是否显示封面
- [ ] 窄窗口（< 800）下的标题条拖动、窗口按钮；右键菜单位置是否准确

## 其他待办 / 优化

- [ ] 主页顶部渐变：随快捷入口悬停的封面取色变化（官方桌面端效果）
- [ ] 主页播客 / 单集：目前只展示，点按提示暂不支持
- [ ] 音乐库「按字母顺序」改为按拼音排序（左栏 `library_sidebar_entry.dart` 与移动端 `library_screen.dart` 两处）
- [ ] 登录页的中文文案迁入 ARB（账号卡片已完成）
- [ ] 外观设置跨设备同步（目前仅本机）；沉浸式歌词支持逐字歌词（需 color-lyrics 的 syllable 数据）
- [ ] Connect：远程模式下打开全屏播放器（目前点按打开设备面板）；本机作为可被遥控的播放端（需要实现 Connect 播放端协议）
- [ ] 桌面客户端升级后 Pathfinder hash 失效检测与提示
