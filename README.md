# Flutify 🎵 - Spotify-Style Music Player (Google Material 3 Expressive)

Flutify 是一个采用 **Google Material 3 Expressive (MD3E)** 设计语言打造的高保真 Spotify 风格在线音乐播放器。专为**逆向 Spotify 移动端/桌面端协议与 API** 而设计，提供完整解耦的 API 数据层、设备控制、歌词同步、播放队列管理及内置逆向工程测试调试器。

---

## 🌟 核心设计与特性

### 1. Google Material 3 Expressive (MD3E) 设计语言
* **富有张力的表面色阶 (Tonal Surface Hierarchy)**：采用 MD3E 深层色阶（`surfaceContainerLowest` 到 `surfaceContainerHighest`），搭配 Spotify 标志性高饱和度极光绿（`#1ED760`）与动感曲风渐变。
* **极具表现力的对比形态 (Expressive Shapes & Radii)**：
  - 胶囊药丸（Stadium Pill / 999dp）：用于分类过滤器、顶部药丸、播放按钮和搜索栏。
  - 宽圆角容器（24dp ~ 28dp）：用于流派卡片、专辑卡片及模态底栏。
* **MiSans 中英文统一字体 (Expressive Typography)**：内置小米 MiSans（400 / 500 / 600 / 700 四档字重，全量中日韩字形），中文放宽行高、取消负字距，大字重标题与正文同样清晰；不再运行时拉取网络字体。
* **简体中文界面**：全部界面文案、系统组件（日期选择、文本选择菜单、Tooltip）均为简体中文，数量按中文习惯显示（12 首歌曲、1.2 万 位粉丝、1 小时 23 分钟）。
* **动感反馈与波形动效**：正在播放的曲目带有实时跃动的均衡器波形动画（Waveform Visualizer）。

### 2. 全面适配 Spotify 核心业务与交互
* **主页 (Home)**：
  - 动态问候语（早上好 / 下午好 / 晚上好）与个人头像。
  - 顶部快速过滤（全部 / 音乐 / 播客）。
  - Spotify 经典 2列x3行 近期播放快捷卡片（含 "Liked Songs" 渐变爱心卡片）。
  - 横向滚动专辑与歌单卡架（"Made For You"、"Popular Releases"、圆形艺人头像卡架）。
* **搜索与浏览 (Search & Browse)**：
  - 实时歌曲、艺人、歌单多类型搜索。
  - Spotify 经典 45° 倾斜封面的彩色流派分类卡（Pop、Hip-Hop、Rock、Dance、Chill 等）。
* **音乐库 (Your Library)**：
  - 置顶 "Liked Songs" 收藏歌单。
  - 标签式分类过滤（歌单 / 艺人 / 专辑 / 已下载）。
  - 排序及列表/网格视图切换。
  - 新建歌单快捷弹窗。
* **播放器系统 (Player Experience)**：
  - **Mini Player (常驻底部悬浮条)**：悬浮在底部导航栏上方，实时展示专辑封面、歌名、艺人、设备状态、爱心收藏与播放/暂停控制，底部自带精确进度线。
  - **Full Screen Player (全屏播放器)**：下拉手势抽屉、动态氛围背景渐变、高清圆角大封面、高灵敏度滑动进度条（Scrubber）、随机/单曲/列表循环三态切换。
  - **Spotify Connect 设备切换**：支持检测并切换播放设备（PC / 手机 / 音箱）。
  - **实时同步歌词 (Synced Lyrics)**：Apple Music iOS 风格——流动封面背景（`LiquidArtworkBackground`）、顶部信息胶囊与底部控制台采用液态玻璃（`LiquidGlass`），当前行清晰、上下句按行距逐级模糊变暗；手动滚动时全部变清晰，停手 3 秒后自动回到当前行；点击任意行跳转。
  - **播放队列管理器 (Queue)**：与 Spotify 一致的双层队列——"Next in queue"（用户手动添加，优先播放）+ "Next from: 上下文"，两段均支持拖拽排序、滑动删除、点击跳播、一键清空。
  - **播放上下文 (Playback Context)**：记录"正在从哪个歌单 / 专辑 / 艺人 / 搜索播放"，全屏播放器顶部显示「正在播放歌单」等，详情页播放键可在"播放整个上下文 / 暂停 / 继续"间切换。
  - **真随机与循环**：随机模式基于打乱的播放顺序表，切换时以当前曲目为起点重建；列表循环在末尾回绕，单曲循环重播。
