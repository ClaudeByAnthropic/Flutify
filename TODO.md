# Flutify 进度与待办（2026-10-02 更新）

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
- [x] 分类页（browsePage）已接入（见「已完成 ⑦」）
- [ ] 歌单的新建 / 保存 / 取消保存尚未同步到账号（Playlist4 写协议未验证）；目前仅本机
- [x] 完整曲目整首下载完才开始播放 → 已改为边下边播（见「已完成 ⑤」）
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
- [x] 远程模式歌词：右栏、手机歌词面板、沉浸式歌词跟随远程曲目与进度，控制台 / 点行跳转发给远程设备
- [x] 沉浸式歌词默认只铺满窗口（深色窗口按钮 + 顶部拖动区），右上角按钮 / F11 切换到系统全屏，记住选择
- [x] 长歌单触控板滑动卡顿：曲目行未悬停时不构建 IconButton（只放同尺寸占位 / 静态爱心）；歌单曲目改为原型定高列表；
      详情页头部按宽度缓存，不再每帧重建。`test/ui/long_playlist_scroll_test.dart` 守护（2000 首合成歌单）
- [x] 更多设置项（全部免费账号可用）：语言、歌词样式、音量均衡、淡入淡出、启动页、窗口记忆、Connect 开关与远程歌词提前量、
      音频缓存占用 / 上限 / 清除、清除搜索记录 / 歌词缓存、版本 / 快捷键 / 开源许可。
      `test/ui/settings_more_test.dart` 端到端，模型与算法另有单元测试（偏好解析、窗口位置、响度解析、音量合成）

### 需要用户在实机上看的

- [ ] 沉浸式歌词退出后黑边是否消失（含进入前为最大化 / 普通窗口两种情况）
- [ ] 分享面板「网页打开」能否拉起默认浏览器；嵌入页 WebView 是否正常显示、深色切换是否刷新
- [ ] Connect：设备面板能否列出手机 / 其他电脑；手机播放时 Flutify 播放栏是否切成远程模式、进度是否同步；
      免费账号下哪些命令被拒（转移 / 暂停 / 切歌 / 进度 / 音量），被拒时是否有提示
- [ ] 远程歌词与手机上的演唱是否同步（服务端快照推算，可能差几百毫秒）
- [ ] 沉浸式歌词「只铺满窗口」：窗口按钮是否可见可用、顶部能否拖动窗口；与系统全屏来回切换后是否有黑边
- [ ] 长歌单触控板滑动是否顺滑（Debug 版本身明显偏慢，以 Release 版为准）；右栏歌词打开 / 关闭时对比是否有差别
- [ ] 窗口记忆：拖到副屏 / 最大化后重启是否还原；拔掉副屏后是否回到主屏居中
- [ ] 音量均衡：清除音频缓存后重新下载的歌是否生效（旧缓存没有响度数据）；淡入淡出的听感与时长是否合适
- [ ] 切换语言后主页推荐文案是否跟着变；关闭 Connect 后播放栏是否立即回到本机模式

- [ ] 重启后昵称 / 头像是否为本人、「已点赞歌曲」是否出现
- [ ] 主页 / 音乐库里之前没图的两个歌单是否显示封面
- [ ] 窄窗口（< 800）下的标题条拖动、窗口按钮；右键菜单位置是否准确

## 已完成 ⑤：边下边播 + 恢复上次播放（测试全部通过，**待用户实机复测**）

- [x] 边下边播：`services/protocol/progressive_download.dart`（流式解密到内存、Range 续传 + 轮换 CDN、按区间读取）、
      `services/downloading_audio_source.dart`（just_audio StreamAudioSource）；`TrackAudioSource.open()` 头部到达即返回，
      `load()` 仍等整首（预取用），两者共享同一份进行中的下载；`AesCtr.atOffset` 支持任意偏移解密，AES 逐块原地运算
- [x] 恢复上次播放：`models/playback_session.dart` + `services/playback_session_store.dart`（`playback_session.json`），
      `PlaybackProvider` 启动还原 / 变化时保存；`DesktopWindow.addBeforeCloseHook` 关窗前保存，`PlaybackSessionKeeper` 手机切后台时保存
- [x] 测试：`test/protocol/progressive_download_test.dart`（解密 / 去头 / 续传 / 失败 / MP3）、`aes_test.dart` 偏移等价、
      `test/playback_session_test.dart`（还原、断点续播、窗口截取、文件读写与损坏）

### 需要用户在实机上看的

- [ ] 点一首没缓存过的歌，是否 1 秒内出声（之前要等整首下载完）；拖到还没下载的位置是否只短暂缓冲
- [ ] Windows（media_kit）与 Android（ExoPlayer）下边播边拖动是否都正常；歌曲时长显示是否正确
- [ ] 关掉 App 再打开：播放栏是否显示上次的歌和进度，点播放是否从断点继续；Alt+F4 / 任务栏关闭后是否也能还原
- [ ] 关窗是否仍然立即关闭（关窗前会等保存完成，最多 0.8 秒）

