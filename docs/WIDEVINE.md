# 原生 Widevine 播放跨平台评估

核对日期：2026-10-05。Android 使用原生 Media3 / MediaDrm；Windows x64 已接入实验性的原生 CDM 解密与音频播放管线，但真实许可证请求返回 HTTP 403，尚未证明原生曲目能够解密出声。未显式启用实验时使用 WebView2；当前 CI 的 Windows x64 构建启用实验并保留失败回退，ARM64 使用 WebView2。

## PR #1 的实现

[PR #1](https://github.com/is-hp-is-mad/Flutify/pull/1) 使用 Android Media3 ExoPlayer，通过 `C.WIDEVINE_UUID` 和 `FrameworkMediaDrm.DEFAULT_PROVIDER` 调用系统提供的 Widevine CDM。
入口在 `android/app/src/main/kotlin/com/flutify/music/flutify_app/NativeDrmPlugin.kt`；Dart 侧通过 `lib/services/eme/native_drm_audio_engine.dart` 调用它，沿用本机媒体与许可证转发服务。

它没有实现一套可移植的 Widevine 解密算法。认证、曲目地址、加密媒体缓存、许可证请求转发及 Flutter 播放状态可以复用；Android 的 MediaDrm、Media3 和 Kotlin 平台插件需要替换为目标平台的播放器/CDM 接口。

## 除 iOS 外的平台

| 平台 | 无浏览器播放的候选方式 | 目前结论 |
| --- | --- | --- |
| Android | Media3 + 系统 MediaDrm/Widevine | 已接入；仍需覆盖不同厂商设备和媒体通知行为 |
| Windows x64 | 独立原生 CDM 宿主 + AAC CENC 解析 + 内存 MP4 + media_kit | 已实现实验管线；CDM 初始化通过，真实许可证 HTTP 403，原生出声未通过 |
| Windows ARM64 | 同上，使用对应架构组件 | 有组件元数据；未进行原生宿主实测 |
| Linux x64 / ARM64 | 原生 CDM 宿主 + 媒体管线 | 有对应架构组件；仍需验证宿主、发行版及许可证兼容性 |
| macOS x64 / ARM64 | 原生 CDM 宿主 + 音频管线，处理签名与分发 | 有对应架构组件；尚未验证 Flutify 的可用性 |

2026-10-03 的跨平台调查只查询 Google 组件更新服务元数据，没有下载、执行或分发 CDM。查询返回 Windows x64/ARM64、Linux x64、macOS x64 为 `4.10.3050.0`，Linux ARM64 为 `4.10.3057.0`，macOS ARM64 为 `4.10.3112.0`。下节的 2026-10-04 实验加载了本机已安装的 Windows x64 组件；版本与前次元数据查询分别记录。
这表明不能把 ARM64 简单判为“没有 CDM”；元数据可用不证明宿主 ABI、服务端许可证策略和实际播放链路兼容，也不代表获得再分发许可。

[Kodi InputStream Adaptive](https://github.com/xbmc/inputstream.adaptive) 的 `WVCdmAdapter.cpp` / `media::CdmAdapter` 展示了浏览器之外托管 Widevine CDM 的工程方式，可用于研究接口与生命周期。
其代码使用 GPL 许可，移植到本项目时需要单独评估许可兼容性。Windows Media Foundation / PlayReady 也不是 Widevine 的直接替代品；只有内容服务提供匹配的 DRM 许可证与媒体格式时才适用。

Widevine 官方提供许可合作流程，并说明不收取 Widevine 产品/服务费用。接入与分发仍应依据其许可条件，不以提取密钥、绕过许可证或伪造设备认证作为实现方式。

## Windows x64 原生会话实验（2026-10-04）

独立探针：[native_session_probe.cpp](../tool/cdm/native_session_probe.cpp)。使用相邻 Chromium CDM 头文件的版本化接口，分别匹配 Host/CDM 10、11、12；不把不同版本的虚表强制转换为同一接口。用 MSVC C++17、`/W4` 编译成功，无编译警告。

| 已安装组件 | CDM 版本 | CDM 10 / 11 | CDM 12 | 退出码 |
| --- | --- | --- | --- | --- |
| Chrome 154.0.8037.93 | 4.10.3112.0 | 均初始化成功，创建并关闭临时会话 | 实例未创建 | 0 |
| Edge 154.0.4258.53 | 4.10.3050.0 | 均初始化成功，创建并关闭临时会话 | 实例未创建 | 0 |

每个成功实例均生成 `kLicenseRequest` 消息（本次为 1704 字节），随后收到会话关闭与 promise 完成回调，销毁实例并卸载模块。模块初始化导出为 `InitializeCdmModule_4`；模块接口版本、CDM/Host 接口版本与组件版本是三种不同编号。CDM 12 的结果只适用于本次这两个二进制文件。

探针使用 Widevine CENC PSSH 和合成的全零 key ID（标识元数据，不是内容密钥），不请求真实曲目，不进行网络或许可证交换。它关闭持久化与 distinctive identifier，不伪造平台认证、输出保护或 StorageId；仅输出状态、版本和消息长度，不输出许可证消息正文、会话 ID 或账号凭据。旧的 `tool/cdm/cdm_host.cpp` 未被本次实验调用。

从仓库根目录在 Windows `cmd.exe` 复现（需安装 x64 MSVC；按本机安装位置调整路径）：

```bat
call D:\VSBuildTools\VC\Auxiliary\Build\vcvars64.bat
if not exist build\native-widevine-probe mkdir build\native-widevine-probe
cd build\native-widevine-probe
cl /nologo /std:c++17 /EHsc /W4 /O2 ..\..\tool\cdm\native_session_probe.cpp /Fe:native_session_probe.exe
native_session_probe.exe "C:\Program Files\Google\Chrome\Application\154.0.8037.93\WidevineCdm\_platform_specific\win_x64\widevinecdm.dll"
native_session_probe.exe "C:\Program Files (x86)\Microsoft\Edge\Application\154.0.4258.53\WidevineCdm\_platform_specific\win_x64\widevinecdm.dll"
```

证据日志保存在工作区 `D:/Flutify/native-widevine-probe.log`，构建产物位于忽略的 `app/build/native-widevine-probe/`。没有将 CDM 复制进项目或分发。

以上是早期会话探针的结果。后续播放管线和真实许可证实验如下，不能把会话初始化成功等同于播放成功。

## Windows x64 实验播放管线

启用方式：

```bat
flutter build windows --release --no-pub --dart-define=FLUTIFY_NATIVE_WIDEVINE=true
```

普通构建也可以在启动进程前设置 `FLUTIFY_NATIVE_WIDEVINE=1`。未启用时仍走 WebView2。ARM64 没有打包此 x64 宿主，不能按 x64 实测结果宣称可用。

1. `track_playback_media.dart` 只从 `file_ids_mp4` 选择最低码率的 CENC 文件；`file_ids_mp4_cbcs` 留给 FairPlay。`windows_native_decryptor.dart` 等待加密媒体下载完成（最多 30 秒、64 MiB），由 `cenc_audio.dart` 解析 AAC fMP4 CENC 的 PSSH、KID、IV 与 subsamples。创建会话优先使用 HLS 清单中的 Widevine PSSH 原始字节，与现有 HLS 播放路径保持一致；清单没有该数据时使用 MP4 内的 PSSH。
2. `windows_cdm_process.dart` 启动可执行文件旁的 `flutify_cdm_bridge.exe`，加载本机浏览器安装的 CDM，优先匹配接口 11，其次 10。账号凭据和网络请求仍留在现有 Dart 许可证客户端。
3. 每个临时会话重新获取 application certificate，交换 CDM 原样生成的许可证请求；不提取内容密钥，不修改许可证响应。
4. 通过匿名管道分批解密样本。全部成功后才将 MP4 的加密描述改为普通 AAC，在内存中交给 media_kit；不保存解密文件。失败、取消、切歌及释放时清理缓冲区并关闭子进程；宿主自身持有的解密缓冲区使用 `SecureZeroMemory` 清理。这不代表已审计第三方解码器的所有内存副本。
5. 首次原生加载失败后，本次应用运行关闭后续原生尝试，使用延迟启动的 WebView 播放。暂停、音量、跳转和取消旧加载的行为有测试替身覆盖；实际出声后的运行期错误不会自动重播到 WebView。

当前只支持已实现的 AAC CENC 路径；CBCS、`seig` 密钥轮换、缺失样本加密信息及不合法 / 重叠样本会失败并回退。管道单帧上限 8 MiB，Dart 每批最多 128 个样本。实验需要整文件就绪才开始原生处理，首播延迟与内存消耗均不能宣称优于流式 WebView。

### 真实实验结果

- 对真实加密样本解析到 8,185 个加密样本、83 字节 PSSH；本机 Chrome 和 Edge 的接口 11 都能启动，未安装许可证的解密请求均返回预期的 `kNoKey`，然后正常退出。这仅验证无许可证时的错误路径。
- 使用已有本地会话进行一次真实许可证诊断：application certificate 返回 HTTP 200 / 702 字节，许可证端点返回 HTTP 403。因此没有成功解密媒体，也没有验证原生音频输出；403 的具体原因尚未确定。
- `native_license_check_test.dart` 是显式启用的诊断，不随普通测试运行。它只读指定偏好文件，随后使用内存副本，避免令牌刷新改写正在运行的用户会话；日志只记录阶段、HTTP 状态和长度。
- CENC 解析、原生引擎生命周期及组件发现由自动化测试覆盖；相关测试替身输出不能当成真实 CDM 播放证据。

证据：工作区 `native-bridge-check.log`、`native-license-check.log`；后续构建日志为 `windows-native-build.log`。实验版目录为 `app/build/native-widevine/windows/x64/runner/Release/`，其中包含 `Flutify.exe` 与独立宿主，不包含 CDM DLL。

### `unsupported_cenc` 修复与复测（2026-10-04）

用户 20:37 日志中的文件 `15a8f0998bcf63c01cbd3fbc7cd3a49a43afcb36` 实际为 AAC / **CBCS**。原选择器将 CENC、CBCS 混在一起仅按码率排序，可能把原生后端不支持的 CBCS 交给 CENC 解析器。现已限定 Widevine 路径选择明确的 `file_ids_mp4` 分组，缺少该分组时不猜测未知格式；FairPlay 继续选择 CBCS。解析器区分 `unsupportedEncryptionScheme` 和 `unsupportedCodec`，没有把 CBCS 冒充 CENC 解密。

另一个差异是初始化数据来源：复测文件的 MP4 内 PSSH 为 83 字节，HLS 提供的 PSSH 为 87 字节，后者包含 `cenc` 保护格式字段。原生会话现在使用清单提供的完整原始数据，不自行拼装或修改服务元数据。新增解析器验证 PSSH 长度、版本、Widevine UUID 与数据边界；不抓取远程 key URI，不接受当前管线尚未实现的多组 PSSH 轮换。

修复后的本地真实 CENC 文件解析得到 **10,194** 个加密样本。使用内嵌 PSSH、改用 HLS PSSH、改用 Edge CDM 三次有界诊断中，应用证书均成功获取（HTTP 200 / 702 B），许可证均返回 **HTTP 403**。因此格式选择和初始化数据差异已修正，但原生完整解密及出声仍未验证成功，也不能断言 403 是某一种宿主认证或令牌问题。日志现在可明确显示 `license_http_403`，失败仍回退 WebView，不连续重复请求被拒绝的许可证。

证据日志：`D:/Flutify/native-format-license-check.log`、`native-hls-license-check.log`、`native-edge-hls-license-check.log`。诊断工具可显式设置 `FLUTIFY_CDM_CHECK_FETCH_MANIFEST=1` 获取本地缓存文件对应的 HLS 清单，并使用同一偏好中的代理配置；凭据与许可证正文不写入诊断日志。

本轮全套 Flutter 测试 740 项通过、8 项跳过；随后新增错误分类日志测试，原生引擎、初始化数据与 FairPlay 定向回归 16 项通过（与全套有重叠，不相加）。这些自动化结果不改变上述真实许可证失败结论。

本轮 Windows x64 Release 已启用原生实验并构建成功（退出 0，670.1 秒），产物为 `app/build/native-format-fix/windows/x64/runner/Release/Flutify.exe`；保留完整目录使用，其中包含 `flutify_cdm_bridge.exe`，不包含 CDM DLL。21 个随包原生程序 / 库的 VC 运行库依赖检查通过；使用新宿主加载本机 Chrome 和 Edge 组件，接口 11 初始化、无许可证时返回 `kNoKey` 及进程关闭均通过，仍不是有许可证的播放验证。构建含第三方 WebView 插件警告，没有编译错误。证据：`windows-native-format-build.log`、`native-format-runtime-check.log`、`native-format-packaged-bridge-check.log`。

### 同一会话的浏览器 / 独立宿主对照（2026-10-05）

这次对照使用同一个新获取的非匿名 Web 令牌、同一份 application certificate（HTTP 200 / 702 B）、同一曲目的 HLS PSSH（87 B），以及相同的 Dart 许可证客户端和代理配置：

| 路径 | 许可证结果 | 已证实的范围 |
| --- | --- | --- |
| 本机 Chrome，无头临时配置 | HTTP 200，EME key status 为 `usable` | 该账号与内容数据能在浏览器宿主下取得可用许可证；未播放音频 |
| Flutify 独立 CDM 宿主，接口 11 | HTTP 403，响应正文 0 B | CENC 的 10,194 个加密样本解析完成、CDM 初始化成功；尚未进行成功的授权解密 |

日志：工作区 `D:/Flutify/native-current-license-check.log`。该结果将调查重点缩小到独立宿主生成请求的兼容性，不能从空的 403 正文断言具体服务端拒绝策略。

已核实的一处接入差异：Chromium 会用真实宿主文件、CDM 文件及对应签名调用 `VerifyCdmHost_0`；发行版实验宿主没有这套验证接入，后续独立诊断探针已接入，结果见下节。该接口的返回值表示验证启动情况，并不等于许可证一定可用。仓库目前只有 Android 的系统 MediaDrm 接入，没有 Windows 独立宿主的签名与完整验证资料；Android 系统接口不能直接用于 Windows。不能以浏览器签名代替 Flutify 宿主签名，也不能把浏览器探针的成功称为原生播放修复。

从仓库根目录显式运行对照（路径替换为本机文件）：

```bat
set FLUTIFY_CDM_CHECK_PREFS=C:\path\to\shared_preferences.json
set FLUTIFY_CDM_CHECK_MEDIA=C:\path\to\cached-file-id.m4a
set FLUTIFY_CDM_CHECK_HELPER=C:\path\to\flutify_cdm_bridge.exe
set FLUTIFY_CDM_CHECK_METADATA_ONLY=0
set FLUTIFY_CDM_CHECK_FETCH_MANIFEST=1
set FLUTIFY_CDM_CHECK_REFRESH_TOKEN=1
set FLUTIFY_CDM_CHECK_BROWSER=C:\Program Files\Google\Chrome\Application\chrome.exe
flutter test --no-pub tool/cdm/native_license_check_test.dart
```

媒体文件名须为缓存的 40 位 file ID。浏览器选项仅用于诊断，可省略；浏览器使用临时配置，许可证仍由 Dart 请求，账号令牌不传入网页。偏好文件只读并克隆到内存，诊断不会更新用户的已保存会话；不记录凭据、许可证正文、内容密钥或明文媒体。

本轮另修复了失败恢复：原生解码器 `stop()` 抛错时，将其释放并禁用本次运行的原生尝试，继续清理媒体内存及回退；许可证和解析失败尚未打开解码器时，不调用其 `stop()`。回归测试复现了修复前清理错误阻断回退，并覆盖修复后回退、停止、内存释放和后续曲目行为。这项稳定性修复不改变上述 HTTP 403 结论。

本轮修复验证：38 项相关回归测试通过，包括原生失败恢复、切歌与取消、CENC/初始化数据，以及语言设置和无障碍布局。启用原生实验的 Windows x64 Release 构建成功，产物为 `app/build/native-recovery-language/windows/x64/runner/Release/Flutify.exe`；随包 21 个 EXE/DLL 的 x64 架构和 VC 运行库依赖检查均通过，须保留整个 Release 目录使用。静态分析没有错误或警告，仅有 3 条原有的构造函数风格提示。证据：工作区 `native-language-regression.log`、`native-language-analyze.log`、`windows-native-recovery-build.log`、`native-recovery-runtime-check.log`。本轮未取得原生授权解密或出声成功的结果。

### 宿主验证开关的本地对照（2026-10-05）

此前同会话的请求元数据对照中，Chrome 生成 4,278 B 请求，客户端身份已加密；独立宿主生成 1,741 B 请求，客户端身份为明文，VMP 字段缺失。两者的 HLS PSSH、请求类型、协议版本和时间检查均一致。Chrome 的 VMP 位于加密身份内，不能由这份元数据证明其具体内容。两种请求都经同一个 Dart HTTP 客户端转发，故不能用“Chrome TLS 与 Dart TLS 不同”解释此前的 200 / 403。证据：`D:/Flutify/native-request-metadata-check.log`。

本次核对 Chromium 的 `CdmAdapter`、`CdmWrapper` 和 `CdmModule`：当前宿主的初始化参数、等待初始化完成、设置证书后创建临时 CENC 会话的顺序与参考实现一致；Chromium 另有 `VerifyCdmHost_0` 宿主文件验证步骤。`media/base/media_switches.cc` 将 `CdmHostVerification` 默认开启，并明确允许测试时关闭。本次只在诊断创建的临时 Chrome 进程中使用该开关，未改变用户浏览器或应用配置。

对照使用同一份新 application certificate（HTTP 200 / 702 B）和缓存 MP4 的 83 B PSSH，每次启动新的临时 Chrome 配置；按“默认开启 → 测试关闭 → 恢复默认”的顺序采集本地请求，再运行本次 Release 随包的原生宿主：

| 路径 | 请求长度 | 客户端身份 | 可观察的 VMP |
| --- | --- | --- | --- |
| Chrome 默认宿主验证 | 4,274 B | 加密；证书 provider / serial 匹配 | 加密内不可观察 |
| Chrome 测试关闭宿主验证 | 1,737 B | 明文 | 缺失 |
| Chrome 恢复默认宿主验证 | 4,274 B | 加密；证书 provider / serial 匹配 | 加密内不可观察 |
| 本次随包独立宿主，接口 11 | 1,737 B | 明文 | 缺失 |

Chrome 为本机 `154.0.8037.93`，原生固定加载同一安装目录的 CDM `4.10.3112.0`。本次外部进程模块采样未捕获浏览器的 DLL 路径，不能把实际模块路径核验算作本轮新增证据。所有请求都使用 streaming / new、协议 2.2、128 B 签名、16 B 请求 ID，PSSH 匹配输入且请求时间在 5 分钟内。长度相同和这些字段相同不表示请求逐字节相同。

**结论：在该 Chrome / CDM 环境中，关闭宿主验证可复现独立宿主的请求特征，恢复验证后特征恢复。** 该结果将调查指向宿主验证，但没有证明服务端仅检查 VMP 或身份加密。后续实验证实：即使自身签名缺失，调用验证接口也能开启身份加密，而许可证仍为 403（见下节）。因此不能把“未调用验证接口”“身份未加密”和“宿主认证未通过”视为同一件事，也不能声称补一个调用即可修复。

本次**未发送任何许可证请求**，未刷新账号令牌、请求新媒体或保存挑战正文；只读取偏好内存副本中的网络配置与本地加密媒体，并获取公开应用证书。诊断客户端在 metadata 模式下主动拒绝许可证端点请求。恢复对照整项集成诊断退出 0，元数据解析回归 4 项通过，定向静态分析无问题。日志：`D:/Flutify/host-verification-metadata.log`、`host-verification-parser-tests.log`、`host-verification-analyze.log`。

复现时使用上节的偏好、媒体、宿主和浏览器路径，并额外设置以下变量；无需有效账号令牌，但工具仍要求偏好中有已有 Web 登录记录：

```bat
set FLUTIFY_CDM_CHECK_METADATA_ONLY=1
set FLUTIFY_CDM_CHECK_FETCH_MANIFEST=0
set FLUTIFY_CDM_CHECK_REFRESH_TOKEN=0
set FLUTIFY_CDM_CHECK_LIBRARY=C:\path\to\widevinecdm.dll
flutter test --no-pub tool/cdm/native_license_check_test.dart
```

若不指定浏览器，只采集原生请求元数据。诊断只使用 Chromium 公开测试开关，不修改 CDM、不替换签名、不将测试关闭验证的请求发送给服务端。之前的 interface 10 / 11、预加载系统 `dxva2.dll` 本地对照均未改变明文身份 / 无 VMP 特征；错误证书会被拒绝，回调也未显示 StorageId / FileIO / 平台挑战阻塞请求生成，因此本轮没有重复这些实验。

### 真实自身宿主验证与加密请求复测（2026-10-05）

新增显式诊断 [native_host_verification_probe.cpp](../tool/cdm/native_host_verification_probe.cpp)，复用生产宿主的 CDM 接口、回调与管道协议。探针在 `InitializeCdmModule_4` 之前调用 `VerifyCdmHost_0`，提交当前探针自身 EXE、实际加载的 CDM DLL，以及各自相邻的 `.sig`。本机 CDM 签名可读，探针自身签名缺失；按 Chromium 行为传入无效签名句柄，所有文件句柄交给 CDM 关闭。没有借用其他程序的宿主文件或签名。

接口返回 `verification_call_accepted=1`。依照公开头文件，这只表示接受异步处理；Chromium 的 `ReportMetrics` 实现也没有提供可据此确认认证通过的公开结果。此时 83 B PSSH 生成 **3,682 B** 请求，客户端身份已加密（密文 3,104 B），证书 provider / serial 匹配，VMP 在加密身份内不可观察。**自身 `.sig` 缺失不妨碍本机 CDM 开启隐私模式，但这不证明宿主通过认证。** 此项本地诊断通过，未发送许可证。

接着获取新非匿名 Web 令牌、702 B 应用证书及 87 B HLS PSSH，真实请求长度为 **3,686 B**，仍返回 **403 / 0 B**。这直接否定了“只开启身份加密即可修复”的假设。日志：工作区 `self-host-verification-metadata.log`、`self-host-verification-callback.log`、`self-host-license-check.log`、`self-host-license-callback.log`。

再做四组本地对照，分别为：仅验证接入、初始化后等待 5 秒、验证前预加载系统 `dxva2.dll`、预加载并等待。等待期间宿主继续处理 CDM 定时器；DXVA 仅从 Windows 系统目录加载。四组都生成 **3,682 B / 加密身份 3,104 B** 请求，证书及 PSSH 匹配，均正常关闭；许可证请求数 **0**。可观察字段一致不表示加密正文逐字节相同，也不能排除加密内部状态变化。

因此对“预加载并等待”配置再进行一次同令牌的真实 Chrome / 原生对照：

| 路径 | 请求 / 身份密文长度 | 许可证结果 |
| --- | --- | --- |
| Chrome 默认宿主验证 | 4,278 B / 3,696 B | HTTP 200，EME `usable` |
| 自身宿主验证 + 系统 DXVA + 等待 5 秒 | 3,686 B / 3,104 B | HTTP 403，正文 0 B |

两者共用同一新非匿名 Web 令牌、证书、87 B HLS PSSH、Dart HTTP 客户端及代理配置。原生 CDM 固定为本机 `4.10.3112.0`，接口 11。最终对照共发送两次许可证请求；加上此前单独原生请求，本节共三次。Chrome 成功只验证了可用许可证，没有播放音频；原生未能进入授权解密。日志：`self-host-license-dxva2-settled-check.log`、`self-host-license-dxva2-settled-callback.log`；本地四组日志为 `self-host-verification-{baseline,settled,dxva2,dxva2-settled}-metadata.log` 和对应 `-callback.log`。

**当前结论：验证调用、身份加密、预加载 DXVA 与等待均不足以解决 403。** 同一客户端的成功对照不支持把此次差异归结为账号整体不可用或 TLS 栈差异。Windows 宿主自身有效签名及完整接入资料仍缺失，是继续验证的重要缺口；空的 403 不能证明签名是唯一拒绝原因，身份密文长度差也不能用于推定 VMP 内容。输出保护与持久化接口仍有平台实现差异，未将未知状态改为成功来试探服务器。下一步需要补齐可验证的自身宿主认证条件，或获得许可证服务端的具体拒绝原因，才能继续针对性修复。

该接入仍限于诊断工具，未加入发行宿主。探针 MSVC C++17 `/W4 /WX` 构建通过；四组本地真实 CDM 诊断通过，Dart 定向静态分析无问题。许可证集成诊断因真实 403 退出 1，不计为测试通过。未修改用户的持久化凭据，未保存原始请求、许可证或明文媒体。

从仓库根目录构建探针（MSVC 路径按本机调整）：

```bat
call D:\VSBuildTools\VC\Auxiliary\Build\vcvars64.bat
if not exist build\cdm-self-verification mkdir build\cdm-self-verification
cd build\cdm-self-verification
cl /nologo /std:c++17 /EHsc /W4 /WX /O2 ..\..\tool\cdm\native_host_verification_probe.cpp /Fe:native_host_verification_probe.exe
cd ..\..
```

沿用上节偏好、媒体、CDM 路径及 metadata 模式，将 `FLUTIFY_CDM_CHECK_HELPER` 设为探针的绝对路径，并设置可写日志路径 `FLUTIFY_CDM_HOST_PROBE_LOG`。`FLUTIFY_CDM_HOST_PROBE_PRELOAD_DXVA2=1` 开启系统 DXVA 预加载；`FLUTIFY_CDM_CHECK_SETTLE=1` 开启 5 秒等待，未设置则都不启用。运行同一 `flutter test --no-pub tool/cdm/native_license_check_test.dart`。只有显式将 `FLUTIFY_CDM_CHECK_METADATA_ONLY=0` 才会进入真实许可证诊断；可再设置 `FLUTIFY_CDM_CHECK_BROWSER` 做默认验证模式的浏览器对照。

### 输出保护回调与本机 OPM 检查（2026-10-05）

透明 Host 10 / 11 代理仅记录回调名称，原样转发参数和返回值。初始化过程中确实调用 `QueryOutputProtectionStatus`；未观察到 `RequestStorageId`、`CreateFileIO`、`SendPlatformChallenge` 或 `EnableOutputProtection`。生产宿主目前异步返回 `kQueryFailed, 0, 0`。代理探针正常退出，83 B PSSH 的请求仍为 3,682 B / 身份密文 3,104 B。

临时 Chrome 的 `media` trace 实测 `CdmAdapter::OnQueryOutputProtectionStatusDone` 为 `success=true, link_mask=0, protection_mask=0`。诊断仅输出该布尔值和数值掩码，原始 trace 留在内存；这确认了回调差异，但尚未证明它导致 403，也没有把原生未知状态硬编码为成功。该批次许可证请求数为 0。证据：工作区 `self-host-verification-trace-settled-{metadata,callback}.log`、`self-host-verification-browser-output-{metadata,callback}.log`。

独立 `native_output_capability_probe.cpp` 检查本机真实 OPM 能力：当前为本地会话、一条内置显示链路，输出枚举与 `StartInitialization` 均成功，返回证书可解析。普通 Windows 缓存链验证得到 `chain_errors=0x21`、Microsoft root policy `0x800B0109`；尚需确认 OPM 专用信任锚和验证规则，不能据此断言驱动不可信。尚未执行 `FinishInitialization` 或经过认证的 `GetInformation`，所以未测得 HDCP 状态。未修改信任库、跳过证书验证或配置显示保护，许可证请求数为 0；MSVC `/W4 /WX` 编译通过。证据：工作区 `output-capability-certificate-check.log`。

### 0.07 Windows 本地构建（2026-10-05）

版本 `0.0.7+7` 的 x64 Release 已编译通过，启用原生 Widevine 实验，并修正歌词背景首次暂停后直接关闭的 Ticker 生命周期异常。产物为 `app/build/v007-20261005/windows/x64/runner/Release/Flutify.exe`，文件版本 `0.0.7.7`；21 个 EXE / DLL 架构和 VC 运行库依赖检查通过，便携 ZIP 的 CRC 检查通过。Flutter 全套回归 851 项通过、8 项跳过，Node 测试 25 项通过。证据：工作区 `v007-final-tests.log`、`v007-windows-final-build.log`、`v007-package-check.log`。编译与测试不代表原生许可证、解密出声或更新安装已通过实机验证。

### 此前 Windows 构建（2026-10-05）

按用户要求先构建，再进行上述调查。启用原生实验的 Windows x64 Release 构建成功，退出 0，耗时 **514.4 秒**；产物在 `app/build/session-native-20261005/windows/x64/runner/Release/Flutify.exe`。**须保留整个 Release 目录**，其中包含独立宿主，不包含 CDM DLL。随包 21 个 EXE / DLL 的 x64 架构及 VC 运行库依赖检查通过。第三方 WebView 插件仍有编译警告，没有编译错误。

该历史构建包含 401 清理及当时的应用改动，早于上述 0.07 歌词生命周期修正。随包宿主已用于上面的真实 CDM 请求生成验证，许可证、原生解密和出声仍未验证成功。更新功能和真实 WebView Cookie 清理也不能仅由编译成功视为完成实机验证。证据：`D:/Flutify/windows-session-native-build.log`、`session-native-runtime-check.log`。

### 证书与组件更新

三者分别处理：

| 对象 | 更新方式 |
| --- | --- |
| Widevine application certificate | 每个原生会话从服务端重新获取，无固定嵌入证书 |
| 曲目许可证 | 按临时会话重新请求，不跨会话缓存；请求被拒绝时回退，不把更新证书当作 403 的解决保证 |
| Widevine CDM DLL | 由 Chrome / Edge 自身安装与更新；每次新会话扫描系统 / 用户安装目录和 `User Data/WidevineCdm` 组件目录，按组件版本排序选择 |

Flutify 不下载、复制或分发 CDM。浏览器更新组件后，新会话会重新发现版本；正在使用的会话不会热替换 DLL。没有安装可用组件或初始化失败时回退。

用户日志中的 `[eme-js]`、Edge User-Agent、`createMediaKeys`、MSE 和 hls.js 都说明在使用 WebView 的 EME 路径。能正常播放这些日志对应的歌曲，不能证明原生 Widevine 已成功，也不能据此删除 WebView。

## 资源占用与验证顺序

原生播放可以省去专为音频运行的浏览器渲染进程、JavaScript 与 MSE 管线，因此有望降低常驻内存、进程数量及启动开销。解密、解码、网络和音频输出仍然存在，CPU 与耗电收益需实测；不能仅凭架构给出降低百分比。
登录页仍可独立使用浏览器，浏览器登录不要求播放也使用浏览器。Electron、CEF 或无头 Chromium 仍包含浏览器引擎，不属于这里讨论的原生后端。

Windows x64 下一步需要查明真实许可证 HTTP 403 的兼容性原因，在请求成功后验证实际解密、出声、暂停、跳转、切歌、会话失效与退出清理。
成功后再逐一验证 Windows ARM64、Linux 和 macOS；保留现有 WebView2 后端以便回退。
对照测试应使用同一设备、曲目、音质、缓存状态和网络，统计所有子进程的内存/CPU、首帧音频延迟和连续播放耗电。

## 资料

- [Widevine 官方概览与许可](https://developers.google.com/widevine/drm/overview)
- [Chromium CDM 宿主文件验证](https://github.com/chromium/chromium/blob/main/media/cdm/cdm_host_files.cc)
- [Android Media3 DRM 文档](https://developer.android.com/media/media3/exoplayer/drm)
- [Microsoft PlayReady 概览](https://learn.microsoft.com/en-us/playready/overview/overview)
- [Kodi InputStream Adaptive](https://github.com/xbmc/inputstream.adaptive)
- [InputStream Helper 的 Widevine 组件查询实现](https://github.com/emilsvennesson/script.module.inputstreamhelper/blob/master/lib/inputstreamhelper/widevine/repo.py)
