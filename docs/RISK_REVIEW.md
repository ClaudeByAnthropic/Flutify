# Flutify 与 ProxyServer 风险及功能审查

核对日期：2026-10-04，2026-10-05 增补并修正。范围为本地 `app`、相邻 `ProxyServer` 和 `SpotifyApi` 协议资料；以当前代码、自动化测试及本机 TLS ClientHello 对照为依据，没有进行真实账号封禁因果实验。2026-10-05 先复核了 AP 登录身份、playplay 常量、spclient 区域主机与身份组合，随后修正应用专用协议标识、AP 版本、播放端区域路由及 Web client-token 缓存边界，并落实账号请求 401 后的本地会话与 WebView Cookie 清理。TLS 传输栈替换尚未完成，不能把身份字段统一称为指纹已对齐。

## 结论

没有证据能由当前源码推导出“必然封号”或“不会封号”。内部接口、官方客户端标识复用和独立实现的播放协议存在兼容性与账号策略风险；Spotify 的服务端判定规则不可见。网关出口、TLS 实现及不同链路的地理位置是可观察的差异，但不能直接当作已证实的封禁原因。

此次完成了真实播放状态、设备 ID、音频格式、播客、歌词译文、UTF-8 和启动行为方面的修正，并新增首页刷新、日语 / 繁体界面、广告跳过和 Windows x64 原生 DRM 实验管线。没有通过伪造收听、补造遥测或模拟设备认证来掩盖差异。修正的目标是减少错误请求、错误状态与不必要流量，不能承诺消除账号风险。

## 1. ProxyServer：边界与证据

| 检查项 | 当前行为及代码依据 | 结论 / 剩余条件 |
| --- | --- | --- |
| 网关凭据 | `server.js` 的 `AUTH_STRIP_HEADERS` 清除网关认证、自定义会话及代理认证头 | 网关凭据不会作为普通 HTTP 上游头透传；网关自身仍需妥善保管配置 |
| 请求头 | `lib/security.js` 清理 hop-by-hop 头、`Connection` 指名头及 Forwarded / X-Forwarded / 客户端 IP 头 | 没有把本机 IP 作为此类 HTTP 头主动交给上游；不代表整个链路匿名 |
| 上游主机与 TLS | HTTP 上游恢复目标 Host；TLS 使用目标 SNI，默认证书校验开启，`lib/egress.js` 同样校验加密出口代理 | 关闭校验的部署配置会改变结论，需保持默认验证行为 |
| 数据转发 | `server.js` 流式转发响应，未发现账号 API 响应缓存 | 不因网关缓存把一个账号的响应复用给另一账号；网关进程仍能看到明文 HTTP 内容 |
| 中断与 WebSocket | `server.js` / `lib/ws-stream.js` 处理连接取消、帧校验、消息大小及背压 | 自动化测试覆盖相应边界；不等于完成生产压力测试 |
| 白名单 | `lib/geosite.js` 与配置限制目标；App 端另有 Spotify / CDN 和精确 Widevine 主机路由 | 不能把网关当成无限制开放代理；新增允许主机应有具体业务依据 |
| 日志 | 默认 `logLevel: warn` | 未把真实账号探测输出纳入报告；部署方仍应避免额外记录 Cookie、Authorization 或完整敏感响应 |

**信任边界：** 此 HTTPS 网关终止客户端 TLS，再向目标建立连接；因此运营网关的人或被入侵的网关可读取通过它传输的 Spotify bearer、Cookie 与响应。传输加密不能消除这项信任。外部出口代理、域名、证书和运行环境仍由部署方控制。

**可观察差异：** HTTPS 上游由 Node TLS 栈建立，可能不同于浏览器 / 官方客户端；共享出口可能关联多个用户；浏览器登录与 API / 音频分流可能出现不同出口。这些是合理的风险假设，当前没有封禁样本、对照实验或官方判定依据支持量化概率。

本轮未改写 ProxyServer 的传输实现。普通 HTTP CONNECT 代理保留隧道内客户端发出的 TLS 握手；本项目 HTTPS 反向网关则重新建立 Node TLS 上游连接，两者不能混为一谈。

## 2. App 网络、认证与协议

