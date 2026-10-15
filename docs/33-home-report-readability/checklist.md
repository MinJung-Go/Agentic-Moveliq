# 首页、报告与输入栏优化清单

当前：0.5.15 已发布；用户真机反馈后的第五版已获确认并完成本地代码接入，见末尾 R6。0.5.15 的 CI 是历史结果；R6 的 0.5.16（37）已打包，CI 与 IPA 结果见末尾。

## 需求与设计

- [x] 核对相关历史需求、首页、RecordRow、报告及三套输入栏，见[需求](requirements.md)。
- [x] 完成[交互稿](design.html)：轻量首页、紧凑记录、连续阅读报告、三入口消息输入和基础组件状态。
- [x] 2026-10-15 用户“开发吧”确认当前设计的 R1–R5 范围，在现有 `feat/home-report-readability` 分支实施。

## 0.5.15 代码实施

- [x] 首页：日期、问候与 Milo 收紧；课程保留独立行动容器；记录去掉外层卡片，健康详情改为轻量折叠行。保留无计划/休息/继续训练等原有路径。
- [x] 共享 RecordRow：照片固定在类型图标下，时间/来源固定右列；辅助功能大字体将元信息移到正文下方。首页与记录页共用，无须加载照片原图。
- [x] 食物展示名：取已有结构化名称，长尾括注只在列表收起；完整 title、模型内容和 VoiceOver 原名保留。缺失或不确定时回退原名。
- [x] 报告：完整保留 headline/body/tags/citedDataText；纯长中文正文按完整句子分段，已有换行/Markdown 保留，增加段间距，AI 依据仍默认折叠。无数据迁移与额外模型请求。
- [x] [MessageComposer](../../AgenticKeepKeep/Core/Design/MessageComposer.swift) 接入首页、Milo/课程教练共用聊天页、记一笔。统一 52pt 起始高度、17pt 字体、1–4 行和至少 44pt 操作范围。
- [x] 输入行为：原地语音转文字、不自动发出，取消恢复原草稿；已有草稿可以补充转写，录音中可直接发送；后台/中断/离开停止收音，首次系统权限弹窗不误停。发送后清理旧提示。
- [x] 附件/忙碌：照片预览可移除，文字/照片单独或一起发送；加载或解析期间防重复提交，失败保留草稿。教练“＋”保留实时通话及停止生成，未添加照片能力；记一笔不伪造停止解析功能。
- [x] 组件：确认修改复用主按钮；来源文字列表/详情共用；暖橙/亮黄图标默认深色；加载点继承前景；筛选/文字操作保留 44pt 下限；登录字段使用 12pt 内圆角与语义字号。
- [x] 修正[第 04 轮设计规范](../04-ui-polish/design-system.md)中颜色、按钮、卡片与按下反馈的冲突。

## 0.5.15 验证