* **详情页**：歌单（本地歌单可删除 / 滑动移除曲目）、专辑（发行信息、"More by"）、艺人（关注、热门曲目、唱片目录），均以封面主色生成渐变头部。
* **曲目菜单**：长按任意曲目 → 收藏、加入歌单、加入队列、前往专辑 / 艺人、复制分享链接。
* **桌面端快捷键**：Space 播放/暂停、Ctrl+←/→ 切歌、Ctrl+↑/↓ 音量、Ctrl+S 随机、Ctrl+R 循环。

---

## ⚡ 性能架构

* **播放进度独立通知**：`PlaybackProvider.positionNotifier`（`ValueNotifier<Duration>`）单独承载高频进度，只有进度条 / 歌词监听它；`notifyListeners` 仅在曲目、播放状态、队列等离散变化时触发。
* **精确订阅**：组件通过 `context.select` 订阅所需字段；`LibraryProvider` 采用写时复制列表，保证 `select` 比较稳定。
* **图片解码降采样**：`CoverImage` 按显示尺寸 × DPR 设置 `memCacheWidth`，避免大图全尺寸解码。
* **歌词**：二分查找当前行，仅在行切换时重建；用户手动滚动后暂停自动滚动 3 秒。
* **搜索**：300ms 防抖 + 请求代次号，丢弃过期结果；歌词与封面取色均带缓存与并发合并。
* **防红屏**：`core/utils/error_placeholder.dart` 替换全局 `ErrorWidget`，单个组件构建失败只显示低调占位块；所有"无内容"区域统一使用 `EmptyState`，加载中使用 `skeleton.dart` 骨架屏。
* **嵌套导航**：每个 Tab 拥有独立 `Navigator`（`ui/navigation/tab_navigator.dart`），详情页不覆盖迷你播放器，切 Tab 保留页面栈。

---

## 🛠️ 为 Spotify 逆向工程深度适配

本项目的架构与 Spotify 官方数据模型及内部协议深度对齐：

| 模块 | 路径 | 逆向对接说明 |
| :--- | :--- | :--- |
| **API 路由注册表** | `lib/core/constants/spotify_endpoints.dart` | 包含所有 Spotify Web API 及 SpClient 内部端点（`/me`, `/me/player`, `/browse/*`, `/color-lyrics/*`） |
| **数据模型层** | `lib/models/` | `SpotifyTrack`, `SpotifyAlbum`, `SpotifyArtist`, `SpotifyPlaylist`, `SpotifyLyrics`, `SpotifyDevice` 均严格遵循 Spotify JSON 字段结构 |
| **API 服务层** | `lib/services/spotify_api_service.dart` | 支持带 `Bearer Token` 的网络请求，支持配置自定义代理或逆向服务，在未连接 Token 时无缝降级至全功能本地 Mock 数据 |
| **协议登录** | `lib/services/auth/` | **桌面版 OAuth（默认）**：与官方桌面版相同的 client_id，系统浏览器打开 accounts.spotify.com 登录，本机回环 `127.0.0.1:8898/login` 接收授权码，PKCE 换令牌、refresh_token 续期，并以 Windows 桌面身份申请 `client-token`；**Login5**：密码（自动 Hashcash + 短信验证码，可重新发送）、手机号短信、登录链接 / 一次性令牌、导入 StoredCredential；**开发者应用 OAuth**：自己的 Client ID。会话的 client_id、client-token 平台数据、User-Agent 与 `app-platform` 请求头始终来自同一种客户端身份（`client_profile.dart`）；登出调用 `/api/logout/v1` |
| **桌面端数据层** | `lib/services/pathfinder/` | 桌面版 OAuth 会话下，公开 Web API（api.spotify.com）会因共享 client_id 频繁 429，因此改走官方桌面端自己的内部接口：Pathfinder GraphQL（`api-partner.spotify.com/pathfinder/v2/query`，持久化查询 hash 取自本机 `xpui.spa` 1.3.1.234）负责主页、分类、搜索、专辑、艺人、唱片目录与曲目补全；spclient `playlist/v2` 负责歌单、`user-profile-view/v3` 负责昵称头像。其余登录方式仍走 Web API |
| **逆向调试中心** | `lib/ui/screens/settings/settings_screen.dart` | **内置 API 调试控制台**：可在 App 内直接输入并测试任何逆向提取的 API 路径（如 `/me`, `/me/player`），实时查看 HTTP 状态码、延迟及响应 JSON |