| 项目 | 当前证据 | 评估 |
| --- | --- | --- |
| 网关路由 | `services/network/spotify_gateway.dart`、`gateway_http_client.dart` | 限定 Spotify / CDN 和特定 Widevine 请求；外部播客走正常网络路由，不把任意站点引入网关 |
| 重定向 | `gateway_http_client.dart` 与网络测试 | 跨源重定向剥离凭据，拒绝 HTTPS 降级；外部音频请求不附带 Spotify 认证头 |
| 桌面 OAuth | `services/auth/`：浏览器授权、回环回调、PKCE、令牌刷新 | OAuth 链路已有刷新合并等保护；这不等于获得复用官方客户端标识的服务端授权 |
| 数据层身份 | `auth/client_profile.dart`、`auth_constants.dart` | Windows 桌面版本常量为 1.3.1.234；非 Windows 平台仍使用 Windows 19045 回退及 x64 字段，是明确存在的实现差异 |
| Web 播放身份 | `connect/receiver/track_playback_api.dart` | track-playback 另用 Web 会话、Web client-token、1.3.5.31 及 Windows / Chrome 154 常量，不能声称整应用只有一种身份 |
| Web client-token | `track_playback_api.dart` 的缓存和 `invalidate()` | 保留并发申请合并；下次使用时按 refresh / expires 中较早的期限提前刷新，短 TTL 同样生效，缺少 TTL 时只短期缓存。失效操作递增代次，迟到的旧响应不能覆盖新令牌；HTTP 失败不缓存。不是后台定时刷新 |
| 内部 API | Pathfinder 持久化查询、spclient、dealer、track-playback | 查询 hash、字段和许可证策略可随服务端升级失效，需保留明确错误与可恢复路径 |
| AP 登录身份 | `auth/client_profile.dart`、`protocol/ap_login_request.dart` | 已省略可选的 system_information_string，不再发送 `flutify-protocol`；version_string 使用桌面配置版本，ClientHello 数字版本由旧的 124200290 改为同源的 130100234。CPU / OS 与所声明的 Windows x64 配置一致。登录包在 DH / Shannon 通道内发送，对服务端可见，并非网络明文；尚未验证服务端是否接受此次字段调整 |
| Connect 应用标识 | `connect_service.dart`、`receiver/connect_receiver.dart` | 播放命令不再填写应用专用 feature_identifier；默认设备名为 `Web Player`，用户自定义名称仍原样保留。这只去掉自动添加的应用标识，不隐藏账号或伪造收听 / 设备认证 |
| 音频密钥常量 | `services/protocol/playplay_key.dart` 的 REQK 为桌面版 `Spotify.dll` 硬编码常量的复用（文件偏移见注释）；当前 `lib/`、`test/` 未发现 `fetchPlayplayKey` 调用者 | 属逆向协议实现，不能描述为当前主播放流程正在使用；若重新接入，需验证常量及服务端兼容性 |
| spclient 区域主机 | Connect 播放端已使用同一 dealer 会话通过 apresolve 发现的 spclient；发现失败仍沿用已有默认地址。未接入主流程的 `playplay_key.dart` 仍固定 `gae2-spclient.spotify.com`，`license_client.dart` 另有 4 主机回退表 | 接收端注册及状态请求随已有发现结果选路，不新增发现请求；许可证只在连接层失败时尝试其他入口，HTTP 403 不切区重试。playplay 如重新接入需处理区域发现；主机名称本身不能证明账号与出口区域不匹配 |
| 身份组合与传输指纹 | 桌面 OAuth / AP 使用 `sp_device_id`；Connect Web 播放端使用独立持久化的 `connect_receiver_device_id`。桌面 1.3.1.234 与 Web 1.3.5.31 / Chrome 154 / harmony 4.62.0 仍是两套配置 | 不能称为同一 device_id 同时呈现三种身份，也不能把桌面 UA 说成 Chrome UA。两条链路令牌用途不同，不能仅靠改版本字符串合并；跨平台声明及 Dart / Node 的 TLS 差异仍在，详见下节 |
| 本地数据 | `StorageService`、播放缓存、探测工具 | 未开展操作系统级凭据存储审计；会话文件与 `tool/probe_out/` 应作为敏感本地数据，不应进入仓库或报告 |

`SpotifyApi/tmp/web-player.js` 用作官方 Web 客户端实现对照。其中歌词 `clientLanguage` 支持 `all`，`alternatives` 包含语言与按原词索引对应的字符串数组。本轮据此接入源译文，而非假设存在通用翻译 API。

### 2.1 TLS 对照与尚未完成的传输改造

2026-10-05 在 `127.0.0.1` 监听原始 ClientHello，比较 Dart `SecureSocket`、与网关上游同配置的 Node `tls.connect` 及本机 Chrome。三者均使用相同测试 SNI；Chrome 使用临时配置目录。探针不请求 Spotify、不加载账号凭据、不发送许可证，也不关闭生产证书校验。已排除 GREASE 值，以下是此次新连接的结果：

