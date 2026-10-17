# 第 34 轮验证记录

## 2026-10-18 发布验证

- 版本：**0.5.18（39）**；最低 iOS 17，AlarmKit 仅 iOS 26+。
- [PR #8](https://github.com/MinJung-Go/Agentic-Moveliq/pull/8) 已合并至 `main`；标签 `v0.5.18` 指向 `03b6a5160f84076daeb48ce1bb0f18fdd7dc0e9e`，源代码树与评审通过的功能分支一致。
- [main CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39058038469) 与 [标签 CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39058061133) 均成功；原生编译、侧载权限声明检查和 **565/565 项 XCTest，0 失败**，包含本轮新增61项。已下载实际构建日志核对数量和 `TEST SUCCEEDED`；标签的 IPA 归档、打包与上传均成功。
- 标签 CI 中 28 项音频、26 项 Foundation 日常/授权策略及默认/全部插件两个实际源码预算场景通过。没有放宽上下文输入上限、输出预留或查询预留。
- [正式标签 IPA 下载](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39058061133/artifacts/12110533955)：artifact `KeepKeep-unsigned-ipa`，解压后的 `KeepKeep-unsigned.ipa` 为 **9,519,630 字节**。本机保留为 `build/releases/Moveliq-0.5.18-39.ipa`；该路径为忽略目录，不提交二进制。
- IPA SHA-256：`11c8f4ba94757add1a46d61e08d860884c1f9acec038b3111beab600ce2ffb9c`。
- 下载后 ZIP 完整性、App/Widget 均为0.5.18（39）、bundle ID `com.minjung.keepkeep`、最低 iOS 17、服务地址 `https://moveliq.work/api`、日历/闹钟/音乐/定位/健康/麦克风/语音权限用途描述均核验通过。三项 App Intents 元数据完整，AlarmKit 为 weak link；包含3,814,924字节 Metal 库和许可证，不含模型权重。
- 执行 `python scripts/local-milo/verify_ipa.py <IPA>` 及本机临时核验脚本检查上述包内容。静态 weak link 和权限描述不能代替旧系统运行及真机授权；本包仍需侧载工具重新签名。
- 发布回填仅更新四份 Markdown；119 项本地文档链接与 `git diff --check` 通过。App、测试、工程及 CI 配置与上述已通过标签一致。

以上是当前状态，后面的失败、待确认或未打包描述为历史阶段记录。Windows 本机不执行 Xcode；原生结果来自对应提交的 macOS CI。

安装后在“设置 → 插件”启用所需插件并申请系统权限；在“我的训练与日常 → 自动调整范围”保存完整的个人规则后才允许自动执行。未配置完整时继续人工确认，不从设计稿示例推断用户额度。

尚待验证：SwiftUI 真机布局、真实模型端到端规划/动态调整、EventKit 同步及重复事件、WebKit 搜索提取、定位/地图跳转、AlarmKit 授权与关闭 App 后响铃、MusicKit 播放和 Siri 发现/冷启动。Apple 音乐曲库需要最终 App ID 的 MusicKit App Service 与实际侧载配置；本轮没有修改开发者后台、部署音乐服务或执行真机测试。

系统插件工具已接入文字与语音转文字对话；Realtime 通话保持原有课程提案入口。主动检查在 App 实际可观察的前台事件触发，App 挂起后不持续运行云端 Agent；已安排的日程/闹钟由系统处理。

## 2026-10-18 实施与 CI 历史

最新功能源码 `c37bec98dc42a0e82b5e903f6710361629db949c` 的 [CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39056960170) 已通过 App 编译、侧载权限声明检查及 **565/565 项 iOS XCTest（0失败）**；包含本轮新增61项。28项音频、26项策略及默认/全部插件两个实际预算场景通过。原先失败的默认预算回归保留并已通过，未调整输入上限、输出预留或查询预留。IPA 正在归档；下面失败和待运行描述均为历史阶段记录。

用户已确认按第二版继续开发并打 IPA。首批提交 `78e478a9cc7b4c72b215b0f27870a4fb81335fa9` 已上传原仓库（GitHub 更名为 Agentic-Moveliq，不可变仓库 ID 1371562951）。[首轮 CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39049650277) 的 28 项音频检查和 26 项日常/授权策略测试通过；App 编译发现今日安排“保留原计划”误调用 CoachLifeStore.dismiss，现已修正。iOS 单测尚未执行。

本批源码接入第二版原生授权设置、前台自动提案及本机执行判定、原始锚点与每日用量、计划/审计同批提交、同步授权与生活约束版本、部分失败回执、单次确认剩余同步、重新校验后恢复原安排。独立系统操作仍走具体确认卡；自由文本限制/不适信息不能可靠校验时转人工确认。新增 8 项数据测试，本轮新增 60 项 XCTest。准备版本 0.5.18（39），尚未生成 IPA。

补查并修正：自身日历写入通知不反复触发同一轮规划；已有新鲜待确认方案/实时通话期间不并发发起主动检查；恢复保留原备注并检查进行中训练；单次确认只解除本批剩余步骤的自动规则标记，不扩大规则或重置已成功回执。系统插件当前用于文字/语音转文字对话，Realtime 维持原有课程提案入口。

第二轮提交 `ac5fdd9a70f10fc9afc7872b945616c4d82f25c5` 的 [CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39050496842) 通过 28 项音频/26 项策略检查，原生编译发现 MusicKit 队列初始化需要可播放内容的 Sequence；已将单个专辑/歌单包装为集合。核对 [Apple MusicPlayer.Queue](https://developer.apple.com/documentation/musickit/musicplayer/queue) 及 CI 中实际 SDK 的泛型签名后修正。该轮尚未执行 iOS XCTest，未产出 IPA。

第三轮提交 `4c7f9b1ad2d8231be787ba1bb3ab8d99ea7cd83f` 的 [CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39051534109) 通过音频/策略检查，原生编译发现插件页 catch 中 error 与隐式错误变量重名，已改为 self.error；扫描其余 catch 未发现同类写法。模拟器 CI 改为构建 runner 原生架构并用同一架构运行测试，避免重复编译两套模拟器依赖；设备归档仍使用原有 iOS 流程。

补齐原 13 屏 HTML 的浏览器验收：浅色及深色/320pt/大字体两种环境，8 类选择器的 44 个状态和 29 项交互断言分别通过，所检查节点无横向越界。独立无头 Chrome 未使用用户会话；截图与 DOM 日志位于本机忽略目录 build/qa，此结果不代替原生布局或系统权限验收。

第四轮提交 `b326a12f0f95274fa9012d6fab1c0c597a7e6478` 的 [CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39052596574) 已通过 App 编译及侧载权限声明检查，实际运行 **564 项 iOS XCTest，563 通过、1 失败**；本轮此前新增的 60 项通过，失败为原有的默认上下文容量回归（CoachQueryToolsTests.testCurrentPlanAndAllQuerySchemasFitDefaultBudget）。压缩重复提示词/参数说明而非提高预算，并增加实际源码提示词/工具预算的快速 Swift 检查。自动检查改用实际服务容量；相处方式提示词同步采用“有效本机授权内调整，其余/删除确认”，保留昵称/偏好不可改变权限的边界。

同时修正减载只能固定15%的限制：结构化 weightReductionPercent 由本机限制为1–50%，缺省仍兼容15%，在确认卡显示实际比例与0.5kg取整规则；模型不能通过描述代替真实参数。新增1项小幅减重与实际落库一致的回归，本轮累计新增61项 XCTest，等待最终CI。

本机再次通过编码回归 4/4、资源守卫、218 个 Swift 文件的语法扫描（只有未修改的 LocalPrompt.swift 既有解析器限制）和补丁空白检查。新批次类型检查及 XCTest 等待原生 CI；以下 2026-10-17 内容保留为此前阶段记录，不能代替当前结果。

日期：2026-10-17。分支：`feat/agent-system-plugins`，基线 `651a37a`。本轮改动尚未提交/推送，无本轮 CI 结果或 IPA。用户已确认原 13 屏设计并授权开发；自动调整授权的追加 UI 稿尚待确认，非 UI 规则可先实施。提交、推送和发布仍遵循仓库的单独授权约定。

## 本机已执行

| 检查 | 结果与范围 |
|---|---|
| Windows 编码回归 | `python scripts/local-milo/test_dependency.py`，4/4 通过，包含关闭 UTF-8 模式及 GBK 默认编码用例 |
| 动作资源守卫 | `python scripts/verify_no_exercise_dataset.py AgenticKeepKeep` 通过 |
| Python / 资源 | 13 个 Python 脚本 AST、5 个 App/Widget 资源 JSON、4 个 plist/entitlements 可解析 |
| 工程 / CI 配置 | project.yml、iOS workflow、Xcode SDK composite action 的 YAML 可解析；未在 GitHub 运行 |
| 设计静态检查 | 13 屏、8 个状态选择器、ID 唯一、label 目标有效，脚本 `node --check` 通过 |
| 追加授权稿第二版 | ID/label/JavaScript 通过；Chrome 实际渲染浅色/深色三屏、320pt、320pt 大字体、大字体编辑浮层及部分失败结果，共 6 种预览 |
| 文档 | README、docs 索引和本轮 Markdown 的本地链接检查 |
| Swift 语法扫描 | 追加授权规则后 Tree-sitter 解析 215 个 Swift 文件，无新增解析错误；LocalPrompt.swift 的 15 个解析节点错误与 HEAD 相同 |
| 补丁 | `git diff --check` 通过，无空白错误；Git 的 LF/CRLF 转换提示不属于测试失败 |

语法扫描使用临时安装在忽略目录 `build/qa` 的 tree-sitter 0.26.0 / tree-sitter-swift 0.7.4；没有增加 App 包依赖。这只能发现语法问题，不检查 Swift 类型、SwiftData 宏、App Intents 元数据或 SDK 链接。

## 新增测试，等待 macOS 执行

共 **52 项 XCTest**：

- `CoachLifePolicyTests` 10 项：未知偏好、缓冲、重叠事件、保护时段、全天占用、过去时间、无效时段、显式时区、夏令时及临时时长提取。
- `CoachAutomationPolicyTests` 16 项：缺省关闭/规则不完整、移动边界/跨天、累计移动与减重、缩短底线、不增加训练量或换动作、整批越界、每日次数、系统同步单独授权、校验过期、进行中/需澄清状态、未知时间、重复与空操作。
- `CoachLifeDataTests` 12 项：账号容器、操作去重、时间窗口、保护/临时限制、无日历时的本地训练重叠、临时信息过期、精确时间导入/导出、连续改期及停用同步、旧账号、摘要版本、自动授权按账号保存/撤销/导出、反馈导出。
- `CoachPluginValidationTests` 5 项：事件身份/实际变更、无时区/无界重复、矛盾闹钟时间/非法星期、更新身份、不可用工具不暴露。
- `LoggingReliabilityTests` 7 项：失败回滚、无关编辑、批次重试/照片关联、兜底草稿、清空后晚到成功/失败、忙碌状态和首页输入。
- 现有 `PlanMutationTests` 增加 1 项精确改期/时长/防重用例；`WorkoutSessionWriteBackTests` 增加 1 项完成身份/时长/防重用例。

`scripts/test_coach_life_portable.py` 把实际 DTO/时间策略、自动授权判定器及对应 26 项测试放入临时 SwiftPM 包，接入 macOS CI。iOS 构建/测试/归档使用本仓库 composite action 选择已安装的稳定 Xcode 26+，App 仍支持 iOS 17，AlarmKit 由 availability gate 保护。

Windows 本机没有 Swift/Xcode，**以上 52 项未运行**。未取得本轮原生通过数；历史 504 项 iOS / 28 项音频的通过记录不代表本轮通过。

## 自主程度追加的实施边界

用户最新选择为“在我预先设定的范围内自动调整，其余再确认”。已更新需求和 [3 场景追加设计](design.autonomy.html)，实现账号配置存储/导出、授权变化使旧提案失效及纯逻辑资格判定器。示例额度没有写入 App，实际自动执行尚未启用。

新增 UI 超出此前确认的 13 屏范围，按 AGENTS.md 等待具体追加稿确认；设置、自动触发/执行器、用量及原始锚点记录、撤销授权后的待执行任务失效、回执/恢复操作尚未接入。当前判定器不承担系统 I/O，也不能作为这部分已完成的证据。

## 授权界面第二版预览

用户认为初稿不好看后，改为 Journal 主题下的授权概览与分项底部编辑，去掉首屏密集的数字输入和复选框；保留真实权限与全部可配置边界。结果页突出原时间到新时间的变化，详细依据折叠；同步失败时固定主按钮改为重试未完成的提醒。此轮只修改设计稿和文档，没有替换原生 UI。

可查看 [浅色三屏截图](design.autonomy.light.png)、[深色三屏截图](design.autonomy.dark.png) 和 [交互稿](design.autonomy.html)。PNG 为本机 Chrome 渲染的 HTML，非 iPhone 真机截图。

使用独立临时浏览器配置加载本地文件，没有访问已有用户浏览器会话。6 种预览逐一检查，修正了单屏预览的浏览器最小视口差异，以及 320pt 下的中文孤行。额外进行浏览器 DOM 检查：编辑保存/取消、停用、同步开关、失败重试、单次确认，在普通/320pt/大字体下所检查的按钮、输入与内容块无横向越界。键盘焦点限制在编辑浮层中，可按 Escape 取消。

检查结果仅覆盖 HTML 原型，不代表 SwiftUI 布局或实际系统写入验证。该第二版尚待用户确认。

## 原生与真机验收

按 [checklist](checklist.md) 运行 iOS 构建、XCTest 和核心端到端场景，再填写实际提交号、CI 链接和通过数。使用本轮构建测试，不以 HTML 设计稿替代原生 UI。

早期 CUA/iab 不可用时未完成原 13 屏渲染；后续已通过无头 Chrome 完成追加授权第二版的截图和预览检查。原生界面仍需验证小屏、浅深色、大字体、键盘、权限拒绝/撤回、冷启动和账号切换。

系统部分需 iPhone 验证 EventKit 实际同步/重复范围、WebKit 搜索与手动提取、地图定位与跳转、AlarmKit 关闭 App 后响铃、Siri 短语及 MusicKit 播放/音频中断。地图路线详情交给 Apple 地图；“N分钟后提醒”使用固定时间 AlarmKit 闹钟，不提供倒计时 Live Activity。

Apple 音乐曲库还需开发者后台为最终 bundle ID 启用 MusicKit App Service，并检查实际侧载签名、订阅和地区。没有配置开发者私钥，也没有修改开发者后台；授权成功不能代替实际曲库播放验证。依据：[Apple 自动 developer token 配置](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api)。

跨 SwiftData、EventKit 和 AlarmKit 不存在单一原子事务。实现使用持久化意图、稳定 ID、创建标记、分步回执与显式重试；应重点验证“日历成功但闹钟失败”“连续改期后重试”“确认前事件被外部修改/删除”“App 中途退出后恢复”，并核对系统实际内容。
