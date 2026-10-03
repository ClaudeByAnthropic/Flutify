# 构建与固定签名

工作流：`.github/workflows/build.yml`。推送 `main` 或手动运行生成 Actions 产物；推送 `v*` 标签在所有构建成功后发布 Release。包含 `alpha`、`beta` 或 `rc` 的标签标为预发布。

## Android

所有 release APK 必须使用同一把 beta 密钥；缺失配置时直接失败，不回退到 debug 签名。调试构建不需要 release 密钥。

仓库已配置下列 Actions Secrets：

| Secret | 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | JKS 文件的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | JKS 密码 |
| `ANDROID_KEY_ALIAS` | 签名别名 |
| `ANDROID_KEY_PASSWORD` | 私钥密码 |
| `ANDROID_SIGNING_CERT_SHA256` | 构建后验证的证书指纹 |

固定 beta 证书 SHA-256：

```text
f342b46d13f500863b6ed4987ae78e5e57d6f8f53690e6e79fa33f17871f2715
```

此次创建的本机备份是仓库目录下的 `.signing/flutify-beta.jks` 和 `.signing/signing.json`。后者包含密码；两者均被 Git 忽略，必须一起保存到可靠的私密备份中。GitHub Secrets 不能导出原值。不要重新生成或轮换密钥来处理普通构建故障。

此前 beta 的旧密钥没有备份，因此旧签名不同的安装需要卸载后安装一次。从这把固定密钥签署的版本开始，后续版本可覆盖升级。

本地 release 构建可以配置环境变量 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`；也可以在已被忽略的 `android/key.properties` 中设置 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`。`storeFile` 相对 `android/` 解析，或使用绝对路径；Windows 属性文件中的路径建议使用 `/`。

工作流临时解码密钥，完成后无论成功失败均删除临时文件。每次构建输出通用包及 armeabi-v7a、arm64-v8a、x86_64 三个拆分包。`tool/verify_android_apks.py` 用 `apksigner` 验证全部四个包的签名和固定指纹，用 `aapt` 检查 versionCode 和媒体通知图标资源，并输出 APK SHA-256。

基础 versionCode 为 `(100 + GITHUB_RUN_NUMBER) * 10000 + GITHUB_RUN_ATTEMPT`。Flutter 为三个拆分包分别增加 1000、2000、4000；批次间隔确保下一批通用包的版本号也高于上一批拆分包。同一运行重试增加 attempt；重跑较早运行不会成为较新发布版本的升级包。

## Windows x64 与 ARM64

工作流分别使用 `windows-latest` 和 `windows-11-arm` runner，生成 `windows-x64`、`windows-arm64` 两份独立产物。打包前使用 `tool/verify_windows_arch.py` 检查所有 EXE/DLL 的 PE 架构，包括 libmpv，防止把 x64 依赖装入 ARM64 包。

Flutter 固定为 3.44.0。官方发布清单没有该版本的整套 Windows ARM64 SDK ZIP，所以 ARM64 runner 从官方 Flutter 仓库的 3.44.0 标签启动，校验提交 `559ffa3f75e7402d65a8def9c28389a9b2e6fe42`，再由官方启动脚本下载原生 ARM64 Dart。工作流同时验证 runner 和 Dart 架构；Flutter 根据宿主 Dart 架构选择 Windows 构建目标。

上游 `media_kit_libs_windows_audio` 包只提供 x64 下载配置，因此 `packages/media_kit_libs_windows_audio/` 保留一份 MIT 授权的 CMake 适配，分别下载并校验 x64／ARM64 libmpv。来源、版本、许可证见该目录 README 和根目录 `THIRD_PARTY_NOTICES.md`。Windows ZIP 附带项目许可证和第三方声明。

本地 x64 构建成功不能替代 ARM64 runner 或 Android CI 验证；CI 构建成功也不能替代真机登录、DRM 播放、媒体键和 WebView 检查。