| 发起端 | 密码套件数量 | 扩展数量 | ALPN | supported_groups |
| --- | --- | --- | --- | --- |
| Dart | 17 | 10 | 未声明 | 29、23、24 |
| Node | 52 | 11 | 未声明 | 4588、29、23、30、24、25、256、257 |
| Chrome | 15 | 17 | h2、http/1.1 | 4588、29、23、24 |

套件、签名算法及扩展还存在内容和顺序差异；Chrome 扩展顺序可能随连接变化，不能要求每次原始字节完全相同。该结果确认了本机默认栈的差异，不是线上部署的抓包，也不是 Spotify 桌面客户端的指纹基线，更没有验证 HTTP/2 SETTINGS 或会话恢复行为。可复现探针已纳入仓库：[`tool/network/tls_client_hello.py`](../tool/network/tls_client_hello.py)，运行方式见 [`tool/network/README.md`](../tool/network/README.md)。最新运行日志为工作区 `D:/Flutify/risk-tls-probe.log`，结果默认保存在已忽略的 `tool/probe_out/tls/result.json`。

**TLS 尚未对齐。** Dart 的公开 `SecureSocket` API 不能完整配置 Chrome 的 ClientHello；当前 Dart / Node HTTP 实现也不能只在 ALPN 中加入 h2 就开始使用 HTTP/2。要实际对齐，需要在明确目标客户端版本后替换并验证 TLS / HTTP 传输实现；直连、CONNECT、WebSocket、流式媒体与网关上游必须分别覆盖。单改 Node 的 ciphers / UA 或 App 的请求头不构成完成。WebView 使用浏览器网络栈也不会自动改变其他 Dart 请求或 Node 网关上游。

AP 使用 DH / Shannon，不属于 TLS 链路。已有 Widevine 对照工具中，Chrome 生成的 challenge 经本机回调交给同一个 Dart `SpotifyLicenseClient` 发往服务端，独立 CDM 也使用该客户端。Chrome challenge 成功而独立 challenge 403，不能用“一个是 Chrome TLS、一个是 Dart TLS”解释；许可证内容 / 宿主兼容性仍需单独调查。本次没有重复真实许可证请求。

此处的自动移除范围是发给 Spotify 的协议专用标识；GitHub 更新请求、歌词供应商 User-Agent、本地 IPC 名称和应用界面名称仍保留对应标识，用户自定义设备名也不被改写。

## 3. 已完成的协议与播放修正

### 3.1 Connect 播放状态

- 新增 `AudioPlaybackInfo`，把实际选择的码率与格式传入播放端状态；无法确定时不填伪造的固定值。
- 播放端设备 ID 改为本地持久化随机 40 位十六进制值，不再从计算机名散列得出。存储保留时保持稳定，清除应用数据后会重新生成。
- `ListeningProgress` 根据递增播放位置和单调时钟累计实际收听，单次增量受真实经过时间限制；跳转、暂停和缓冲不计入正常累计，达到 30 秒才触发一次对应上报。它是保守计数器，不能把进度条跳到 30 秒当成听满 30 秒。
- 注册播放能力时包含外部播客格式。保留现有观察端和本机播放端，纠正旧报告中“没有任何上报”“只有隐藏观察者”的描述。

依据：`services/connect/receiver/`、`models/audio_playback_info.dart`、`providers/playback_provider.dart`；测试在 `test/connect/`。

按用户要求，本机 Connect 播放端识别 `is_advertisement`（布尔值或字符串 `true`）和 `spotify:ad:` URI，在任何加载或展示之前沿状态机跳过广告，待播列表也过滤广告。跳过后使用真实歌曲的状态下标，从零开始并保留暂停状态；自动下一首和上一首会跨过广告映射回服务端状态。不按曲名或时长猜广告，不汇报广告已收听。全广告 / 循环链没有可播放后继时取消旧加载并清空接收端状态，等待新命令；服务端是否接受跨广告状态跳转仍需真实账号验证。这一实现作用于 Flutify 本机播放端，不控制其他应用自身的音频输出。

### 3.2 播客与缓存

- 保留单集 `spotify:episode:` 类型，解析外部 URL / MP3，并保留 MP4 受保护播放回退；外部音频无需先启动 Web DRM 登录链路。
- `http_range_audio.dart` 先探测 HTTPS 资源，再按播放器 Range 按需读取。检查长度、MIME、Content-Range 与截断，处理服务端忽略 Range 的情况；不向外部主机传递 Spotify 认证。
- 完整保存使用临时 `.part` 文件与完成后改名，失败清理临时文件；缓存淘汰保护正在使用 / 加载的音频。
- 不自动预取长播客；歌曲加载并发由 4 降至 2，减少无效下载与资源争用。