---

## 📂 代码目录结构

```
d:/Flutify/app/
├── lib/
│   ├── core/
│   │   ├── constants/
│   │   │   ├── mock_spotify_data.dart    # 真实可播放音频测试流、样本歌单与歌词
│   │   │   └── spotify_endpoints.dart    # Spotify 官方/SpClient 端点表
│   │   ├── theme/
│   │   │   ├── md3e_colors.dart          # MD3E 表面色阶与 Spotify 调色盘
│   │   │   ├── md3e_shapes.dart          # MD3E 胶囊与多级圆角规范
│   │   │   ├── md3e_typography.dart      # MiSans 字体规范（字重、中文行高与字距）
│   │   │   └── md3e_theme.dart           # ThemeData (useMaterial3: true)
│   │   └── utils/
│   │       ├── formatters.dart           # 时长、万/亿紧凑数字、发行日期、问候语（经 l10n 本地化）
│   │       └── artwork_palette.dart      # 封面主色提取（带缓存）
│   ├── l10n/                             # 界面文案（gen-l10n，配置见 l10n.yaml）
│   │   ├── app_zh.arb                    # 简体中文模板（新增文案先写这里）
│   │   ├── app_en.arb                    # 英文备用翻译，与模板保持同步
│   │   ├── app_localizations*.dart       # 自动生成，勿手改
│   │   ├── l10n.dart                     # context.l10n 扩展
│   │   ├── app_locale.dart               # 固定 zh_CN + Global*Localizations 代理
│   │   └── model_labels.dart             # 专辑类型、播放来源等模型字段 → 界面文案
│   ├── models/                           # Spotify 对应的数据模型
│   │   ├── track.dart, album.dart, artist.dart
│   │   ├── playlist.dart, lyrics.dart, device.dart
│   │   ├── playback_context.dart         # 播放上下文（歌单 / 专辑 / 艺人 / 搜索）
│   │   └── user_profile.dart, playback_state.dart
│   ├── services/
│   │   ├── auth/                         # Spotify 协议登录（对应 SpotifyApi/api-docs/01-认证与账号）
│   │   │   ├── spotify_auth_service.dart # 登录总控：全部登录方式、令牌持久化与并发合并续期、登出
│   │   │   ├── login5_service.dart       # Login5 v3：密码/手机号/一次性令牌/StoredCredential，挑战轮次
│   │   │   ├── oauth_pkce_service.dart   # OAuth 授权码 + PKCE（accounts.spotify.com）
│   │   │   ├── oauth_client_config.dart  # OAuth 客户端配置：桌面版（/login）/ 开发者应用（/callback）
│   │   │   ├── oauth_loopback_server.dart# 127.0.0.1:8898 回环接收授权回调
│   │   │   ├── client_profile.dart       # 客户端身份（Android / Windows 桌面）：UA、平台头、client-token 平台数据
│   │   │   ├── account_profile_service.dart # identity/v3 与 /v1/me 昵称头像
│   │   │   ├── credential_parsers.dart   # credentials.json / Base64 / 登录链接解析
│   │   │   ├── client_token_service.dart # clienttoken.spotify.com 设备令牌申请
│   │   │   ├── hashcash.dart             # 工作量证明求解（后台 Isolate）
│   │   │   ├── proto_codec.dart          # 无代码生成的极简 protobuf 编解码
│   │   │   └── auth_constants.dart       # client_id / 版本 / 设备伪装 / 错误码
│   │   ├── pathfinder/                   # 桌面端内部接口数据层（桌面版 OAuth 会话使用）
│   │   │   ├── pathfinder_operations.dart# 持久化查询名 + sha256 hash（随桌面版升级需重新提取）
│   │   │   ├── pathfinder_client.dart    # GraphQL v2 请求与错误处理
│   │   │   ├── pathfinder_parsers.dart   # 响应 → App 数据模型（宽松解析、解包 Wrapper）
│   │   │   └── desktop_data_source.dart  # 页面级数据：主页/分类/搜索/专辑/艺人/歌单，5 分钟查询缓存
│   │   ├── audio_player_service.dart     # 基于 just_audio 的实时音频流控制
│   │   ├── spotify_api_service.dart      # HTTP API 请求与 Mock 降级
│   │   └── storage_service.dart          # SharedPreferences 本地凭证持久化
│   ├── providers/
│   │   ├── auth_provider.dart            # 登录态：表单 → 验证码 → 已登录，错误中文化
│   │   ├── playback_provider.dart        # 播放状态、上下文、双层队列、随机/循环、音量
│   │   ├── library_provider.dart         # 收藏歌曲、歌单、关注艺人、收藏专辑（持久化）
│   │   ├── spotify_provider.dart         # 主页数据、防抖搜索、搜索历史、歌词缓存、设备
│   │   └── settings_provider.dart        # 逆向凭据与 API 测试调试器
│   ├── ui/
│   │   ├── navigation/                   # Tab 内嵌 Navigator 与统一跳转 AppRoutes
│   │   ├── screens/
│   │   │   ├── main_shell.dart           # 响应式主框架 (移动端底部栏 / 桌面端侧边栏)
│   │   │   ├── home/home_screen.dart     # Spotify 风格主页
│   │   │   ├── search/search_screen.dart # 搜索与倾斜封面流派卡片
│   │   │   ├── library/library_screen.dart# 媒体库与已点赞歌曲
│   │   │   ├── detail/                   # 歌单、专辑、艺人详情页
│   │   │   ├── player/                   # 全屏播放器、歌词抽屉、队列与设备列表
│   │   │   ├── auth/                     # 登录页外壳 login_screen.dart + stages/（浏览器登录[默认]、密码、手机号、
│   │   │   │                             #   链接、导入凭据、开发者应用授权、验证码）+ widgets/（品牌标、授权等待页等）
│   │   │   └── settings/settings_screen.dart # 账号卡片（登录/刷新令牌/退出）+ 逆向工程 API 调试中心
│   │   └── widgets/                      # MiniPlayer、TrackTile、CoverImage、PlaybackScrubber、
│   │                                     # PlayerControls、TrackOptionsSheet、CreatePlaylistDialog 等
│   └── main.dart
├── assets/fonts/MiSans/                  # MiSans Regular / Medium / Demibold / Bold（TTF）
├── l10n.yaml                             # gen-l10n 配置（模板 app_zh.arb）
└── test/                                 # Provider 单元测试 + 移动/桌面 UI 流程测试
```

