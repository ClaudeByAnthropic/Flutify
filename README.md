<div align="center">

<img src="assets/brand/flutify_logo_1024.png" width="112" alt="Flutify" />

# Flutify

一个让你呼吸通畅的 Spotify 第三方客户端 · Windows / Android

[下载](../../releases) · 当前版本 **v0.01 Beta**

</div>

---

## ✨ 功能

**听歌**
- 在应用内的 Spotify 官方登录页登录一次即可，其余授权自动完成，浏览主页、搜索、歌单、专辑、艺人
- 完整曲目播放，边下边播，听过的歌自动缓存
- 双层播放队列（手动添加 + 来自歌单），随机 / 列表循环 / 单曲循环
- 音量均衡、歌曲间淡入淡出，重启后从上次的进度继续

**歌词**
- 逐行同步歌词，Apple Music 风格的流动背景与液态玻璃
- 官方没有同步歌词时，自动从 [LRCLIB](https://lrclib.net) 补全
- 桌面沉浸式歌词（F11）
- Windows 任务栏歌词：嵌在任务栏里，不需要额外软件

**Spotify Connect**
- 遥控同账号的其他设备（手机、电脑、音箱），也能把播放转到本机
- 本机会出现在其他设备的设备列表里，可以被遥控，播放状态双向同步
- 设备名称可自定义

**外观与体验**
- Material 3 Expressive 设计，深 / 浅色，纯黑背景，强调色可跟随封面
- 桌面三栏布局，窗口变窄自动切换为手机布局
- 系统媒体控制（任务栏 / 锁屏 / 通知栏）、键盘媒体键与快捷键
- 简体中文 / English，内置 MiSans 字体
- 支持 HTTP 代理（跟随系统或手动设置）

## 📦 安装

从 [Releases](../../releases) 下载：

| 平台 | 文件 | 说明 |
|---|---|---|
| Windows 10 / 11 | `windows-x64.zip` | 解压后运行 `Flutify.exe`。需要 WebView2 运行时（Win11 自带） |
| Android | `android-arm64-v8a.apk` | 绝大多数手机选这个；不确定就选 `universal` |

首次使用：设置 → 账号 →「登录」，在弹出的 Spotify 官方登录页里登录即可。

## 🧪 Beta 已知问题

- Android 端还在适配中，部分功能（如全曲播放、Connect 播放端）可能不可用
- 偶尔遇到播放限流（HTTP 429），稍等片刻再试即可
- 只支持 OGG / MP3 音源，免费账号功能以 Spotify 实际允许的为准

有问题欢迎提 [Issue](../../issues)。

## ⚠️ 免责声明

- 本项目是非官方第三方客户端，**与 Spotify AB 没有任何关联**，Spotify 是 Spotify AB 的注册商标。
- 本项目仅供学习与研究交流使用。使用第三方客户端可能违反 Spotify 服务条款，**存在账号被限制的风险，建议使用小号**，后果由使用者自行承担。
- 本项目不提供、不存储任何音乐内容，所有内容均来自用户自己的 Spotify 账号。
- 请支持正版，订阅 Spotify Premium。

## 📄 许可证

[MIT License](LICENSE)。随附的第三方组件遵循各自的许可证，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

开发相关文档见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 🙏 致谢

感谢 <a href="https://linux.do">LINUX DO</a> 社区。