限制：外部源必须给出可信总长度，无长度 chunked 源尚未接入；多种真实播客托管服务、长时播放及厂商播放器差异仍需实机验证。

依据：`protocol/eme_track_audio_source.dart`、`http_range_audio.dart`、`track_audio_loader.dart`；`test/protocol/podcast_playback_test.dart`、`http_range_audio_test.dart`。

### 3.3 字符编码

播放媒体、track-playback 和账号资料 JSON 由响应原始字节按 UTF-8 解码，避免响应没有 charset 时把中文、日文或 emoji 当作单字节编码解析。相关测试使用无 charset 响应，验证文本保持正确；不会擅自二次转换本来就正确的曲名。

## 4. 歌词、Canvas 与启动

### 4.1 歌词源提供的翻译

- 请求 Spotify 歌词时带 `clientLanguage=all`，解析 `alternatives`，保留空行。译词数量不符合原词行数时不直接按索引拼接。
- 默认自动显示已有译文，并默认排除界面语言；允许增加排除语言、关闭自动显示及手动显示 / 取消。手动操作可以覆盖自动排除规则。
- 中文目标随界面：简体 `zh-Hans`，繁体 `zh-Hant`；识别 CN / SG / MY 与 TW / HK / MO 等标签别名。`zh` 排除两种中文，具体脚本只排除相应类型。没有私自将繁体歌词转换成简体译文，也没有单独新增译文简繁开关。
- Spotify 无合适译词时，在启用歌词补全的前提下查 LRCLIB 的其他语言 / 双语记录。LRCLIB 没有可靠统一的语言字段或专门翻译端点，所以不能把搜索到的任何外语词都当译文。
- LRCLIB 匹配曲名、艺人和已知时长（差值不超过 3 秒），时间戳容差 350 ms；双语记录至少有 3 行且覆盖 80% 原词，并校验原文锚点。纯译词要求已知艺人 / 时长、完整时间轴且没有额外歌词行。英文候选须有明确翻译标记，不以拉丁字母直接断言英文。
- 搜索和匹配忽略曲名里的 feat. / ft. / featuring 合作歌手标注，但保留 Live / remix 等版本信息；官方精确查询仍使用完整曲名。时间轴优先精确时间戳，日语译词允许个别行只有汉字，但整体仍必须识别为日语，不能把中文当日语。
- 保守匹配会漏掉部分合法译文，尤其是无同步时间、不同编辑版本或元数据不完整的记录；没有可靠结果时显示无此语言译文，保持原词可用。
- 查找带并发合并、短期候选缓存与过期结果保护；切歌、切换语言、修改偏好或取消后，旧请求不得覆盖当前视图。LRCLIB 译文注明来源。

没有 Google 翻译或其他机器翻译调用。简体、繁体、英文和日语界面资源已接入；日语界面优先匹配源提供的日语译词，默认跳过日语原词。部分历史硬编码中文文案的本地化仍未完成。

翻译按钮位于展开 / 全屏按钮左侧，歌词面板与按钮共享查询状态；未找到译文及网络错误都允许再次点击重试。切歌在帧结束后更新共享控制器，不在构建期间通知祖先组件，也不在新曲目中展示旧译文。任务栏歌词设置示例使用应用主题的明暗模式。

依据：`models/lyrics.dart`、`services/lyrics_service.dart`、`services/lyrics/`、`ui/screens/player/lyrics/`；`test/lyrics/lyrics_translation_test.dart`、`test/app_locale_test.dart`。

### 4.2 Spotify Canvas

通过 Pathfinder Canvas 查询取官方元数据，支持 HTTPS 直接 URL 的视频、循环视频、图片与 GIF。视频静音循环，遵循播放状态、页面生命周期与减弱动效设置；超时、无内容或错误时回到静态封面。保留原有封面形状与 MD3E 播放器布局。

单个媒体上限 12 MB，内存最多缓存 3 个；成功结果保存 10 分钟、失败 1 分钟，并合并同曲并发请求。媒体请求不附 Spotify 认证。只有 manifest / fileId 的 Canvas 尚未解析；WebView 渲染、真实视频格式与播放耗电没有实机结论。

依据：`services/canvas/canvas_service.dart`、`ui/screens/player/widgets/canvas_artwork.dart`；`test/canvas_service_test.dart`。

### 4.3 启动与 DRM

移除启动加载动画，成功后进入应用（默认主页；已有启动页偏好保留）；初始化失败或 60 秒超时显示原因。存储、网络、窗口及基础媒体服务仍需初始化，不能承诺零等待。

