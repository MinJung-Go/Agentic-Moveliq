# 首页、报告与输入栏优化清单

## 需求与设计

- [x] 核对相关历史需求、首页、RecordRow、报告及三套输入栏，见[需求](requirements.md)。
- [x] 完成[交互稿](design.html)：轻量首页、紧凑记录、连续阅读报告、三入口消息输入和基础组件状态。
- [x] 2026-10-15 用户“开发吧”确认当前设计的 R1–R5 范围，在现有 `feat/home-report-readability` 分支实施。

## 代码实施

- [x] 首页：日期、问候与 Milo 收紧；课程保留独立行动容器；记录去掉外层卡片，健康详情改为轻量折叠行。保留无计划/休息/继续训练等原有路径。
- [x] 共享 RecordRow：照片固定在类型图标下，时间/来源固定右列；辅助功能大字体将元信息移到正文下方。首页与记录页共用，无须加载照片原图。
- [x] 食物展示名：取已有结构化名称，长尾括注只在列表收起；完整 title、模型内容和 VoiceOver 原名保留。缺失或不确定时回退原名。
- [x] 报告：完整保留 headline/body/tags/citedDataText；纯长中文正文按完整句子分段，已有换行/Markdown 保留，增加段间距，AI 依据仍默认折叠。无数据迁移与额外模型请求。
- [x] [MessageComposer](../../AgenticKeepKeep/Core/Design/MessageComposer.swift) 接入首页、Milo/课程教练共用聊天页、记一笔。统一 52pt 起始高度、17pt 字体、1–4 行和至少 44pt 操作范围。
- [x] 输入行为：原地语音转文字、不自动发出，取消恢复原草稿；已有草稿可以补充转写，录音中可直接发送；后台/中断/离开停止收音，首次系统权限弹窗不误停。发送后清理旧提示。
- [x] 附件/忙碌：照片预览可移除，文字/照片单独或一起发送；加载或解析期间防重复提交，失败保留草稿。教练“＋”保留实时通话及停止生成，未添加照片能力；记一笔不伪造停止解析功能。
- [x] 组件：确认修改复用主按钮；来源文字列表/详情共用；暖橙/亮黄图标默认深色；加载点继承前景；筛选/文字操作保留 44pt 下限；登录字段使用 12pt 内圆角与语义字号。
- [x] 修正[第 04 轮设计规范](../04-ui-polish/design-system.md)中颜色、按钮、卡片与按下反馈的冲突。

## 验证

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

## 状态与边界

分支 `feat/home-report-readability`，基线 main `05aaee2`。已修改 App、适用测试和文档；Service、云端、账号与数据结构均未改。用户已授权提交/push 和 0.5.15（36）IPA；CI 构建、测试与 IPA 归档均通过，真机验证结果另行记录，不把 HTML 或 Linux 检查表述为原生验收。

登录/搜索/数字表单、系统 Form、系统确认框、通话控制保留场景差异。未重新设计其他页面和空态体系，也未恢复本地模型。