## 已完成 ⑥：系统媒体控制 + 后台解密 + Win11 分屏布局（测试全部通过，Release 编译通过，**待用户实机复测**）

- [x] 后台解密：`services/protocol/decrypt/`。`DecryptSpec` 描述「怎么解」（当前 `AesCtrDecryptSpec`，另有 `PassthroughDecryptSpec`），
      `DecryptBackend` 决定「在哪解」：`IsolateDecryptBackend` 常驻一个后台 Isolate（启动时预热，崩溃后下次自动重建），
      `InlineDecryptBackend` 在当前 Isolate（测试用）。数据用 `TransferableTypedData` 零拷贝往返。
      **新解密方法接入**：实现 `DecryptSpec` + `AudioDecryptor`（字段只放可跨 Isolate 发送的数据），
      在 `TrackAudioLoader` 里按格式 / 曲目选择对应 Spec 即可，下载、续传、后台线程都不用动
- [x] 系统媒体控制：`services/media_controls/`。`SystemMediaControls` 抽象 + `MediaControlsSync`（把 `PlaybackProvider` 同步给系统、
      系统按钮回传）。Windows 走自写 C++/WinRT SMTC（`windows/runner/media_controls.cpp`，通道 `flutify/media_controls`）：
      任务栏 / 锁屏 / 音量浮层媒体卡片、键盘媒体键、进度条拖动；Android / iOS 走 audio_service（通知栏 / 锁屏控件，
      `MainActivity` 改继承 `AudioServiceActivity`，Manifest 加前台服务与权限）
- [x] 媒体卡片跟随 Connect：`MediaSourceOverride` 接口 + `ConnectMediaSource`。在其他设备上播放时（与播放栏远程模式同一规则，
      `ConnectProvider.controlsRemote`）卡片显示远程曲目 / 状态 / 进度，媒体键与卡片按钮发给远程设备；
      控制权跟随「最后出声的一方」，暂停远程后按空格 / 播放键仍继续远程，本机开始播放才交回本机
- [x] Win11 分屏布局：`windows/runner/snap_layout.cpp` + `ui/shell/desktop/snap_layout_bridge.dart`。
      Dart 报告最大化按钮位置，原生在 `WM_NCHITTEST` 返回 `HTMAXBUTTON`（Flutter 子窗口对该区域返回 `HTTRANSPARENT`），
      系统据此弹出分屏布局；悬停 / 按下 / 点击由原生转回 Dart 驱动按钮外观与最大化
- [x] runner 编译加 `/utf-8`（中文注释在 GBK 代码页下触发 C4819）；`test/media_controls_sync_test.dart`，
      `progressive_download_test.dart` 同时跑内联与后台 Isolate 两种后端

### 需要用户在实机上看的

- [ ] Windows：播放时按音量键 / 媒体键，系统浮层是否出现 Flutify 卡片（封面、歌名、进度）；媒体键、卡片上的切歌 / 拖进度是否生效
- [ ] Windows 11：鼠标悬停最大化按钮是否弹出分屏布局；按钮悬停 / 按下效果、单击最大化 / 还原是否正常；高 DPI 与副屏下位置是否准确
- [ ] Android（本机无 SDK，**未编译验证**）：通知栏 / 锁屏播放控件、耳机线控；Android 13+ 首次是否请求通知权限
- [ ] 下载 320k 曲目时界面是否不再掉帧

## 已完成 ⑦：统一登录修复 + 待办收尾（测试全部通过，Release 编译通过，**待用户实机复测**）

- [x] 统一登录页卡在 `open.spotify.com`：`WebLoginScreen` 的 `CookieManager` 未绑定 `EmePlayer` 的 WebViewEnvironment，
      读 cookie 一直抛 `ERROR_INVALID_STATE`。现改为可测试的流程状态机：轮询读取 sp_dc（多 URL 兜底）→ 换 Web token 验证 →
      未授权时同一 WebView 会话后台完成桌面 OAuth（12 秒未自动完成则露出授权页手动同意）
- [x] 分类页 browsePage（hash 取自 gql_ops，复用主页卡片）；Pathfinder hash 失效（PersistedQueryNotFound）提示更新
- [x] 登出 / 切换账号清除上次播放会话（内存 + 磁盘）
- [x] 音乐库「按字母顺序」中文按拼音排序（左栏 + 移动端，`pinyin` 包）
- [x] Connect 远程模式点按打开全屏播放器（曲目 / 进度 / 控制台 / 滑动切歌全走远程）
- [x] 主页顶部渐变随快捷入口悬停取色
- [x] 修好 WIP 重构后 15 个测试文件的编译

## 已完成 ⑧：实机反馈修复（代码已改，**未提交**，回归测试补写中）

- [x] 右栏歌词换行时整个右栏跟着滚：`Scrollable.ensureVisible` 会沿嵌套滚动容器向外滚，
      `LyricsView._scrollToActive` 改用歌词自身的 `position.ensureVisible`（新测试 `test/ui/lyrics_auto_scroll_test.dart`）