- [x] 设计原型浏览器 **26/26**：60 种页面组合、288 个输入栏组合预览、36 种基础组件组合；仅验证 HTML，不能替代 SwiftUI 验收。
- [x] 浅深色预览人工检查；本目录仍只保留[浅色总览](design.light.png)和[深色总览](design.dark.png)，没有新增局部截图。
- [x] 纯逻辑 **16/16**：10 项报告分段/展示名称测试、6 项既有首页分流测试。实际 Swift 6.0.3 Linux 执行，见 `/tmp/moveliq-readability-tests.log`。
- [x] 语音状态 **9/9**：草稿追加、取消、最终结果、录音中发送、旧回调隔离、失败重试和提示清理。Linux 临时 harness 使用 Combine/音频替身，仅覆盖 VoiceInput 状态，不覆盖 SwiftUI 发布订阅和真实音频。日志 `/tmp/moveliq-round33-voice-tests.log`。
- [x] App、测试与 Widget 共 192 个 Swift 文件语法解析通过，`git diff --check` 和既有资源清理检查通过；语法检查不等同于 iOS 类型检查/构建。
- [x] iOS CI 构建及完整原生测试：提交 `3be6cb8e1f48fc78a49ecb6641a281c18e2c60a5`，[运行 38704542009](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/38704542009)。Xcode 构建成功，完整原生 XCTest **501/501**；新增 2 项 RecordItem/SwiftData 集成测试通过，Apple 音频专项另 **28/28**。
- [ ] 模拟器/真机：320/390/430pt、浅深色、动态字体、VoiceOver、键盘安全区与焦点、相册取消/失败、真实语音权限/中断/转写和实时通话入口复验。
- [x] 功能代码已提交/push（`3be6cb8`）；0.5.15（36）IPA 已归档并上传，[下载产物](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/38704542009/artifacts/11958669876)。[CI 全部成功](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/38704542009)，安装需通过 AltStore/Sideloadly 等重签名。
- [x] 下载产物复核：IPA ZIP CRC 通过，App/Widget 均为 **0.5.15（36）**，服务地址为 `https://moveliq.work/api`；IPA 8,822,518 bytes，SHA-256 `e038df097a75a44d0ed81a97ad1321e34a77bbcb7a26acf8c4afde0a3d3fde37`。

可复跑纯逻辑：`python3 scripts/test_readability_portable.py`；Linux 自定义 Swift 路径可通过 `SWIFT=/path/to/swift` 传入。新增/修改的 XCTest 也由既有 iOS 测试目标自动收录。

## 一致性巡检落实

| 巡检发现 | 本次落实 |
|---|---|
| 主按钮有矩形/胶囊/borderedProminent 混用 | 开始训练与确认修改共用 PrimaryButtonStyle；删除保留红色语义，系统确认框不重做 |
| AI 估算在列表白字、详情黑字 | 两处共用 RecordSourceLabel，使用次级来源文字 |
| 暖橙图标默认白色 | SymbolChip 按暖橙/亮黄选择 onAccent，其余语义色前景保留 |
| 禁用按钮上固定白色加载点 | PulsingDots 可继承当前前景，洞察生成按钮采用该模式 |
| 小筛选和文字动作不足 44pt | FilterSegments、PlainActionButtonStyle 补最小范围，实际命中待真机验证 |
| 登录字段局部圆角 14pt | 收敛为 Theme.Radius.inner=12，保留表单语义与原有校验逻辑 |
| 设计规范与实现不符 | 同步修正规范，不将历史截图当作当前实现 |

## 0.5.15 发布时的状态与边界

分支 `feat/home-report-readability`，基线 main `05aaee2`。已修改 App、适用测试和文档；Service、云端、账号与数据结构均未改。当时用户已授权提交/push 和 0.5.15（36）IPA；该版 CI 构建、测试与 IPA 归档均通过，真机验证结果另行记录，不把 HTML 或 Linux 检查表述为原生验收。

登录/搜索/数字表单、系统 Form、系统确认框、通话控制保留场景差异。未重新设计其他页面和空态体系，也未恢复本地模型。

## 第四版记录稿（历史提案，未获确认）

- [x] 记录第三版未获确认：用户选择“继续调整设计”；原有 13 项浏览器结果仅证明布局检查通过，不代表审美通过或已经接入 App。
- [x] 更新 R6：名称与热量分主次，时间/照片/来源集中，恢复正常字号，未知热量不占位或伪造。
- [x] 更新当前 HTML 的第四版首页和记录页；既有报告、输入栏与组件可展开。
- [x] 第四版浏览器 **15/15**：三宽度 × 浅深色 × 常规/大字体 × 五状态（60 组合 / 120 页面预览）、原始完整名称搜索和详情、类别筛选、未知热量/蛋白质不补值、照片不等于估算、44pt 操作范围、既有稿展开与无脚本错误。当时浅深色已人工复核；总览现已由第五版覆盖，历史日志 `/tmp/moveliq-records-v4-check.log`。
- [x] 第四版未获确认：用户反馈“还是有些略丑”，要求重新思考；15 项检查不代表审美通过。
第四版已放弃，不再实施；后续工作统一记录于第五版/R6。

