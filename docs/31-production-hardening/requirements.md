# 第 31 轮 · HTTPS 生产入口适配

用户授权按照 Moveliq-Service README 生产加固待办开发，Service 使用 master，App 保持当前分支。无界面改动。

- 配合 Nginx 支持 https://moveliq.work/api，登录/配置/聊天路径为 /api/v1/...，实时为 wss://moveliq.work/api/v1/realtime。
- HTTP 仍只允许 http://47.100.234.212:8080；HTTPS 不允许内嵌账号密码、查询或 fragment，拒绝路径穿越、非法 URL 及跨来源路径。
- 服务地址由打包时 MOVELIQ_SERVICE_URL 决定；HTTPS 实际验收前保留默认 IP 地址，不宣称现有装机版本已迁移。
- 切换服务地址仍遵守 Keychain 与 SwiftData 按地址隔离的既有约定，重新登录；不自动将旧记录绑定到新地址。
- 测试 HTTPS 前缀、根路径、尾斜杠、WSS 拼接和 HTTP 例外边界；无 Mac 环境仅报告纯 Swift 验证，iOS CI 与真机另行执行。

服务端需求与部署说明在独立仓库 docs/03-production-hardening/。
