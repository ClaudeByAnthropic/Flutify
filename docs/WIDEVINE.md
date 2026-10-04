# 原生 Widevine 播放跨平台评估

核对日期：2026-10-04。Android 使用原生 Media3 / MediaDrm；Windows x64 已接入实验性的原生 CDM 解密与音频播放管线，但真实许可证请求返回 HTTP 403，尚未证明原生曲目能够解密出声。Windows 默认仍使用 WebView2，实验模式失败时也保留该回退。

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
- [Android Media3 DRM 文档](https://developer.android.com/media/media3/exoplayer/drm)
- [Microsoft PlayReady 概览](https://learn.microsoft.com/en-us/playready/overview/overview)
- [Kodi InputStream Adaptive](https://github.com/xbmc/inputstream.adaptive)
- [InputStream Helper 的 Widevine 组件查询实现](https://github.com/emilsvennesson/script.module.inputstreamhelper/blob/master/lib/inputstreamhelper/widevine/repo.py)
