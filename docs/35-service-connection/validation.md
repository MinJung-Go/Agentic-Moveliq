# 第 35 轮验证记录

日期：2026-10-18。实施分支 `codex/service-connection`，基线 `9c0a8c069a494204a35724ef117be290db873dc1`；[PR #9](https://github.com/MinJung-Go/Agentic-Moveliq/pull/9) 已合并至 `main`，合并提交 `19e9afe8dc5a54f509f604512512e6f39814fdbf`，标签 `v0.5.19`。源码树与已验证的功能提交一致。

## 当前原生结果

[功能 CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39133879587) 在提交 `55376bb13946e5960f4aed4ea2a1211197a07e22` 成功：原生编译、侧载权限声明检查及 **582/582 项 XCTest，0失败**；包含本轮新增17项。实际下载的 `build.log` 含 `Executed 582 tests, with 0 failures` 和 `TEST SUCCEEDED`。41项日常/授权策略、28项音频及默认/全部插件两个实际提示词容量场景通过。

[main CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39134856595) 和 [正式标签 CI](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39134986064) 均成功，标签已完成归档和 IPA 上传；实际下载标签构建日志，同样核对582项 XCTest、0失败和 `TEST SUCCEEDED`。旧运行39132788694因补充账号切换保护而取消，重复PR运行39134745036在合并后取消；两者不作为最终源码通过证据。

## 当前实施范围

用户于2026-10-18明确回复“按第二版接入”，已按该版实施原生页面。初稿未获确认；第二版采用 Milo 欢迎区与底部连接卡，两列服务选择、当前项进度和精简结果替代长列表。OnboardingView首次登录主动展示，复用RootView原账号引导完成键，跳过/完成后不反复弹出，普通升级保持原状态；CoachPluginsView作为同一页面的设置补连入口。

NativeServiceConnection连接Calendar/AlarmKit/MusicKit/CoreLocation及原健康授权，串行等待App活跃状态，全局防重叠请求。ServiceConnectionModel核对账号、保存选择后再请求系统授权，拒绝后继续，支持暂停、后台/页面退出停止、回前台状态复查。日历范围/默认写入位置缺失时引导补充，不代选；保留已有训练同步与自动调整规则。版本0.5.19（40），功能源码已通过上述原生构建/测试。

健康开关以可选字段保存在账号SwiftData配置：旧JSON缺字段保持原行为，新账号首次跳过明确关闭，防止继承设备上其他账号的读取接入。关闭后停止后续导入，已保存记录保留；异步查询返回后再次核对账号代次和开关才落库。旧设置页的显式授权/同步可以重新开启连接。

独立的非 UI 源码新增 `ServiceConnectionFlow`：仅处理选定目标，串行等待、重新检查系统快照、已授权/被拒绝/受限/不可用不重新弹窗；单项拒绝/失败可继续其余服务。请求前、恢复活跃后、系统返回后复查账号及批次；停止保留已处理结果，原请求未返回时禁止再次启动，晚到结果不覆盖新批次。健康选择完成与完整授权状态分开，不选择日历或修改训练同步规则。设置页可清空全部选择后保存关闭，首次引导空选择可跳过。

## 正式安装包

- [下载0.5.19（40）IPA](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39134986064/artifacts/12140041292)，artifact `KeepKeep-unsigned-ipa`，需解压后使用 AltStore / Sideloadly 重签安装。
- 本机留存于忽略目录 `build/releases/Moveliq-0.5.19-40.ipa`；IPA大小 **9,575,525 bytes**，artifact ZIP大小9,548,985 bytes。
- IPA SHA-256：`0c90788511a9001a1871eb48ce1364d0110c561ce9a4031c4c339bbecfbc0a30`。
- 实际下载后通过ZIP完整性检查；App与Widget均为0.5.19（40），bundle ID `com.minjung.keepkeep`，最低系统17.0。服务端点为HTTPS，无全局任意HTTP放行。
- 日历、闹钟、音乐、使用期间定位、健康、麦克风和语音识别用途声明齐全；三个既有Siri动作元数据存在，AlarmKit在Mach-O中为弱链接。静态存在不代表真机授权或执行已经验证。
- 仓库IPA检查脚本通过：Metal库3,814,924 bytes、Widget及许可证存在，无打包模型权重。本地模型继续停用。
- 最终发布文档仅改Markdown，App、测试、构建配置和脚本与已验证标签保持一致；119个本地文档链接及 `git diff --check` 通过。

## 本机验证

| 检查 | 结果 |
|---|---|
| 设计 JavaScript | 提取后 `node --check` 通过 |
| 浏览器预览 | 独立无头 Chrome；第二版浅色390pt、深色390pt、深色320pt大字体，三种环境各9种状态及34项断言通过，所检查节点无横向越界 |
| 交互范围 | 空选择、单次弹窗、顺序请求、拒绝继续、浏览器无授权弹窗、日历范围单独选择、停止、仅处理剩余步骤、跳过与ID唯一性；另查两列布局、整卡触控、键盘焦点、受限服务不跳过选择、进度/结果不重复网格及编辑保留已有结果 |
| 图片检查 | 第二版浅深色三屏及320pt大字体人工查看；缩短欢迎文案，主按钮固定可见，长内容可滚动 |
| 新 Swift 源码 | 13份新改 Swift 文件通过 Tree-sitter 语法检查；不检查类型、并发隔离或 XCTest 运行结果 |
| SwiftPM 检查脚本 | Python AST通过；已包含新 Flow 和测试文件 |
| 文本与资源检查 | Python编码检查4项通过，旧动作数据集资源守卫通过 |

本机临时渲染/断言脚本及额外截图位于忽略目录 `build/qa`，使用独立浏览器配置，未访问已有浏览器会话。仓库保留的PNG是HTML设计预览，不是iPhone截图。

## 验证范围与真机待验

- 新增17项 XCTest 已在macOS原生CI通过，Windows本机未执行。15项队列/选择回归覆盖旧JSON兼容、首次账号健康选择、独立范围/同步配置保留等；2项数据回归验证关闭健康连接不导入、授权期间换账号不重新开启原账号。既有账号隔离测试新增健康开关断言。
- 原生 UI 已按确认的第二版接入并通过编译/XCTest；真实系统连续弹窗、健康授权、首次引导跳过/重启/升级/账号切换、侧载签名和 iOS 版本兼容均未真机验证。
- 实际小屏/大字体/VoiceOver布局、健康读取结果、闹钟响铃、音乐曲库/播放及MusicKit App Service与重签后的能力仍待真机验收；本轮未扩大既有平台权限或后台运行能力。
- 上轮0.5.18的565项测试及IPA不包含本轮改动，不能用作本轮通过证据。

健康读取授权语义核对自 [Apple HealthKit 文档](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)：用户完成授权选择后，App仍无法得知所有读取类型各自是否被允许，因而不得显示“全部健康权限已获准”。
