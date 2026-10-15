<div align="center">

<img src="docs/18-milo-home/assets/milo.png" alt="Milo：淡蓝色小糯团，戴黄色手环" width="112">

<h1>Moveliq</h1>

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform](https://img.shields.io/badge/iOS-17%2B-blue.svg)
![Swift](https://img.shields.io/badge/SwiftUI%20%2B%20SwiftData-orange.svg)
[![iOS CI](https://github.com/MinJung-Go/Agentic-KeepKeep/actions/workflows/ios.yml/badge.svg)](https://github.com/MinJung-Go/Agentic-KeepKeep/actions/workflows/ios.yml)

**和运动伙伴 Milo 一起，用一句话记录训练与饮食，回顾身体状态，安排适合自己的训练。**

</div>

---

> 当前开发：语音输入与 GLM 实时通话；第 31 轮切换已备案域名 `https://moveliq.work/api`，旧安装版本地址不会自动更新。[0.5.14（35）HTTPS IPA](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/37917041170/artifacts/11610593869) 已构建并校验，需重签安装。进度和验证见 [域名切换清单](docs/31-domain-https/checklist.md)，服务接入见 [服务说明](docs/29-auth-service/integration.md)。

## 界面示意

[![Milo 本地图文与网页搜索设计演示](docs/19-local-milo/design-preview.gif)](docs/19-local-milo/design-video.mp4)

[观看 24 秒设计短片（MP4）](docs/19-local-milo/design-video.mp4) · [六屏交互设计稿](docs/19-local-milo/design.html)

> 以上为设计稿演示，非真机录屏。第 19 轮本地图文与浏览器功能正在验证，不能视为已通过 iPhone 性能或可用性验收。

Milo 是 Moveliq 的运动伙伴，默认出现在首页；称呼与相处方式可在设置中自定义。新版形象采用淡蓝小糯团、黄色手环与同色浅腹肌。

<p align="center">
  <img src="docs/18-milo-home/preview-milo-themes.png" alt="Milo 首页浅深色设计对照：左侧白底淡蓝角色，右侧炭黑背景与柔和蓝色角色，下方展示三种头像尺寸" width="900">
</p>

> 上图为 HTML 设计预览，非真机截图；训练与记录内容均为演示。新版 Milo、深色角色调色与背景适配已接入当前源码，已通过 0.4.10 (14) 的 iOS 编译与 353 项单测，真机效果待验收；请以对应构建的提交与版本为准。

[浅深色对照稿](docs/18-milo-home/design-milo-themes.html) · [四屏交互稿](docs/18-milo-home/design.html) · [设计需求](docs/18-milo-home/requirements.md) · [实施清单](docs/18-milo-home/checklist.md)

HTML 文件可下载后在浏览器打开；GitHub 文件页展示的是源码。

## 这个项目解决什么

现有健身应用（Keep、Apple Fitness+ 等）的记录依赖繁琐的点选表单，分析停留在静态图表，课程是固定模板。Moveliq 的差异：

| 维度 | 常见做法 | 本项目 |
|------|---------|--------|
| 记录方式 | 点选表单 | 自然语言一句话，LLM 结构化解析后由你确认 |
| 分析 | 静态图表 | AI 跨维度关联（训练 × 睡眠 × 饮食），主动指出平台期 |
| 课程表 | 固定模板课程 | 对话生成课程表，按完成情况与恢复状态调整 |
| 数据归属 | 厂商云 | 按账号隔离的本地 SwiftData，独立服务鉴权并代理 AI |

## 能做什么

- **自然语言记录**：「深蹲100kg 5×5」「中午吃了牛肉面」→ 解析成结构化记录；解析结果先过确认卡片，每个字段可改
- **失败不丢数据**：解析失败时原文存为「待归类」笔记，登录且服务恢复后可重新解析
- **AI 周报**：基于本地聚合摘要分析渐进超负荷、平台期、训练与睡眠/饮食的关联；报告标注 AI 依据
- **对话式课程表**：和 Milo 说明目标与器械，通过 function call 生成周期化计划，确认后写入；支持手动增删改，也支持让 Milo 提出减载/换动作建议
- **饮食分析**：日均热量与宏营养素、蛋白质目标缺口、每日热量图
- **照片估算热量**：拍一张食物照片，估算组成与热量（标注为 AI 估算，可修正）
- **健康数据接入**：HealthKit 只读同步睡眠、HRV、静息心率、步数与运动记录（含 Apple Watch 训练，按 UUID 去重）
- **趋势图表**：体重、动作估算 1RM、每周训练容量、睡眠
- **语音输入 / 桌面小组件 / JSON 数据导出**

## 安装与启动

### 方式一：下载未签名 IPA（不需要 Mac）

以下为历史本地模型版本；当前分支已停止本地模型下载与加载。历史版本使用 **Qwen3.5-0.8B MLX 4bit**：从 ModelScope 下载约 **645 MB**，保持原有角色、历史与工具流程。历史本地模型分支默认上下文已适配 **16K**（[扩容清单](docs/23-local-context/checklist.md)，尚未打包）；下方已发布的 0.5.1（22）仍为 8K。升级后需下载新模型；旧 2B 不会作为新版启用。[本轮修复与验证](docs/22-local-memory/checklist.md)。[下载 IPA · 0.5.1（22）](https://github.com/MinJung-Go/Agentic-KeepKeep/actions/runs/35483344157/artifacts/10596852788)：397 项 iOS 单测通过，Release 归档成功；L14 与工具／图文质量待同设备复测。下方为上一版本。

[MLX 正式接入 IPA · 0.5.0（21）](https://github.com/MinJung-Go/Agentic-KeepKeep/actions/runs/35380521646/artifacts/10562367633)：393 项 iOS 单测通过，正式 App 已接入 MLX 文字／单图推理与后台下载。默认从 ModelScope 下载约 1.74 GB 新模型，旧 GGUF 不兼容；图文真机性能与任务质量仍待验收。[需求与 checklist](docs/21-mlx-production/checklist.md) · [安装说明与验证边界](docs/21-mlx-production/validation.md)。

仓库自带 GitHub Actions 流水线，打 tag 会自动构建并产出未签名 IPA：

1. 打开 [Actions](https://github.com/MinJung-Go/Agentic-KeepKeep/actions/workflows/ios.yml) → 选择 `v*` tag 触发的运行 → 下载 `KeepKeep-unsigned-ipa`
2. 用 AltStore / Sideloadly 等工具自签安装到 iPhone（免费 Apple ID 需每 7 天重签）

> HealthKit 与小组件依赖最终签名中的能力授权。缺少权限时，其他记录与 AI 功能仍可使用。不能仅凭缺少 entitlement 判断必须购买开发者会员；重新签名后可在设置中重新授权。

### 方式二：从源码构建

需要 macOS + Xcode 16.4（Swift 6.1）或更新版本，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
git clone https://github.com/MinJung-Go/Agentic-KeepKeep.git
cd Agentic-KeepKeep
python3 scripts/verify_no_exercise_dataset.py AgenticKeepKeep  # 检查无旧动作数据集
xcodegen generate
open AgenticKeepKeep.xcodeproj
```

正式 App 通过 Swift Package Manager 链接 MLX Swift 0.31.3 / MLX Swift LM 2.31.3，首次构建会下载依赖；保留推理包依赖以便以后恢复，但本轮不再下载或加载模型权重。

`.xcodeproj` 由 `project.yml` 生成，不进版本库。在 Xcode 中选择自己的开发团队后即可运行到真机。

## 第一次使用

1. 当前 App 默认接入已部署的服务；自建服务可覆盖 `MOVELIQ_SERVICE_URL` 并重新构建（[接入说明](docs/29-auth-service/integration.md)）。
2. 打开 App，用用户名与密码登录；首次注册填写一次性邀请码，成功后获得 3 个子邀请码。
3. 若检测到旧记录，确认其账号归属后继续。完成欢迎与 HealthKit 可选授权引导；无需模型 API Key。
4. 在首页输入「深蹲100kg 5×5，有点累」→ 确认卡片 → 保存。邀请码在「设置 → 账号与邀请码」查看。

## 权限与数据

| 权限 | 用途 | 说明 |
|------|------|------|
| HealthKit（读） | 睡眠、HRV、静息心率、步数、运动记录 | 只读，不回写 HealthKit |
| 相机 / 相册 | 食物照片估算热量 | 照片随记录存本机 |
| 麦克风 / 语音识别 | 语音转写为记录文本 | 使用系统 Speech 框架 |

- App 会话保存在 Keychain，供应商 API Key 只在独立服务端；旧版本保存的个人 Key 不再用于请求
- 账号、会话与邀请码在服务端；训练与饮食记录按账号保存在本地，不做记录云同步
- AI 请求（用户输入、主动附加的照片、对话与所需聚合摘要）经过自有服务中转到模型供应商；不会上传整个本地数据库
- 更换账号使用独立数据库，退出取消云端请求并请求刷新锁定小组件；HealthKit 授权属于当前设备，其他账号仍可主动授权导入该设备健康数据
- 可随时在「设置 → 数据」导出全部数据为 JSON

## 支持的平台

- iOS 17.0 及以上（iPhone）
- 桌面小组件：WidgetKit（依赖 App Group，见上）
- 构建环境：Xcode 16+ / XcodeGen 2.38+；CI 在 `macos-latest` 上构建与测试

## 已知限制

- 未上架 App Store，只能自签安装；HealthKit 与小组件是否可用取决于最终签名权限，需真机验证
- 照片识别与语音输入在模拟器上可能不可用，需真机验证
- 热量与宏营养素为 AI 估算值，不是称重结果
- 分析报告由 AI 生成，仅供参考，不构成医疗建议
- 目前只在中文语境下验证（提示词、日期与语音识别语言均为中文）

## 开发

本地推理由私有 Swift Package `MiloInference` 提供，版本固定在 `project.yml`。先配置该仓库的 Git 读取权限，详见 [接入说明](docs/24-inference-package/integration.md)。SwiftPM 会解析推理依赖，无需另行构建 llama.cpp。

```bash
python3 scripts/verify_no_exercise_dataset.py AgenticKeepKeep  # 检查无旧动作数据集
xcodegen generate   # 生成 Xcode 工程

# 本机（需 macOS）
xcodebuild test -scmProvider system -project AgenticKeepKeep.xcodeproj -scheme AgenticKeepKeep \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

架构：`Features/`（SwiftUI UI）→ `Core/Agents/`（ParserAgent / CoachAgent / AnalystAgent / VisionAgent，纯逻辑可单测）→ `Core/LLM/`（通过独立服务调用 OpenAI 兼容模型；旧协议代码保留）→ `Core/Data/`（SwiftData，唯一数据源）。测试结果以对应提交的 GitHub Actions 为准；主分支推送、PR 与手动触发可运行构建和测试。

文档按轮次组织（索引与约定见 [docs/README.md](docs/README.md)）：

- 轮次 01 · 项目基线：[需求文档](docs/01-foundation/requirements.md)（P0/P1/P2 分级与明确不做清单）· [实施清单](docs/01-foundation/checklist.md) · [界面设计稿](docs/01-foundation/design.html)（HTML 高保真稿，非真机截图）
- 轮次 02 · 真机反馈修复：[实施清单](docs/02-device-feedback/checklist.md)
- 轮次 03 · 教练流式与个人数据：[需求文档](docs/03-coach-streaming/requirements.md) · [实施清单](docs/03-coach-streaming/checklist.md)

- 轮次 18 · Moveliq 品牌与 Milo 首页：[需求文档](docs/18-milo-home/requirements.md) · [实施清单](docs/18-milo-home/checklist.md) · [浅深色设计对照](docs/18-milo-home/design-milo-themes.html)

## 许可证

[MIT](LICENSE) © 2026 MinJung-Go

### HealthKit 侧载签名

CI 产出的 IPA 带 ad-hoc 签名，用于携带 HealthKit / App Group 能力声明，仍需安装工具向 Apple 申请相应描述文件并重新签名。历史 artifact 名中的 unsigned 表示尚未完成设备安装签名。Windows 可用 Impactor 验证；仅替换安装工具不保证最终权限获准。授权失败后可在设置重新授权，详见 [修复清单](docs/10-healthkit-sideload/checklist.md)。

### 本地推理引擎

App 保留独立的 [MiloInference 私有 Swift Package](https://github.com/MinJung-Go/MiloInference)，集中维护 MLX、内存保护、模型校验和性能诊断。业务提示词、工具执行与下载交互保留在 App。App 已改为固定提交的远端依赖，本仓库不再保存引擎源码副本。CI 使用专属只读部署密钥；本地构建需具有私有仓库读取权限。[接入说明](docs/24-inference-package/integration.md)。Apple CI／真机回归仍待完成。[拆分清单](docs/24-inference-package/checklist.md)。
