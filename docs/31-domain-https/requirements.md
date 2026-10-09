# App 切换已备案域名

2026-10-09 配合用户授权的 moveliq.work 云端 HTTPS/WSS 上线，在当前 feat/milo-voice-chat 分支实施；无 UI 变动。

默认服务地址改为 https://moveliq.work/api，同步 project.yml、GitHub Actions 默认值和仓库变量，移除 Info.plist HTTP 例外及端点白名单。登录、模型请求和实时通话共用端点，HTTPS 自动转 WSS。保留 URL 安全校验及现有账户隔离，不自动把旧 IP 的本地记录绑定新服务；用户需重新登录，历史记录保留。执行可移植鉴权测试和 Apple CI，记录实际结果；设备收音、摄像头与 IPv6-only 网络仍需实际装机验证。
