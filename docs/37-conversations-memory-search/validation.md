# 第 37 轮 · 调查与设计预览验证

日期：2026-10-23。App 代码基线 `8eebdfc`，分支 `feat/personal-agent-skills`。本轮仅新增文档与 HTML/CSS，未修复原生搜索、修改数据模型或主题。

## 搜索最小复现

Linux Swift 6.0.3 直接编译当前仓库的三个源文件及临时 main.swift，没有复制改写被测策略：

```sh
swiftc AgenticKeepKeep/Core/LLM/FitnessSearchTopic.swift \
  AgenticKeepKeep/Core/Agents/CoachToolResult.swift \
  AgenticKeepKeep/Core/LocalMilo/LocalBrowserPolicy.swift \
  /tmp/moveliq-round37/main.swift -o /tmp/moveliq-round37/search-probe
/tmp/moveliq-round37/search-probe
```

| 输入／检查 | 实际结果 |
| --- | --- |
| 单条 `https://www.swift.org/documentation/` 公共结果 | failed=true，sources 为空 |
| 单条 `https://www.who.int/health-topics/physical-activity` | failed=false，保留 1 个来源 |
| 空数组与上述被过滤的 Swift 来源比较 | content 与 failed 完全相同 |
| strength 查询及主题枚举 | 查询含强制 site 条件，主题只有 7 个 |

4 项断言通过。这是对旧限制的复现，不是修复验收，也不是网站可访问性测试。未对网络发请求，未获取用户失败页面的 DOM；真机问题可能还叠加验证码、移动布局或网络差异。

可独立重建 main.swift 的核心检查：

```swift
import Foundation
let filtered = LocalBrowserPolicy.result([
    ["title": "Swift", "url": "https://www.swift.org/documentation/", "text": "Documentation"]
], count: 5)
let allowed = LocalBrowserPolicy.result([
    ["title": "WHO", "url": "https://www.who.int/health-topics/physical-activity", "text": "Guidance"]
], count: 5)
let empty = LocalBrowserPolicy.result([], count: 5)
precondition(filtered.failed && filtered.sources.isEmpty)
precondition(!allowed.failed && allowed.sources.count == 1)
precondition(empty.content == filtered.content && empty.failed == filtered.failed)
let query = URLComponents(url: LocalBrowserPolicy.searchURL(topic: .strength),
                          resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "q" }!.value!
precondition(query.contains("site:") && FitnessSearchTopic.allCases.count == 7)
```

## HTML 预览验证

本地 Chromium + Playwright，以 file:// 打开，无外部资源和真实账号请求。

- 会话搜索、当前标记、新建空会话复用、生成中阻止新建：通过。
- 画像编辑与撤销、技能使用开关、空态、管理菜单打开／关闭：通过。
- 搜索七种状态、通用来源示例、浏览示意关闭：通过。
- 1640px 桌面浅／深色截图，360px 窗口下 320px 手机大字号布局：无页面横向溢出、四个内容滚动区无横向溢出、无 JS 异常。
- 六屏配色对照：浅深色下六个 phone 容器使用相同 page token；320px 窗口无横向溢出、无 JS 异常。
- 人工查看浅色交互稿、深色交互稿、六屏配色截图，标题、列表基线和分组层次可见。

脚本与截图位于本次环境的 `/tmp/moveliq-round37/`，不作为永久发布产物。设计入口为同目录的 design.html 与 design.colors.html；两者共用 design.css。

后续 IDE 预览兼容修复：共享 CSS 仍作为维护源，但 HTML 已内嵌生成的样式副本，不再运行时加载外部 CSS。修改样式后运行 `python3 docs/37-conversations-memory-search/sync-design-assets.py` 同步三份 HTML；该脚本也从仓库资源更新内嵌 Milo 图片。

## 色值检查

按 sRGB 相对亮度计算（最终系统可访问性仍需 iOS 验证）：

| 文字／底色 | 浅色对比度 | 深色对比度 |
| --- | --- | --- |
| text / page | 14.86:1 | 15.29:1 |
| secondary / surface | 5.21:1 | 7.60:1 |
| secondary / field | 5.07:1 | 7.05:1 |
| metadata / page | 4.62:1 | 7.01:1 |
| action / page（也是主按钮前后景组合） | 5.08:1 | 9.06:1 |

metadata 不据此授权放在任何背景上；装饰线条不承担唯一控件边界。

## 尚未验证

原生 App、真正的 Safari 展示／读取通道、目标网络的实时搜索、升级迁移、VoiceOver、提高对比度与原生 Dynamic Type。未运行 iOS CI，本轮 XCTest 数量为未运行；未提交或打包。

## 会话第二版预览验证

2026-10-23 用户要求参考豆包后，仅更新设计，未接入 App。

- 只读查看了 2025 年公开手机截图，参考导航栏右上角新建与新对话空态，不复制头像或品牌。
- 新增 design.conversations.html／design.conversations.css；完整 design.html 的会话入口同步更新。Milo 图片直接引用本仓库现有资源。
- Playwright：搜索、切换、生成中阻止新建、重复新建复用空会话、输入后麦克风变发送、发送后恢复麦克风，通过。
- 完整设计稿新建页打开、演示输入发送、返回列表通过；无 JS 异常。
- 1300px 窗口导出三屏浅深色高清 PNG；360px 窗口、320px 手机、大字号检查，无页面与手机容器横向溢出。
- design.conversations.light.png／design.conversations.dark.png 为本版图片；design.interactions.light.png／design.interactions.dark.png 同步重导出，避免图片仍展示旧按钮。

## IDE 预览布局失效修复

