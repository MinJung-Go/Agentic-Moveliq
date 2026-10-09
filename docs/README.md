# 文档目录

按「轮次」组织：每一轮（一次需求交付，或一轮反馈修复）一个文件夹，文件夹内自带该轮的需求、实施清单与设计稿。

第 31 轮：HTTPS /api 与 WSS 生产入口适配，配合独立 Service 的 Nginx、共享租约及双副本部署。[需求](31-production-hardening/requirements.md) · [清单](31-production-hardening/checklist.md)。默认 IP 暂时保留，生产切换与 IPA 尚未执行。

| 轮次 | 主题 | 文档 |
|------|------|------|
| 01-foundation | 项目基线：P0/P1/P2 全量实现 | [需求](01-foundation/requirements.md) · [清单](01-foundation/checklist.md) · [设计稿](01-foundation/design.html) |
| 02-device-feedback | 真机反馈修复（bug 修复轮） | [清单](02-device-feedback/checklist.md) |
| 03-coach-streaming | 教练综合个人数据 + 流式回复 + 图片与文字同发 | [需求](03-coach-streaming/requirements.md) · [清单](03-coach-streaming/checklist.md) |
| 04-ui-polish | 界面与交互重做（设计系统 v2）+ 修复思考内容不展示 + 动作指导示意图 | [需求](04-ui-polish/requirements.md) · [设计系统](04-ui-polish/design-system.md) · [清单](04-ui-polish/checklist.md) · [设计稿](04-ui-polish/design.html) · [动作示意图稿](04-ui-polish/exercise-illustrations.html) |
| 05-workout-session | 训练执行页：跟着计划练、逐组打勾、练完自动成记录 | [需求](05-workout-session/requirements.md) · [清单](05-workout-session/checklist.md) |
| 06-ui-feedback | 计划确认回执、离线姿势图、输入栏与 App 图标 | [需求](06-ui-feedback/requirements.md) · [清单](06-ui-feedback/checklist.md) |
| 07-photo-entry | 首页图文记录与一次发送 | [清单](07-photo-entry/checklist.md) |
| 08-coach-context | AI 教练超长上下文管理 | [需求](08-coach-context/requirements.md) · [清单](08-coach-context/checklist.md) |
| 09-ui-refinement | UI 专项：操作可见性、首页层级、对比、教练卡片与图表 | [需求](09-ui-refinement/requirements.md) · [清单](09-ui-refinement/checklist.md) · [新版 HTML](09-ui-refinement/design.html) · [Figma 主稿](09-ui-refinement/figma.md) |
| 10-healthkit-sideload | HealthKit 侧载签名声明与授权重试修复 | [清单](10-healthkit-sideload/checklist.md) |
| 20-mlx-validation | MLX Swift 独立验证 App | [需求](20-mlx-validation/requirements.md) · [清单](20-mlx-validation/checklist.md) · [设计稿](20-mlx-validation/design.html) · [验证说明](20-mlx-validation/validation.md) |
| 21-mlx-production | 正式 App 迁移 MLX，含图文 | [需求](21-mlx-production/requirements.md) · [清单](21-mlx-production/checklist.md) |

## 候选需求（尚未立轮次）

记录在这里免得丢，**不是承诺**。真要开工时按约定先写 `requirements.md` 并确认。

（暂无；已立项轮次见上表。）

## 约定

### 文件夹

- 命名 `NN-<slug>`：`NN` 为两位递增序号，`slug` 用英文短横线（如 `04-social-sharing`）
- 一轮一个文件夹，该轮的所有文档都放进去

### 每轮必备

| 文件 | 何时需要 | 内容 |
|------|---------|------|
| `requirements.md` | **除纯 bug 修复轮外都必须有** | 背景与目标、功能需求（带验收标准）、非功能需求、明确不做的范围 |
| `checklist.md` | 每轮都要 | 实施项与验证结果：逐条对应需求、标注 CI 提交号与单测数量、记录真机复验要点 |

### 可选

| 文件 | 说明 |
|------|------|
| `design.html` / `design.*` | 高保真稿、线框或真机截图，与本轮需求放在一起 |
| `design-system.md` | 改版视觉语言时，用 DESIGN.md 格式写 token 规范；**代码实现以它为准**，跨轮次沿用 |

### 流程

1. 先写 `requirements.md`，与用户确认后再动手（**需求先于实现**）
2. 实现过程中需求有变化，同步更新需求文档，不要只改代码
3. 每批实现推送后等 CI 绿，检查项与验证记录写进 `checklist.md`
4. 纯 bug 修复轮可以跳过需求文档，但 `checklist.md` 里要逐条写清：现象、根因、修复方式、验证结果