## 第五版：按时间阅读的日常记录（已确认）

- [x] 重新梳理用途与信息层级，更新 R6：撤掉大热量列与类别图标底，改为时间栏与连续内容栏。
- [x] 重画首页与记录页：暖白底、克制字重、统一留白、轻量快捷入口；完整名称搜索、详情与既有业务入口保留。
- [x] 第五版浏览器 **15/15**：三宽度 × 浅深色 × 常规/大字体 × 五状态（60 组合 / 120 页面预览），时间与内容分栏/对齐、首页与记录页共用行、完整名称搜索/详情、类别筛选、未知营养/来源、44pt 筛选范围、既有输入稿与脚本错误检查通过。浅深色已人工检查，仅更新现有两张总览；日志 `/tmp/moveliq-records-v5-check.log`。这些结果只验证 HTML，不代替审美确认或原生验收。
- [x] 2026-10-15 用户“可以，开发吧”确认第五版与 24pt 对齐细化，在当前分支接入 App。
- [x] 后续用户“打 IPA”已授权发布；原生 CI/IPA 已完成，真机复核另列于下方。

## 第五版对齐细化

- [x] 明确页面外边缘与容器内边距的区别：正文、课程卡和首页输入栏外边缘统一 24pt，记录仍保留时间分栏。
- [x] 首页输入栏与附件操作菜单随正文统一 24pt。浏览器 **16/16** 检查通过，其中新增三宽度 × 浅深色 × 常规/大字体 × 八输入状态 × 键盘显隐，共 **192** 个输入组合，验证双侧 24pt、菜单边界、44pt 按钮、无横向溢出和保留时间分栏；现有浅深色两张总览已更新并人工复核。日志 `/tmp/moveliq-records-v5-alignment.log`，仅 HTML 原型。
- [x] 用户确认将对齐细化随第五版一起接入 App。

## R6 实施与验证

- [x] 共享 [RecordRow](../../AgenticKeepKeep/Core/Design/RecordRow.swift)：时间栏、第一项名称与独立项数样式、完整摘要/来源。极大辅助功能字号时将时间移到上方，分隔线同步跟随。照片仅读 hasPhoto。
- [x] 首页：局部暖白/深色主题、轻描边快捷入口、低对比课程容器，正文与输入框统一 24pt。已有课程状态、进度、开始/继续训练、语音和照片路径保留；聊天/记一笔默认 16pt 未变。
- [x] 记录页：移除拼接白卡，24pt 搜索/列表边距，32pt 视觉/至少 44pt 操作的筛选、日期分组；仍用原生 List 和 swipeActions。整行按钮进入原详情，避免默认 disclosure 额外挤占内容宽度。
- [x] 搜索覆盖所有食物名称、原有摘要和饮食备注，VoiceOver 保留完整食物名；列表精简不修改持久化内容。新增 1 项真实长名称展示逻辑回归、更新既有项数/空名回退测试；另新增 2 项原生模型搜索/朗读回归，本次 iOS CI 已通过。
- [x] 本次 Linux Swift 6.0.3 实际执行：展示/报告 **11/11**、首页分流 **6/6**，合计 **17/17**（`/tmp/moveliq-r6-readability-tests.log`）；App/测试/Widget **193** 个 Swift 文件语法解析通过，后续 UI 增量也已解析（`/tmp/moveliq-r6-swift-parse.log`）。资源清理检查和 `git diff --check` 通过。语法解析不代表 SwiftUI 类型检查、SwiftData 集成或 iOS 构建通过。
- [x] iOS 原生构建、全量测试与 0.5.16（37）IPA 归档已完成；本次用户“打 IPA”已授权提交、push 与触发构建。
- [ ] 真机：浅深色、320/390/430pt、辅助功能字号、搜索/删除、照片/语音/键盘。

