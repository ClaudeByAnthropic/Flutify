# Flutify 与 ProxyServer 风险及功能审查

核对日期：2026-10-04。范围为本地 `app`、相邻 `ProxyServer` 和 `SpotifyApi` 协议资料；以当前代码和自动化测试为依据，没有进行真实账号封禁因果实验。

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

本轮主要完成核查与报告更新，没有为“伪装官方指纹”改写 ProxyServer。

## 2. App 网络、认证与协议

| 项目 | 当前证据 | 评估 |
| --- | --- | --- |
| 网关路由 | `services/network/spotify_gateway.dart`、`gateway_http_client.dart` | 限定 Spotify / CDN 和特定 Widevine 请求；外部播客走正常网络路由，不把任意站点引入网关 |
| 重定向 | `gateway_http_client.dart` 与网络测试 | 跨源重定向剥离凭据，拒绝 HTTPS 降级；外部音频请求不附带 Spotify 认证头 |
| 桌面 OAuth | `services/auth/`：浏览器授权、回环回调、PKCE、令牌刷新 | OAuth 链路已有刷新合并等保护；这不等于获得复用官方客户端标识的服务端授权 |
| 数据层身份 | `auth/client_profile.dart`、`auth_constants.dart` | Windows 桌面版本常量为 1.3.1.234；非 Windows 平台仍使用 Windows 19045 回退及 x64 字段，是明确存在的实现差异 |
| Web 播放身份 | `connect/receiver/track_playback_api.dart` | track-playback 另用 Web 会话、Web client-token、1.3.5.31 及 Windows / Chrome 154 常量，不能声称整应用只有一种身份 |
| Web client-token | `track_playback_api.dart` 的缓存和 `invalidate()` | 当前按 401 / 403 失效更新，未按到期时间主动更新，也未合并所有并发申请；仍可改善请求效率与恢复行为 |
| 内部 API | Pathfinder 持久化查询、spclient、dealer、track-playback | 查询 hash、字段和许可证策略可随服务端升级失效，需保留明确错误与可恢复路径 |
| 本地数据 | `StorageService`、播放缓存、探测工具 | 未开展操作系统级凭据存储审计；会话文件与 `tool/probe_out/` 应作为敏感本地数据，不应进入仓库或报告 |

`SpotifyApi/tmp/web-player.js` 用作官方 Web 客户端实现对照。其中歌词 `clientLanguage` 支持 `all`，`alternatives` 包含语言与按原词索引对应的字符串数组。本轮据此接入源译文，而非假设存在通用翻译 API。

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
- 新增日语和繁体中文界面资源，保留简体中文和英文，支持手动选择、偏好持久化和跟随系统。Spotify 请求使用所选语言；语言选项使用自动换行的 ChoiceChips，窄屏和大字号下不会把英文挤到不可见位置。

依据：`providers/spotify_provider.dart`、`services/pathfinder/desktop_data_source.dart`、`ui/screens/home/`、`l10n/app_ja.arb`、`ui/screens/settings/sections/language_section.dart`；`test/home_refresh_test.dart`、`desktop_home_refresh_test.dart`、`ui/home_refresh_test.dart`、`ui/settings_more_test.dart`。

## 5. 验证与未验证范围

| 验证 | 结果 | 边界 |
| --- | --- | --- |
| `flutter test --no-pub` | 586 项通过，6 项显式跳过 | 包含 Connect 撤销播放状态、切走后立即恢复、Android 原生异步加载取消，以及广告跳过、首页刷新、四种界面语言、源译词和原生播放回退等；使用 HTTP / 播放测试替身，跳过项不计为通过；双设备实机切换仍待验证 |
| `flutter build windows --release --no-pub --dart-define=FLUTIFY_NATIVE_WIDEVINE=true` | 本地 Windows x64 Release 构建成功，退出 0，118.1 秒 | 包含 CDM 子进程；保留第三方 WebView CMake 开发警告，构建通过不等于真实播放通过；此记录早于发布版本号更新 |
| ProxyServer `npm test` | 23 项通过 | 包含头清理、出口连接及 WebSocket 等边界；本轮未更改代理代码 |
| Windows x64 随包 CDM 子进程检查 | Chrome / Edge 组件均退出 0，接口 11 初始化通过；8185 个加密样本被解析，无许可证时返回预期 `kNoKey`，容器重写保持长度 | 无网络、无账号、无许可证交换；不是完整播放实测 |
| Windows 原生真实许可证实验 | 应用证书 HTTP 200 / 702 B；许可证 HTTP 403 | 403 原因尚未确定，未验证原生出声；WebView 播放日志不能作为原生验证证据 |
| `dart analyze lib test tool/cdm/native_license_check_test.dart` | 退出 0，无错误或警告；189 条 info / 样式提示 | 分析当前源码与测试，不包含历史构建目录；不代表运行期接口验证通过 |

工作区证据日志在 `D:/Flutify/`：`connect-final-tests.log`、`connect-final-analysis.log`、`final-app-tests.log`、`final-app-analysis.log`、`ad-skip-tests.log`、`final-fix-tests.log`、`proxy-test.log`、`native-bridge-check.log`、`native-license-check.log`、`windows-native-build.log`。日志保留本地，不随版本发布。隔离的 Windows 本地构建产物在 `app/build/native-widevine/windows/x64/runner/Release/`。

0.05beta 按用户要求提交 GitHub 构建，并明确提示 **Windows 可能不可用（未验证）**。发布版 x64 开启原生 DRM 实验并保留 WebView 加载失败回退；ARM64 保留 WebView。真实账号播放、完整设备兼容性和账号封禁概率未获得验证结论。

后续验证应集中在真实 Canvas 显示、外部播客长时播放与跳转、歌词源实际可用性，以及 Widevine 后端的设备兼容性。真实许可证成功、能出声、暂停 / 跳转 / 退出清理都需要分别验证；单纯初始化 CDM 成功不等于完整播放成功。

## 6. 修正旧报告

此前关于“完全没有播放上报”“设备 ID 总是由主机名生成”“永远上报固定音质”“播客只能展示”和“全应用统一官方身份”的表述不再符合当前实现。本文以具体代码行为替代这些结论；对服务端风控因果不作未经验证的确定性断言。