- [x] 横屏下底部播放栏遮挡左栏 / 右栏最底部内容（BUG-2b）：两栏滚动末尾留出播放栏高度（新测试 `test/ui/sidebar_bottom_inset_test.dart`）
- [x] 手机竖屏歌单内搜索框太小点不进去：窄布局工具条独占一行，点开搜索后输入框优先（高 44），排序键截断

- [x] 横屏（桌面三栏）下右栏已打开时点击播放栏左下角封面，会弹出手机端的全屏播放器。
      `PlayerBarCover` 改为：有三栏框架时始终切换（打开 / 关闭）右栏「正在播放」，只有手机布局才打开全屏播放器（待实机复测）

## 调研：Connect 播放端（让 Flutify 出现在手机设备列表里、可被遥控）

两套协议，选 **A（网页版同款）**：

- **A. track-playback（Web 播放器 / harmony SDK 用的）**：服务器维护播放状态机，客户端只播放和汇报。
  - 注册：`POST @webgate/track-playback/v1/devices`，JSON
    `{device, connection_id, client_version, volume, outro_endcontent_snooping:false, previous_session_state}`；
    `device` = `{brand, capabilities, device_id, device_type, metadata, model, name, platform_name, platform_identifier, is_group, is_public, correlation_id, client_version}`。
    429 = 连接数已满；403 + `PREMIUM_REQUIRED` = 非会员不能注册（网页版免费账号能用，需实测我们的 Web token 是否同样放行）
  - 命令（dealer 推送，`_onTrackPlaybackMessage` → `payloads[0].type`）只有 4 种：
    `replace_state`（新状态机 + `state_ref` + `prev_state_ref` + 可选 `seek_to`，播放 / 暂停 / 切歌 / 换歌单全走它）、`set_volume`（0–65535）、`log_out`、`ping`
  - 汇报：`PUT …/devices/{id}/state`，`{seq_num, state_ref:{state_machine_id, state_id, paused}, sub_state:{playback_speed, position, duration, media_type, bitrate, audio_quality, format}, previous_position, debug_source}`；
    事件 `debug_source` 取 REGISTER / BEFORE_TRACK_LOAD / STARTED_PLAYING / PROGRESS / PAUSE / RESUME / SEEK / PLAYED_THRESHOLD_REACHED / TRACK_DATA_FINALIZED / STATE_CLEAR / PING 等；
    `prev_state_ref` 对不上时 `POST …/state_conflict` 拒绝；音量 `PUT …/volume`；注销 `DELETE …/devices/{id}`
  - 源码位置：`vendor~web-player.*.js` 中 `_performCommand` / `_replaceState` / `_generateStatePayload` / `register()`
- **B. connect-state（官方桌面端 / librespot 用的）**：客户端自己维护歌单上下文、队列、随机、循环；
  `PUT connect-state/v1/devices/{id}`（protobuf PutStateRequest），dealer `request` 命令 13+ 种
  （transfer 带 base64 TransferState、play、pause、seek_to、skip_next…），需回 `{"type":"reply","key":…,"payload":{"success":true}}`。
  工作量约为 A 的数倍；设备信息模板见 `tool/probe_out/connect_cluster.json`
- 现有可复用：`services/connect/dealer_client.dart`（需补 `request` 类型与回执）、`connect_state_client.dart`、Web token / client-token

### 与全曲播放 429 相关的发现（限流解除后先验证）

- 网页版播放时还会发 `melody/v1/msg/batch` 的 `track_stream_verification`，并通过 `track-playback/v1/devices/{id}/state` 汇报播放状态；
  我们从未发过。抓包见 `SpotifyApi/tmp/web_license_capture.log`。许可证服务器可能据此判断「真实播放」，缺失时按异常限流
- 每首歌 HLS.js 开 3 个密钥会话 × 重试，约 9 次 license 请求（网页版 1 次）：需改为每首只申请一次、429 不重试不跳歌

## 其他待办 / 优化

- [ ] 新的音频解密方法（研究中）：按上文「新解密方法接入」实现 `DecryptSpec`
- [ ] 补完并跑通 ⑧ 的回归测试后提交：`sidebar_bottom_inset_test.dart` 两条仍失败（测试搭建问题：
      左栏找不到 ListView、右栏取 `ShellLayoutController` 抛 ProviderNotFound）；另补封面点击切换右栏的测试
- [ ] 实测：Web 登录一条龙是否自动完成；sp_dc 到手后 DRM 曲目整曲能否出声
- [ ] 主页播客 / 单集：目前只展示，点按提示暂不支持
- [ ] 登录页的中文文案迁入 ARB（账号卡片已完成）
- [ ] 外观设置跨设备同步（目前仅本机）；沉浸式歌词支持逐字歌词（需 color-lyrics 的 syllable 数据）
- [ ] Connect：本机作为可被遥控的播放端（需要实现 Connect 播放端协议）