用户截图显示按钮恢复浏览器默认样式、手机框架消失、搜索 SVG 异常放大。原设计依赖相对路径的外部 CSS；在模拟 IDE 文档地址下阻断相邻资源，复现 phone 从 flex 退回 block。未直接访问用户的 IDE 扩展，截图的实际资源加载错误仍无法读取。

修复：design.html、design.conversations.html、design.colors.html 内嵌所需 CSS；前两份内嵌 Milo PNG；静态及动态 SVG 明确 width／height。共享 CSS 保留为源文件，用 sync-design-assets.py 生成内嵌副本，避免手工维护多份主题。

验证：

- 三份 HTML 在模拟 HTTPS 预览地址、全部外部子请求被阻断时，手机布局正常，无外部资源请求；Milo 图片成功解码，SVG 宽度不超过按钮区域。
- 深色切换、主稿新建页打开，无 JS 异常。
- 新建入口、生成中限制、重复新建、输入／发送与窄屏检查再次通过。
- 禁用 JavaScript 时会话稿静态三屏与样式仍可见；列表动态填充及按钮交互仍需要预览器允许脚本，并未声称可以绕过扩展脚本限制。
- 未修改原生 App；真实 IDE 扩展内复验由用户重开预览后检查。


## 开发与打包前检查（2026-10-23）

上文为设计阶段的历史记录；用户随后已确认设计并授权开发及 IPA。本节记录实际实现验证，不将设计截图视为原生截图。

- 本地个人知识回归：49 项通过，包括旧资料无损迁移、字段幂等仍需来源、局部 patch／撤销、字段导出导入与时区校验。
- 本地搜索回归：15 项通过，包括通用／旧主题查询、URL 与 DNS 地址规则、真实链接解包、健康来源排序、RSS／CDATA、验证与异常结构、正文提取、隐私关键词与大小上限。
- 默认提示词预算检查通过：9031 / 9064；带个人技能、全插件场景也通过。未放宽原容量保护。
- 全部 Swift 文件通过 Linux Swift 前端语法解析。此项不等于 iOS SDK 类型检查或构建。
- 补充原生测试：会话草稿／删除回退／字段写入回读；搜索成功等待使用、失败保留与重试、取消后隔离下一次请求。等待 macOS CI 执行。
- 目录清理：删除 6 张从 HTML 导出的重复 PNG，约 2.4 MB；保留需求、方案、清单、配色规范、验证记录、三份自包含 HTML、两个 CSS 和样式同步脚本。上文 PNG 名称仅记录当时预览，不再作为交付文件。
- 未清理独立 Service 仓库、原始产品图片、历史需求、已有 IPA 或用户数据。

真机仍需确认：Safari 层级与返回停留、目标地区运营商网络、动态字体／VoiceOver、键盘和浅深色跳转。当前环境没有 iPhone 或本地 Xcode，不声称这些已验证。


### 实际联网样本（当前开发机网络，不代替中国大陆手机网络）

- 使用生产 Swift 解析器处理实际 Bing RSS 响应：`Swift language documentation` 保留 5 个匹配来源（含 docs.swift.org、developer.apple.com）；`hypertrophy training frequency` 保留 5 个匹配来源。
- 中文 `力量训练 频率 指南` 虽返回 HTTP 200，却出现无关 Microsoft 内容。区域参数、cn.bing.com 和其他关键词也有不相关结果。新增关键词相关性下限，拦截这类返回并提示改用精确公共关键词或继续浏览；不伪造来源，不标为“已核实”。
- 同时调查的 DuckDuckGo 返回验证页，Brave 返回 429；没有绕过验证，也没有擅自启用收费 API。这些通道未作为生产 fallback。
- 因此，已验证通用检索通道可用，但中文查询覆盖率、地域网络和来源相关性仍有局限。此限制保留在本轮验收清单，IPA 为测试版本，不能宣称搜索问题在所有网络中彻底解决。
- 搜索结果送回 Agent 前等待浏览容器完成关闭，避免上一轮 `onDismiss` 取消下一轮正文读取；新增原生连续搜索→阅读回归。

- 实际正文样本：NHS 成人运动指南返回 HTTP 200；生产正文解析器提取出 1 个来源、1678 字节节选。开发机下载的 gzip 响应先解压后交给解析器；iOS URLSession 负责 HTTP 内容编码解压。此项验证解析与真实内容，不等于已在手机验证传输。
- 清理后的三份 HTML 本地资源引用检查通过，无缺失 CSS／图片路径。


### 首轮原生回归及修正

- 提交 `01d759a`，CI [39911906824](https://github.com/MinJung-Go/Agentic-Moveliq/actions/runs/39911906824)：App 编译成功；662 项 XCTest 执行完成，4 个用例失败、共 7 个断言失败，未生成 IPA。
- 其中两项用例仍按已退役的来源白名单判断普通公开域名；更新为通用访问，同时验证近似域名不会获得健康来源或搜索引擎身份。
- 摘要预算回归发现新摘要长度过大：恢复每条标题 80 字／摘要 160 字与 10 条上限，保留原预算断言，并纳入便携测试。
- 字段写入集成测试发现 `profile_field` 被旧工具入口白名单拒绝：仅在 save 操作允许该参数，其他操作继续拒绝未知参数；字段值及 kind 继续由规则校验。
- 新增会话草稿／删除回退，以及搜索浏览面板的 4 项生命周期测试已在首轮原生测试通过。
- 搜索结果页面按确认稿使用独立来源卡片，显示标题、域名、编号和摘要；模型收到的内容仍受原摘要预算约束。
- 修订 `17708d3` 的中间 CI 已取消，避免构建已被后续修正替代的包；最终提交将完整重跑并单独记录。
