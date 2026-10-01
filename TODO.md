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

## 其他待办 / 优化

- [ ] 主页「最近播放」：目前快捷网格是媒体库前 7 个歌单，可改为真实播放历史（`recently-played` / 本机记录）
- [ ] 音乐库「按字母顺序」改为按拼音排序（左栏 `library_sidebar_entry.dart` 与移动端 `library_screen.dart` 两处）
- [ ] 登录页的中文文案迁入 ARB（账号卡片已完成）
- [ ] 外观设置跨设备同步（目前仅本机）；沉浸式歌词支持逐字歌词（需 color-lyrics 的 syllable 数据）
- [ ] 主页按官方分区显示（带分区标题）
- [ ] Spotify Connect 设备列表（dealer / connect-state）
- [ ] 桌面客户端升级后 Pathfinder hash 失效检测与提示