桌面 EME WebView 延迟到第一次 DRM 播放时启动，并恢复用户已设置的音量；初始化失败可以重试。Android 继续使用原有 Media3 原生 Widevine。Windows x64 已加入可选的独立 CDM 宿主、AAC CENC 解析、批量解密与内存音频播放管线，原生加载失败后本次运行回退 WebView。真实实验中证书请求 HTTP 200，许可证 HTTP 403，尚未验证实际原生出声。每次原生会话重新获取证书、重新发现浏览器安装及组件更新目录里的 CDM，不下载或分发 DLL。版本、复现方式和边界见 [WIDEVINE.md](WIDEVINE.md)。

依据：`main.dart`、`core/widgets/app_startup.dart`、`services/eme/eme_audio_engine.dart`、`eme_player.dart`；`test/app_startup_test.dart`、`test/eme_lazy_start_test.dart`。

### 4.4 首页刷新与日语

- 首页支持下拉刷新和顶部按钮，空列表也能下拉；保留当前筛选，仅刷新主页，并发请求合并。失败时保留旧内容并提示；迟到的旧筛选、旧初始化或旧刷新结果不得覆盖新结果。
- 主页查询直接重新联网，不再命中数据层五分钟缓存。浏览等实体缓存按语言区分，切换语言后不会复用另一语言的标题。
- 新增日语和繁体中文界面资源，保留简体中文和英文，支持手动选择、偏好持久化和跟随系统。Spotify 请求使用所选语言；语言选项已改为 Material 3 下拉菜单，并适配窄屏和大字号。

依据：`providers/spotify_provider.dart`、`services/pathfinder/desktop_data_source.dart`、`ui/screens/home/`、`l10n/app_ja.arb`、`ui/screens/settings/sections/language_section.dart`；`test/home_refresh_test.dart`、`desktop_home_refresh_test.dart`、`ui/home_refresh_test.dart`、`ui/settings_more_test.dart`。

### 4.5 Android 系统栏、交互与请求节制

- AppBar 显式按背景明暗设置系统栏图标，修复设置页浅色背景上的白色状态栏图标；设置内容保留侧边安全区，宽屏主界面也避开系统区域。设置页恢复平台滚动物理效果。
- 设置行采用至少 56 逻辑像素高度，修复水波纹承载层，并合并开关标题、状态与操作语义；应用字号与系统文字缩放组合，保留系统非线性缩放。
- LRCLIB、网易歌词和 Connect 状态查询收到 429 或带 `Retry-After` 的 503 后，共享各自客户端的冷却时间，后续候选查询也遵守冷却；支持秒数及 HTTP 日期。此保护未覆盖所有 Spotify API、接收端或许可证请求，不能称为全应用限流。
- Windows EME 只报告当前使用的 DRM 系统缺失，去掉无关的 FairPlay 不可用提示。原生媒体误选 CBCS、初始化数据来源和失败分类的修复见 [WIDEVINE.md](WIDEVINE.md)。
- Web token 与许可证失败分别使用 `WebTokenHttpException`、`LicenseHttpException` 保留 HTTP 状态及请求类型；Android 原生媒体错误不再根据字符串中出现 401 / 403 猜测登录失效，EME 仅在明确缺少登录态或账号认证路径返回 401 时提示重新登录。匿名应用证书、媒体 / CDN 请求失败和 403 不据此退出账号。
- **自动点击同意按用户确认保留，作为减少操作步骤的预期功能，不列为待删除问题。** 登录页跨平台固定 Windows Chrome User-Agent 是另一项兼容性问题，与是否自动同意分别评估。

按用户要求，新增账号请求 401 的完整本地清理：

- `SessionHttpClient` 识别携带当前账号 bearer / `sp_dc` 的 Spotify HTTPS 请求及 OAuth token 交换；响应为 401 时清除桌面 / Web token、刷新令牌、client-token、`sp_dc` 和账号展示信息，立即通知界面退出，并接入停止账号播放和 Connect 的既有回调。无需再请求远端 logout，也不把 401 当作封号证明。
- 清理应用 WebView 的全部 Cookie；Windows 使用与登录页 / EME 相同的自定义 WebView 环境。清理前停止并移除正在打开的登录 WebView，防止旧页面继续写回 Cookie；保留安装 ID、用户偏好和更新设置。
- 并发 401 合并清理；OAuth、令牌刷新、资料读取及登录页回调按会话代次丢弃迟到结果。旧响应不能恢复已退出的会话，也不能清除后来新登录的账号。
- Cookie 清理失败保留持久重试标记，在启动或重新登录前重试，并合并并发重试。首次显示登录 WebView 也必须等清理完成；失败时显示重试入口，避免重用残留 Cookie。
- 403、CDN / 第三方 401、匿名证书请求及不属于当前会话的凭据不触发账号清理。清理范围是应用保存的凭据和应用 WebView Cookie，不操作外部浏览器配置，也不删除整个 WebView / CDM 数据目录。

