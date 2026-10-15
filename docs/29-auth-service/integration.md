# 第 29 轮 · 服务与 App 接入

## 仓库边界

- App：`Agentic-KeepKeep`，分支 `feat/account-auth-service`。
- 独立服务：`/zhangaimin/Agentic-KeepKeep/Moveliq-Service`，同名功能分支。源码、迁移、测试、Docker 和服务 README 均位于该仓库。
- GitHub 私有仓库 [MinJung-Go/Moveliq-Service](https://github.com/MinJung-Go/Moveliq-Service) 已创建；服务分支首推 `cb2b880`。App 分支已推送，`e0cc02c` 通过 Apple 构建与 429 项单测，详见 checklist。

## 接入顺序

1. 按服务仓库 README 配置 PostgreSQL，执行迁移，生成首个种子邀请码。
2. 配置服务端 `LLM_BASE_URL`、`LLM_API_KEY`、`LLM_MODEL`；如需搜索，配置 `SEARCH_ENABLED=true` 与智谱搜索密钥。
3. 部署 HTTPS 服务：Vercel 或带 HTTPS 反向代理的自有服务器，验证 `/health`。
4. 第 31 轮起 App 默认接入 `https://moveliq.work/api`，移除临时 IP HTTP 例外，端点仅允许 HTTPS。可用 `MOVELIQ_SERVICE_URL` 覆盖，不要包含 `/v1`；实时地址自动转换为 WSS。
5. GitHub App 仓库 Actions Variables 设置同名 `MOVELIQ_SERVICE_URL`；CI 将其传给 build/test/archive。它是公开地址，不是密钥。
6. 重新构建 App，邀请码注册→登录→记录解析→对话流式→搜索→退出并恢复登录。

```bash
xcodegen generate
xcodebuild build -project AgenticKeepKeep.xcodeproj -scheme AgenticKeepKeep \
  -destination 'generic/platform=iOS Simulator' \
  MOVELIQ_SERVICE_URL=https://your-service.example.com CODE_SIGNING_ALLOWED=NO
```

默认服务地址为 `https://moveliq.work/api`；GitHub Actions 未配置变量时使用相同默认值。其他未配置／不允许的地址显示明确错误，不会回退到旧 BYOK、本地模型或明文 HTTP。旧安装包不会自动改地址；新地址需要重新登录，旧本地账户数据按原地址保留，不自动合并。实施与验证见[第 31 轮清单](../31-domain-https/checklist.md)。

## 认证协议

| 接口 | 请求／响应 |
|---|---|
| `POST /v1/auth/register` | `{username,password,inviteCode}` → `{user:{id,username},token,expiresAt}` |
| `POST /v1/auth/login` | `{username,password}` → 同上 |
| `GET /v1/auth/me` | Bearer → `{user}` |
| `POST /v1/auth/logout` | Bearer → 204，撤销当前会话 |
| `GET /v1/invites` | Bearer → `{invites:[{id,code,status}]}`；已用码的 code 为 null |
| `GET /v1/config` | Bearer → `{model,contextWindow,maxOutput,searchEnabled,supportContact}` |
| `POST /v1/chat/completions` | Bearer，OpenAI 兼容 JSON／SSE，模型由服务端固定 |
| `POST /v1/web_search`、`POST /v1/reader` | Bearer，服务端智谱搜索／阅读适配 |

会话有效期 30 天，到期重新登录，无刷新令牌。App 将会话与服务地址绑定保存到 Keychain；启动在线校验，网络失败可重试；401 撤销本地登录并显示入口。退出先在本机锁定再尝试服务端撤销；离线退出不能保证服务端收到撤销，管理员仍可禁用／重置以撤销旧会话。

## 数据与迁移

SwiftData 以服务地址＋用户 ID 的 SHA256 为账号目录标识。旧数据库在用户明确确认后绑定，不搬动文件；账号之间隔离数据库、Milo 个人偏好、用量和引导状态。退出保留记录、取消模型请求、请求 Widget 刷新；Widget 只在本机会话未到期且 App Group 可用时读取当前库。Widget 刷新由系统调度，真机需验收缓存画面更新时机。

HealthKit 的系统权限属于设备，不属于服务账号；其他账号仍可能主动导入设备健康数据。当前不做健康数据云同步、账号删除、自助改密或密码恢复。

本地模型通过 `LocalModelAvailability.enabled = false` 停用；启动只重新连接旧下载任务以取消，不恢复下载、不实例化推理引擎，不删除已下载权重。恢复不能仅把标志置 true，还需恢复请求路由和入口并回归验证。

## 验证边界

本地可运行 `python3 scripts/test_auth_portable.py`（需 Swift 5.9+）验证输入、协议与个人偏好隔离。服务测试在独立仓库运行 `npm test`。本地 Linux 语法检查不替代 Apple 编译；远程 iOS CI 已通过（`e0cc02c`，429 项单测），SwiftData／Keychain／Widget 与后台下载真机验收见 checklist。

## 自有服务器部署记录（2026-09-22）

- 服务器 `47.100.234.212`，部署目录 `/opt/moveliq-service`，服务版本 `cb2b880`。
- Docker Compose 独立项目 `moveliq`：API＋PostgreSQL 17，持久卷 `moveliq_database`，自动重启；未更改现有 Harbor／Portainer／反向代理。
- 按用户要求发布 `0.0.0.0:8080`，公网地址 `http://47.100.234.212:8080`；已从服务器外验证 `/health` 返回 HTTP 200 和 `{"ok":true}`。未登录访问受保护接口返回 401；HTTPS 尚未配置，App 已适配此临时 HTTP 地址。
- 随机数据库凭据只在服务器 `.env`；初始种子邀请码位于服务器 `bootstrap-invite.txt`，均为 600 权限，不入 Git。
- 在独立测试库运行真实 PostgreSQL 多连接回归，**9/9 通过**；测试库随后删除，生产库没有测试账号。
- GLM Key 已配置于服务器 `.env`（600 权限），模型为 `glm-5.3-flash`，真实文本调用返回 200／OK；没有将 Key 写入源码、日志或 Git。可选检索未开启，HTTPS 和真机 App 联调待完成。
- 服务器运维说明：`/opt/moveliq-service/OPERATIONS.md`；测试日志：`validation-2026-09-22.log`。