## 相关

- 项目说明、安装与已知限制：[README](../README.md)
- 开发约定（构建链路、架构决策、工作流）：[CLAUDE.md](../CLAUDE.md)

## 第 11 轮

[教练工具、课程表管理与外观需求](11-coach-query-tools/requirements.md) · [开发清单](11-coach-query-tools/checklist.md)

- [12 · 课程表动作详情与误删修复](12-plan-detail-fix/checklist.md)

## 第 14 轮（合并原第 14、15、16 轮）

Milo 体验：推理速度、工具进度、搜索扩展、网页阅读与角色/UI 设计。暂不需要同步 Figma。

[需求](14-coach-speed/requirements.md) · [清单](14-coach-speed/checklist.md) · [本地设计稿](14-coach-speed/design.html) · [首页记录栏预览](14-coach-speed/preview-home-record.png)

## 第 17 轮（需求讨论中）

Milo 运动伙伴：先记录可选择的角色与相处方式，默认大姐姐、可选大哥哥，后续需求继续追加。尚未开发。

[需求](17-milo-companion/requirements.md) · [清单](17-milo-companion/checklist.md)

## 第 18 轮（需求与设计提案）

Moveliq 品牌统一、Milo 默认首页与统一记录／聊天入口。

[需求](18-milo-home/requirements.md) · [清单](18-milo-home/checklist.md) · [四屏交互稿](18-milo-home/design.html)

## 第 19 轮（实现与验证中）

离线 Milo：验证 Qwen 图文小模型（当前候选 Qwen3.5-2B）的 iPhone 本地推理、图文记录、工具调用、模型下载及 App 内置浏览器搜索／阅读方案。现有 GLM 保留；本地运行时、下载、图文和浏览器已接入，Linux 模型冒烟与纯 Swift 测试已执行，iOS CI／真机和完整质量评测待完成。设计短片已放到 README 顶部。

[需求](19-local-milo/requirements.md) · [验证清单](19-local-milo/checklist.md) · [下载 UI](19-local-milo/design.html)

## 第 23 轮 · 本地上下文分阶段扩容

默认 16K；32K 待真机验证及选择入口设计确认后开放。[需求](23-local-context/requirements.md) · [清单](23-local-context/checklist.md)。

## 第 24 轮 · 推理核心独立包

[需求](24-inference-package/requirements.md) · [清单](24-inference-package/checklist.md) · [私有包接入说明](24-inference-package/integration.md)。

## 第 25 轮 · 记录 JSON 解析回归

纯文字／照片记录格式恢复与安全错误诊断。[需求](25-record-json/requirements.md) · [清单](25-record-json/checklist.md)。

## 第 26 轮 · 本地输出上限 2048

本地模型输出上限由 1024 提升至 2048 tokens，教练策略与引擎预算随动。[需求](26-output-2048/requirements.md) · [清单](26-output-2048/checklist.md)。

## 第 27 轮 · 本地思考模式与撞顶保护

本地思考接入「深度思考」开关（默认开），思考超子预算即中止并自动降级重试。[需求](27-local-thinking/requirements.md) · [清单](27-local-thinking/checklist.md)。

## 第 28 轮 · 推理迁移遗留清理

删除旧 llama.cpp 桥接与工具，更新当前构建说明；历史轮次的旧运行时命令仅供追溯，不再作为现行入口。[需求](28-inference-cleanup/requirements.md) · [清单](28-inference-cleanup/checklist.md)。

## 第 29 轮 · 独立鉴权服务与 App 登录（需求整理中）

停用本地模型，独立鉴权与模型代理服务；用户名密码登录、邀请码注册，每次注册后发放 3 个子邀请码并逐层延续。[需求](29-auth-service/requirements.md) · [清单](29-auth-service/checklist.md)。

## 第 30 轮 · Milo 语音与 GLM 实时通话

原连续语音已交付 0.5.6；新增 GLM 实时语音／可选视频 UI 已确认，App 与 Service 接入中。[交互稿](30-milo-voice-chat/design.html)。[需求](30-milo-voice-chat/requirements.md) · [清单](30-milo-voice-chat/checklist.md)。

## 第 31 轮 · 已备案域名 HTTPS/WSS

App 默认连接 https://moveliq.work/api，移除 HTTP 放行；服务端独立部署。[需求](31-domain-https/requirements.md) · [清单](31-domain-https/checklist.md)。