依据：`services/auth/session_http_client.dart`、`storage_service.dart`、`auth/spotify_auth_service.dart`、`auth/web_token_service.dart`、`auth/web_login_flow.dart`、`providers/auth_provider.dart`、`ui/screens/auth/web_login_screen.dart`、`services/eme/eme_player.dart` 与 `main.dart`。

仍需处理的审查项：

| 项目 | 现状与影响 |
| --- | --- |
| 凭据存储与备份 | `storage_service.dart` 将令牌、刷新令牌、`sp_dc` 和代理密码写入普通 SharedPreferences；受操作系统应用目录权限保护，但未使用系统凭据库，Android 清单也未配置相应备份排除 |
| 平板触控 | 宽屏布局仍复用桌面播放器中的 32 / 36 逻辑像素按钮，需要覆盖平板上至少 48 的触摸目标 |
| MD3E 组件 | 一些滑块仍使用旧式细轨道、圆形滑块；启用 `useMaterial3` 不等于所有组件已符合 MD3E |
| TLS 与原生 DRM | 生产 Dart / Node TLS 栈尚未替换或对齐；Windows 独立 Widevine 的许可证 403 仍未解决。独立诊断已调用真实自身宿主验证，能开启加密身份，但同令牌、同 Dart 客户端的 Chrome / 原生对照仍为 200 / 403；预加载系统 DXVA 及等待也未解决。自身有效签名及完整接入资料仍缺失，服务端具体拒绝原因未知 |
| 服务协议 | 内部接口、跨平台复用官方客户端身份、playplay 逆向常量与广告跳过仍有服务兼容性 / 策略风险；AP 自动附带的应用名已移除，但不代表通过官方宿主认证。保留用户要求的跳过功能，不伪造广告收听，也不据此推断具体封号概率 |

系统栏与交互有 widget 测试覆盖，尚无 Android 实机截图或本轮 APK：本机未安装 Android SDK，构建停在 SDK 检查。

## 5. 验证与未验证范围

**2026-10-05 0.07 与输出保护增量：** 版本 `0.0.7+7` 的 Windows x64 本地 Release 编译、21 个二进制的架构 / VC 运行库检查及便携 ZIP CRC 检查通过；Flutter 851 项通过、8 项跳过，Node 25 项通过。此版本包含歌词背景首次暂停后直接关闭的生命周期修正。后续透明宿主跟踪确认 CDM 调用了输出保护查询：原生返回失败，临时 Chrome trace 实测成功、两个掩码均为 0；尚不能证明此差异导致 403。真实 OPM 枚举和初始化成功，但普通 Windows 证书链检查未通过，需继续核对 OPM 专用信任规则；尚未完成认证查询，不能声称测得 HDCP 状态。该批次未发送许可证、伪报输出状态或修改系统信任库。详细条件与证据见 [WIDEVINE.md](WIDEVINE.md)。以下构建记录属于各自历史批次。

**2026-10-05 自身宿主验证增量：** 新增 `tool/cdm/native_host_verification_probe.cpp`，在 CDM 初始化前提交实际探针 EXE、实际加载的 CDM 及相邻签名。CDM 签名可读、自身宿主签名缺失，接口仍返回接受异步处理，并生成加密身份；这纠正了“缺少自身签名便不能开启隐私模式”的推断，不能据接口返回值声称认证通过。83 B PSSH 的本地请求为 **3,682 B / 身份密文 3,104 B**，证书匹配；换用新令牌与 87 B HLS PSSH，**3,686 B** 请求仍为 **403 / 0 B**。