---

## 🌐 语言与字体

### 简体中文界面（gen-l10n）
* `MaterialApp` 固定 `locale: zh_CN`（`lib/l10n/app_locale.dart`），并注册 `GlobalMaterialLocalizations` / `GlobalCupertinoLocalizations` / `GlobalWidgetsLocalizations`，系统组件同样显示中文。
* 组件内统一使用 `context.l10n.xxx`（`import 'package:flutify_app/l10n/l10n.dart'` 或相对路径）；模型字段到文案的映射（专辑 / 单曲 / 合辑、「正在播放歌单」）放在 `l10n/model_labels.dart`，模型层不含界面语言。
* 服务层 / Provider 不依赖 `BuildContext`，其错误信息在 UI 层转换后再展示。登录页（`ui/screens/auth/`）与账号卡片的文案为直接书写的中文，尚未迁入 ARB。
* 用词参照 Spotify 中文版：主页 / 搜索 / 音乐库 / 已点赞的歌曲 / 正在播放 / 播放队列 / 歌词 / 随机播放 / 单曲循环 / 添加到歌单 / 关注。

**新增一条文案：**
1. 在 `lib/l10n/app_zh.arb` 添加键值（带占位符时写 `@键名.placeholders`，数量用 ICU `plural`，如 `"songCount": "{count, plural, other{{count} 首歌曲}}"`）；
2. 在 `lib/l10n/app_en.arb` 添加同名英文；
3. 运行 `flutter pub get`（或直接 `flutter run` / `flutter gen-l10n`）重新生成 `app_localizations*.dart`；
4. 代码中使用 `context.l10n.键名`。

