# Android 系统媒体控制排查

反馈：vivo 手机使用 v0.03-beta，有播放通知，但上一首、下一首、暂停按钮和进度条缺失。具体手机型号和系统版本尚未提供，未在反馈设备复现。

## 已确认的问题及修复

- 从 GitHub 下载已发布的 `Flutify-v0.03-beta-android-arm64-v8a.apk`，检查 `resources.arsc`：`audio_service_play_arrow`、`audio_service_pause`、`audio_service_skip_previous`、`audio_service_skip_next`、`audio_service_stop` 名称均不存在。audio_service 0.18.19 在原生代码中使用 `getIdentifier` 按名称加载这些图标。新增 `res/raw/keep.xml` 保留资源，并使用独立的单色通知图标。
- `MediaControlsSync` 原来仅按曲目 ID 更新元数据。若初始时长为 0，解码器后来得到实际时长，系统仍收到 0，无法形成有效时间线。现在同时比较时长、标题、专辑和封面，并使用播放器更新后的时长。
- 为暂停和缓冲上报速度 0，正常播放上报 1；进度变化检测也在缓冲时停止外推。
- 显式声明 MediaSession 的播放、暂停、切换、跳转和可用的上一首／下一首操作，保留旧版通知的紧凑按钮。插件本身已把通知关联到 MediaSession，且会将通知按钮合入原生 actions；显式声明便于验证两种展示路径，并非单独证明 vivo 根因。
- 修复 Connect 队列扩展与完整歌单分页，使“下一首”的可用性反映实际队列。

## 验证

自动测试覆盖 AudioHandler → MediaControlsSync → PlaybackProvider 的播放、暂停、上一首、下一首和 seek；包括未知时长补全、越界 seek、列表末尾禁用下一首、缓冲恢复。GitHub 构建对四个 Release APK 检查媒体图标、固定签名和 versionCode。

收到新版后，在反馈 vivo 设备上验证：播放有后续曲目的歌单，展开通知并查看锁屏控制；暂停／恢复，切换前后曲目，拖动进度；熄屏后重复操作。若仍缺失，用 `adb shell dumpsys media_session` 检查 Flutify 会话的 active、actions、state、position、speed 与 metadata duration。回传前去掉其他应用会话和个人曲目信息。

按钮缺失与发布资源裁剪吻合；仍需实机确认是否还有 OEM 展示策略差异。