随后“仅验证、等待 5 秒、预加载系统 DXVA、预加载并等待”四组本地诊断全部通过，可观察请求特征未变，该四组未发送许可证。最终用“预加载并等待”配置做同一新非匿名 Web 令牌、证书、HLS PSSH、Dart HTTP 客户端及代理的 Chrome / 原生对照，仍是 **Chrome 200 / EME usable，独立宿主 403 / 空正文**。本增量共三次真实许可证请求（单独原生一次，最终对照两次），不同于下述历史纯本地批次的零请求。VMP 位于加密身份内，未观察其具体内容；自身签名仍缺失，不能断言它是唯一拒绝原因。探针 `/W4 /WX` 构建及定向 Dart 分析通过，真实许可证测试因 403 失败；未修改生产宿主或持久化用户会话。证据：工作区 `self-host-license-check.log`、`self-host-license-dxva2-settled-check.log`、对应回调日志、`self-host-verification-*-metadata.log`、`self-host-probe-analyze.log`。复现和结论见 [WIDEVINE.md](WIDEVINE.md#真实自身宿主验证与加密请求复测2026-10-05)。

**2026-10-05 此前 Windows 构建与宿主验证调查：** 先完成 Windows x64 Release 编译，启用 `FLUTIFY_NATIVE_WIDEVINE`，退出 0，耗时 **514.4 秒**；21 个随包 EXE / DLL 的 x64 架构和 VC 运行库依赖检查通过。产物为 `app/build/session-native-20261005/windows/x64/runner/Release/Flutify.exe`，须保留整个目录。该历史构建包含下述 401 及身份 / 缓存改动，早于 0.07 歌词生命周期修正；日志为工作区 `windows-session-native-build.log`、`session-native-runtime-check.log`。第三方 WebView 插件警告仍在，没有编译错误。

随后用相同证书及 83 B PSSH，在临时 Chrome 中做“默认开启宿主验证 → 测试关闭 → 恢复默认”对照，请求依次为 **4,274 B 加密身份 → 1,737 B 明文身份且无 VMP → 4,274 B 加密身份**；本次随包独立宿主同样生成 1,737 B 明文身份 / 无 VMP 请求。Chrome 的加密身份内 VMP 不可直接观察。这项对照确认了宿主验证对请求特征的影响，结合此前同一 Dart 客户端转发时的浏览器 200 / 独立宿主 403，将调查重点指向缺失的宿主验证接入；不把它当成服务端拒绝规则或原生修复完成的证明。本轮许可证请求数 **0**，只获取公开证书，不刷新账号令牌或下载媒体；4 项元数据解析测试通过，诊断工具静态分析无问题。日志：`host-verification-metadata.log`、`host-verification-parser-tests.log`、`host-verification-analyze.log`；详细条件和复现见 [WIDEVINE.md](WIDEVINE.md)。原生授权解密、出声、更新安装及真实 WebView Cookie 清理仍未因此得到实机验证。

**2026-10-05 账号 401 清理及错误分类增量：** 最新组合回归共 **166 项通过**，覆盖会话失效、OAuth、Web token、登录流程与登录页清理门禁、Windows CookieManager 环境、EME / Android 原生 / Windows 原生错误分类、Connect 接收端及协议消息。包含并发清理、清理失败重试、旧请求迟到与关闭页面等边界；与下述身份 / 缓存及历史 DRM 测试有重叠，不累加。定向 `dart analyze` 退出 0，无 error / warning，19 项 info；相关文件 `git diff --check` 通过。证据：工作区 `D:/Flutify/risk-session-final-tests.log`、`risk-session-final-analyze.log`。Windows CookieManager 使用方法通道测试替身，确认环境 ID 一致，不代表真实 WebView 清理已实机验证；本次未构建发行包、进行真实账号请求或验证 Windows 原生出声。

**2026-10-05 身份及缓存修正增量：** `protocol_message_test.dart`、`connect_service_test.dart`、`track_playback_api_test.dart`、`connect_receiver_test.dart` 共 70 项通过。覆盖实际登录编码、proto2 零值字段、播放命令、短 TTL / 并发 / 失效代次、区域主机及接收端恢复。定向 `dart analyze` 退出 0，无错误或警告，有 31 项 info。证据：工作区 `risk-identity-tests.log`、`risk-identity-analyze.log`。没有生成此次改动的发行包、进行真实账号兼容性验证，或宣称完成 TLS 对齐；下表和后文构建记录属于各自此前批次。

以下为历史批次记录，不能作为上述最新代码的构建或实机验证结果：

| 验证 | 结果 | 边界 |
| --- | --- | --- |
| `flutter test --no-pub` | 740 项通过，8 项显式跳过 | 包含 Connect、歌词、系统栏与交互、CENC 选择、HLS 初始化数据和原生回退等；使用 HTTP / 播放测试替身，跳过项不计为通过；双设备实机切换仍待验证 |
| 该历史批次的定向 Flutter 回归 | 16 项通过 | 全套之后新增错误分类日志测试；覆盖原生引擎、HLS 初始化数据和 FairPlay，与全套有重叠，不相加 |
| EME JavaScript 与自动同意测试 | 19 项通过 | 保留自动同意行为；不是实机浏览器兼容性验证 |
| Android 本地构建 | 未生成 APK：No Android SDK found | 系统栏效果仍需 Android 实机验证 |
| `flutter build windows --release --no-pub --dart-define=FLUTIFY_NATIVE_WIDEVINE=true` | 该历史批次 Windows x64 Release 构建成功，退出 0，670.1 秒 | 包含 CDM 子进程；保留第三方 WebView 插件警告，构建通过不等于真实播放通过 |
| ProxyServer `npm test` | 23 项通过 | 包含头清理、出口连接及 WebSocket 等边界；本轮未更改代理代码 |
| Windows x64 随包 CDM 子进程检查 | Chrome / Edge 组件均退出 0，接口 11 初始化通过；10,194 个加密样本被解析，无许可证时返回预期 `kNoKey`，容器重写保持长度 | 使用该历史批次构建的宿主；无网络、无账号、无许可证交换，不是完整播放实测 |
| Windows VC 运行库依赖 | 21 个随包原生程序 / 库检查通过 | 使用构建工具链的 `dumpbin /DEPENDENTS`，核对所需 VC 运行库随包存在 |
| Windows 原生真实许可证实验 | 修复后 Chrome / Edge CDM 均为应用证书 HTTP 200 / 702 B、许可证 HTTP 403 | CENC 文件解析到 10,194 个加密样本，使用 HLS 的 87 B 初始化数据仍被拒绝；403 原因尚未确定，未验证原生出声 |
| `dart analyze lib test tool/cdm/native_license_check_test.dart` | 退出 0，无错误或警告，仍有 info / 样式提示 | 分析当前源码与测试，不包含历史构建目录；不代表运行期接口验证通过 |

工作区证据日志在 `D:/Flutify/`：`connect-final-tests.log`、`connect-final-analysis.log`、`final-app-tests.log`、`final-app-analysis.log`、`ad-skip-tests.log`、`final-fix-tests.log`、`proxy-test.log`、`native-bridge-check.log`、`native-license-check.log`、`windows-native-build.log`。日志保留本地，不随版本发布。隔离的 Windows 本地构建产物在 `app/build/native-widevine/windows/x64/runner/Release/`。

原生格式修正历史批次的增量证据：`native-format-full-tests.log`、`native-format-final-targeted.log`、`native-format-final-analyze.log`、`native-format-cleanup-analyze.log`、`native-hls-license-check.log`、`native-edge-hls-license-check.log`、`android-review-node.log`、`android-review-build.log`、`windows-native-format-build.log`、`native-format-runtime-check.log`、`native-format-packaged-bridge-check.log`。旧构建记录仅代表当时源码；该批次产物另存 `app/build/native-format-fix/windows/x64/runner/Release/`，不覆盖 `build/pr-merge/`。

0.05beta 按用户要求提交 GitHub 构建，并明确提示 **Windows 可能不可用（未验证）**。发布版 x64 开启原生 DRM 实验并保留 WebView 加载失败回退；ARM64 保留 WebView。真实账号播放、完整设备兼容性和账号封禁概率未获得验证结论。

后续验证应集中在真实 Canvas 显示、外部播客长时播放与跳转、歌词源实际可用性，以及 Widevine 后端的设备兼容性。真实许可证成功、能出声、暂停 / 跳转 / 退出清理都需要分别验证；单纯初始化 CDM 成功不等于完整播放成功。

### 0.06beta 发布前回归

在合入 PR #9 / #10、歌词当前行位置设置、翻译匹配与沉浸式播放器修正后，版本更新为 `0.0.6+6`。全套 Flutter 测试 762 项通过、8 项跳过；发布流程、EME 播放与自动同意脚本测试 25 项通过。`dart analyze lib test tool/cdm/native_license_check_test.dart` 无错误或警告，有 202 项 info 提示。日志为工作区 `v006-tests.log`、`v006-node-tests.log`、`v006-analyze.log`。

版本号更新前的同批功能已完成本地 Windows x64 Release 编译（466.0 秒），21 个原生文件的架构及 VC 运行库依赖检查通过；产物在 `app/build/lyrics-position/windows/x64/runner/Release/`。该验证不代表新版完整播放或原生 Widevine 获得许可证；0.06beta 的各平台发行产物由标签触发的 GitHub Actions 重新构建。

## 6. 修正旧报告

此前关于“完全没有播放上报”“设备 ID 总是由主机名生成”“永远上报固定音质”“播客只能展示”和“全应用统一官方身份”的表述不再符合当前实现。本文以具体代码行为替代这些结论；对服务端风控因果不作未经验证的确定性断言。
