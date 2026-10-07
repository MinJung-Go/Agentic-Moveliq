# 第 31 轮清单

- [x] 需求与实施范围；无 UI 变动，沿用当前分支。
- [x] 统一验证服务地址，支持 HTTPS /api 与 WSS；RealtimeCall 复用同一 URL 策略。
- [x] 地址策略边界及路径测试：HTTP 例外、HTTPS /api、尾斜杠、WSS、非法凭据/查询/fragment/路径穿越。
- [x] 文档记录构建变量和切换后账号/本地数据隔离行为；默认 project.yml/CI 地址暂未切换。
- [x] Linux Swift 6.0.3 临时包：AuthPolicyTests 9/9 通过；RealtimeCall.swift 语法解析通过。不代表 iOS 音频/UI 真机验证。
- [ ] iOS CI 与 IPA（未提交，不触发）。
- [ ] HTTPS 登录、SSE、WSS 真机验收。

CI 提交号：尚无本轮提交；本地账号/地址策略单测 9 项通过，日志 /tmp/moveliq-endpoint-check.log。

Service 在 master 完成共享租约、Nginx 与双副本模板；PGlite/真实 PostgreSQL 各 59 项、实际 Nginx 代理 15 项、Compose 配置校验通过。独立 Service 的具体范围与现场待办见其 docs/03-production-hardening/checklist.md。

## 用户授权交付（2026-10-07）

用户要求提交、push、部署云端与 IPA。版本提升为 0.5.13（34）。域名公网 HTTP 返回 403，HTTPS 连接被重置，服务器无受信任的 moveliq.work 证书；80/443 已由既有 Nginx Proxy Manager 占用。本次新 IPA 沿用 http://47.100.234.212:8080，避免改到不可用域名；服务部署共享租约与双副本，由独立 Nginx 在 8080 提供兼容入口。既有 80/443 服务保持运行，域名 HTTPS 切换另行验收。

- [ ] App 功能提交与 push。
- [ ] iOS CI、IPA 产出及包内版本/地址核验。
- [ ] 记录 Service 生产部署与公网联调结果。