本次构建限制：当前工具环境 `list_sims` 返回 `spawn xcrun ENOENT`，没有 Xcode/iOS SDK，因此新增的 2 项原生模型测试和 SwiftUI 构建现已通过 GitHub Actions 验证；原生导航/滑动删除和真实键盘/辅助功能效果仍待装机复核。本地验证与 iOS 构建结果分别记录，Service 与云端未改。

## 0.5.16（37）IPA 发布

- [x] 用户“打 IPA”确认按现有 GitHub Actions 链路发布；保持当前功能分支，App/Widget 同步升级至 0.5.16（37）。
- [x] 提交并 push 当前 R6 功能与文档：`92262e61688f7542d0f8ca78837916e1b1a3b094`；`v0.5.16` 已触发[本次构建 38715725040](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/38715725040)。
- [x] `92262e61688f7542d0f8ca78837916e1b1a3b094` 的[本次 CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/38715725040)原生构建及完整 XCTest **504/504** 通过，Apple 音频专项另 **28/28**。新增真实长名称、完整食物名搜索/辅助朗读及非饮食搜索测试均通过；侧载权限嵌入校验通过。原生日志 `/tmp/moveliq-0.5.16-build-log/build.log`，音频日志 `/tmp/moveliq-0.5.16-audio.log`。
- [x] [本次 CI 全部成功](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/38715725040)，[下载 0.5.16（37）IPA](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/38715725040/artifacts/11964063963)。已实际下载并验证 ZIP CRC、App/Widget 版本一致、`https://moveliq.work/api` 服务地址、MLX Metal 库和许可、未打包模型权重及旧动作资源。IPA **8,840,124 bytes**，SHA-256 `5411c0e6df458cfab9a636dbda870dbaf5b659f7bc8191a5751e888dcd7ba8af`；本地文件 `/tmp/moveliq-0.5.16-37/KeepKeep-unsigned.ipa`。安装仍需 AltStore/Sideloadly 等侧载工具重签名。

## R7 输入栏内部对齐修复

- [x] 用户已确认是空白/单行时「＋」与“聊聊…”上下未居中；确认范围与当前修复一致。记录线索但不将其当作已经验证的真机根因。
- [x] 同步当前 HTML 的单行居中约束，保留多行靠下和原有输入状态；更新现有两张总览，未新增永久稿件。
- [x] 共享 MessageComposer：空文本显式 center、TextField 内容理想高度与最小 44pt 居中范围，照片/实时菜单统一外部 44pt，实时菜单 plain + 隐藏指示符；原有入口及回调保留。
- [x] 原型三宽度 × 浅深色 × 常规/大字体 × 八状态 × 三入口，共 **288** 个预览通过：单行文字/图标垂直中心误差小于 1px，多行保持底对齐，按钮 44pt、无横向溢出；实时菜单可打开并触发演示动作。日志 `/tmp/moveliq-r7-composer-check.log`。修改后的 Swift 文件语法解析和 `git diff --check` 通过。本次均为 HTML/语法验证，不沿用 0.5.16 的原生测试结果。
- [ ] 原生构建与全量回归，结果记录在下方 0.5.17（38）发布项。
- [ ] 真机：单行、自动换行、4 行以上滚动、大字体、键盘、照片和实时菜单。

## 0.5.17（38）IPA 发布

- [x] 用户再次“打 IPA”授权提交/push 本次对齐修复并按既有 Actions 流程打包；当前分支不变，App 与 Widget 同步升级至 0.5.17（38）。
- [ ] 提交、push 并以 v0.5.17 tag 触发构建，记录源码提交与 CI 链接。
- [ ] 本次原生构建、全量 XCTest、音频专项及设备归档通过；不沿用上一版结果。
- [ ] 实际下载核验 App/Widget 版本、服务地址、ZIP 完整性与 IPA SHA-256，回填下载链接。
