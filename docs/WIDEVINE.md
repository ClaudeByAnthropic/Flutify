# 原生 Widevine 播放跨平台评估

核对日期：2026-10-03。本文记录可复用范围与待验证条件；当前正式接入的原生播放后端是 Android。

## PR #1 的实现

[PR #1](https://github.com/is-hp-is-mad/Flutify/pull/1) 使用 Android Media3 ExoPlayer，通过 `C.WIDEVINE_UUID` 和 `FrameworkMediaDrm.DEFAULT_PROVIDER` 调用系统提供的 Widevine CDM。
入口在 `android/app/src/main/kotlin/com/flutify/music/flutify_app/NativeDrmPlugin.kt`；Dart 侧通过 `lib/services/eme/native_drm_audio_engine.dart` 调用它，沿用本机媒体与许可证转发服务。

它没有实现一套可移植的 Widevine 解密算法。认证、曲目地址、加密媒体缓存、许可证请求转发及 Flutter 播放状态可以复用；Android 的 MediaDrm、Media3 和 Kotlin 平台插件需要替换为目标平台的播放器/CDM 接口。

## 除 iOS 外的平台

| 平台 | 无浏览器播放的候选方式 | 目前结论 |
| --- | --- | --- |
| Android | Media3 + 系统 MediaDrm/Widevine | 已接入；仍需覆盖不同厂商设备和媒体通知行为 |
| Windows x64 / ARM64 | 原生宿主加载对应架构的 Widevine CDM，再接解复用、音频解码和输出 | 有对应架构组件；Flutify 尚未实现或验证该宿主 |
| Linux x64 / ARM64 | 原生 CDM 宿主 + 媒体管线 | 有对应架构组件；仍需验证宿主、发行版及许可证兼容性 |
| macOS x64 / ARM64 | 原生 CDM 宿主 + 音频管线，处理签名与分发 | 有对应架构组件；尚未验证 Flutify 的可用性 |

本次只查询 Google 组件更新服务的元数据，没有下载、执行或分发 CDM。查询返回 Windows x64/ARM64、Linux x64、macOS x64 为 `4.10.3050.0`，Linux ARM64 为 `4.10.3057.0`，macOS ARM64 为 `4.10.3112.0`。
这表明不能把 ARM64 简单判为“没有 CDM”；元数据可用不证明宿主 ABI、服务端许可证策略和实际播放链路兼容，也不代表获得再分发许可。

[Kodi InputStream Adaptive](https://github.com/xbmc/inputstream.adaptive) 的 `WVCdmAdapter.cpp` / `media::CdmAdapter` 展示了浏览器之外托管 Widevine CDM 的工程方式，可用于研究接口与生命周期。
其代码使用 GPL 许可，移植到本项目时需要单独评估许可兼容性。Windows Media Foundation / PlayReady 也不是 Widevine 的直接替代品；只有内容服务提供匹配的 DRM 许可证与媒体格式时才适用。

Widevine 官方提供许可合作流程，并说明不收取 Widevine 产品/服务费用。接入与分发仍应依据其许可条件，不以提取密钥、绕过许可证或伪造设备认证作为实现方式。

## 资源占用与验证顺序

原生播放可以省去专为音频运行的浏览器渲染进程、JavaScript 与 MSE 管线，因此有望降低常驻内存、进程数量及启动开销。解密、解码、网络和音频输出仍然存在，CPU 与耗电收益需实测；不能仅凭架构给出降低百分比。
登录页仍可独立使用浏览器，浏览器登录不要求播放也使用浏览器。Electron、CEF 或无头 Chromium 仍包含浏览器引擎，不属于这里讨论的原生后端。

建议先验证 Windows x64：初始化受支持的 CDM、创建会话、走已有合法许可证请求、解复用加密音频、向音频输出交付解码数据，并覆盖暂停、跳转、切歌、会话失效与退出清理。
成功后再逐一验证 Windows ARM64、Linux 和 macOS；保留现有 WebView2 后端以便回退。
对照测试应使用同一设备、曲目、音质、缓存状态和网络，统计所有子进程的内存/CPU、首帧音频延迟和连续播放耗电。

## 资料

- [Widevine 官方概览与许可](https://developers.google.com/widevine/drm/overview)
- [Android Media3 DRM 文档](https://developer.android.com/media/media3/exoplayer/drm)
- [Microsoft PlayReady 概览](https://learn.microsoft.com/en-us/playready/overview/overview)
- [Kodi InputStream Adaptive](https://github.com/xbmc/inputstream.adaptive)
- [InputStream Helper 的 Widevine 组件查询实现](https://github.com/emilsvennesson/script.module.inputstreamhelper/blob/master/lib/inputstreamhelper/widevine/repo.py)
