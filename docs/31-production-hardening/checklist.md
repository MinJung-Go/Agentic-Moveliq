# 第 31 轮清单

- [x] 需求与实施范围；无 UI 变动，沿用当前分支。
- [x] 统一验证服务地址，支持 HTTPS /api 与 WSS；RealtimeCall 复用同一 URL 策略。
- [x] 地址策略边界及路径测试：HTTP 例外、HTTPS /api、尾斜杠、WSS、非法凭据/查询/fragment/路径穿越。
- [x] 文档记录构建变量和切换后账号/本地数据隔离行为；默认 project.yml/CI 地址暂未切换。
- [x] Linux Swift 6.0.3 临时包：AuthPolicyTests 9/9 通过；RealtimeCall.swift 语法解析通过。不代表 iOS 音频/UI 真机验证。
- [x] iOS CI：487/487 单测，Apple 音频转换检查 28/28。
- [x] IPA 产出及包内版本/地址核验：0.5.13（34）、http://47.100.234.212:8080，ZIP 完整性通过。
- [ ] HTTPS 登录、SSE、WSS 真机验收。

CI 提交号：6c0fc1948eff4dae43fd5e6c44af024dcbe1adcb；[本次工作流](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/37574689044) 的 iOS 构建和 487 项单测、28 项 Apple 音频检查通过。本地账号/地址策略单测另有 9 项，日志 /tmp/moveliq-endpoint-check.log。

Service 在 master 完成共享租约、Nginx 与双副本模板；PGlite/真实 PostgreSQL 各 59 项、实际 Nginx 代理 15 项、Compose 配置校验通过。独立 Service 的具体范围与现场待办见其 docs/03-production-hardening/checklist.md。

## 用户授权交付（2026-10-07）

用户要求提交、push、部署云端与 IPA。版本提升为 0.5.13（34）。域名公网 HTTP 返回 403，HTTPS 连接被重置，服务器无受信任的 moveliq.work 证书；80/443 已由既有 Nginx Proxy Manager 占用。本次新 IPA 沿用 http://47.100.234.212:8080，避免改到不可用域名；服务部署共享租约与双副本，由独立 Nginx 在 8080 提供兼容入口。既有 80/443 服务保持运行，域名 HTTPS 切换另行验收。

- [x] App 功能提交与 push：6c0fc19，feat/milo-voice-chat。
- [x] iOS CI、IPA 产出及包内版本/地址核验；工作流全部成功。
- [x] Service master 已推送至 f726800；云端同镜像 d7b4337 双副本及 Nginx 8080 健康，复用原 PostgreSQL 数据卷。PostgreSQL 17 隔离库 59/59，生产真实 GLM SSE/150 秒实时音频联调通过；原账号、邀请码、模型配置与管理员密码保留。
- [x] 按追加授权清理一个停止的旧 API 容器和 10 个旧服务镜像；保留当前和上一版回退镜像、数据库卷及其他服务。

IPA：[KeepKeep-unsigned-ipa](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/37574689044/artifacts/11463280796)，功能提交 6c0fc19。IPA 大小 8,818,383 字节；SHA256 `8f151adc3e2492e180da2d7c3334fa83b19019bc71fb4e483a15587200d6b80a`。标准 gh 下载后读取 Info.plist 并核验版本/服务地址；需侧载重签名。域名 HTTPS 与 App 麦克风/相机真机验收仍未完成。
