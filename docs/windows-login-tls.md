# Windows 登录时证书校验失败

表现：WebView 已收到 OAuth 授权回调，但 Web token 和桌面令牌请求报
`CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`。
回调成功只表示取得授权码，不代表令牌交换已经成功。

Windows 上 Dart 的默认信任库使用内置 CA，WebView2 使用系统信任设置。
因此，部分机器使用系统已信任的企业代理或 HTTPS 检查软件时，可能出现
网页正常、Dart HTTPS 请求失败的差异。本地未复现时，这只是可能原因，
截图本身不能证明反馈用户的实际证书链或代理配置。

应用启动时通过 Windows CryptoAPI 读取逻辑 ROOT 存储，将通过本机链验证
且允许服务器认证的根证书补充到 Dart 默认 SecurityContext。
不导入个人证书或中间证书存储，不安装证书，不绕过 TLS 校验。
读取失败时保留 Dart 原有信任库；显式创建的自定义 SecurityContext 不受影响。
系统信任库变更后需重启应用。

回归测试使用本地测试证书验证：未信任时拒绝连接，加载根证书后成功，
主机名不匹配仍被拒绝，回环连接继续绕过代理。

反馈用户仍需用新构建复测。如果仍失败，可收集应用日志中的 `[TLS]` 行、
系统版本、应用代理模式及是否启用 HTTPS 检查；不要收集 Cookie 或令牌。
此修复不补全服务器漏发的中间证书，也不会信任系统本身未信任的证书。