### MiSans 字体
* 来源：小米官方字体包（[hyperos.mi.com/font](https://hyperos.mi.com/font/)，`MiSans.zip` 中的全量 TTF），放在 `assets/fonts/MiSans/`，于 `pubspec.yaml` 注册为 `MiSans` 字族并设为 `ThemeData.fontFamily`。
* 字重映射：Regular 400、Medium 500、Demibold 600、Bold 700（每档约 7.5 MB，共约 30 MB）。代码中的 `w800` / `w900` 按字重匹配规则回落到 Bold——对中文标题而言比 MiSans Heavy 更通透。
* 排版：正文行高 1.5、标题约 1.3，`TextLeadingDistribution.even` 上下均分行距避免汉字被裁切；除展示级大字号外字距为 0（负字距会让汉字挤在一起）。
* **许可**：MiSans 由小米公司发布，依据《MiSans 字体知识产权许可协议》可免费用于个人与商业用途（含在软件中嵌入与分发）；不得对字体本身进行改编、二次开发或单独出售，字体版权归小米所有。完整协议以官网为准：<https://hyperos.mi.com/font/>。

---

## 🚀 运行与构建

使用本地 Flutter SDK (`D:\flutter-sdk\3.44.0\flutter\bin\flutter.bat`)：

### 1. 运行 Windows 桌面端
```powershell
cd d:\Flutify\app
& "D:\flutter-sdk\3.44.0\flutter\bin\flutter.bat" run -d windows
```

### 2. 运行 Android 端
```powershell
& "D:\flutter-sdk\3.44.0\flutter\bin\flutter.bat" run -d android
```

### 3. 登录 Spotify 账号
设置（主页头像 / 桌面端侧栏底部）→ 顶部账号卡片 →「登录」。登录成功后 App 自动切到真实数据，之后令牌过期会静默续期。

| 方式 | 入口 | 说明 |
| :--- | :--- | :--- |
| 在浏览器中登录 | 默认 | 桌面版 OAuth：打开官方登录页，完成后自动回到 App。人机验证、两步验证、Passkey、Google/Apple 等第三方登录均由官方页面处理；需要本机 8898 端口空闲 |
| 账号密码 | 「账号密码」 | Login5：自动完成 client-token 与 Hashcash；需要时进入短信验证码页（60 秒后可重新发送） |
| 手机号 | 更多方式 | 选择地区 → 获取短信验证码 |
| 登录链接 | 更多方式 | 粘贴 Spotify 邮件中的登录链接或一次性令牌 |
| 导入凭据 | 更多方式 | librespot `credentials.json`，或用户名 + Base64 凭据（+ 原设备 ID） |
| 开发者应用授权 | 更多方式 | 在 developer.spotify.com 创建应用，登记 Redirect URI `http://127.0.0.1:8898/callback`，填入 Client ID；仅公开 Web API |

**降低风控的做法**（均已实现）：默认走与官方桌面版相同的浏览器授权，App 不接触密码、不做 Hashcash；
会话内 client_id、client-token 平台数据（`desktop_windows`）、User-Agent、`app-platform` / `spotify-app-version`
来自同一客户端身份，避免"桌面令牌 + 安卓设备"的混搭特征；令牌只在临近过期时续期，并发续期合并为一次请求；device_id 固定不变。

桌面版 OAuth 登录后，数据走桌面端内部接口（见上表「桌面端数据层」）。暂不支持：Spotify Connect 设备列表（桌面端走 dealer / connect-state，列表为空）。
桌面客户端升级后若出现 `PersistedQueryNotFound`，可用 `tool/pathfinder_probe.dart` 探测并从新的 `xpui.spa` 重新提取 hash。

未实现：魔法链接的发送请求（可用「登录链接」代替）、Login5 下的 reCAPTCHA 挑战（会提示改用浏览器登录）、家庭儿童账号切换。
> 以官方客户端身份登录（桌面版 OAuth / Login5）均违反 Spotify 服务条款，仍存在风控可能，建议使用测试账号；其中 Login5 密码登录风险最高。

### 4. 代码分析与自动化测试
```powershell
& "D:\flutter-sdk\3.44.0\flutter\bin\flutter.bat" analyze
& "D:\flutter-sdk\3.44.0\flutter\bin\flutter.bat" test
```
