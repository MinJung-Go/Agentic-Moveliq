# 第 37 轮 · 实现方案与调查记录

这是待实施方案，非已上线能力。需求见 [requirements.md](requirements.md)。

## 1. 画像参考：借用字段边界，不复制存储架构

只读检查本机 `/zhangaimin/aim-a-evoagent-2026`，HEAD `0e612157`（以当时工作树内容为准，未读取 `.env` 或真实用户资料）。

| 参考源码 | 观察 | Moveliq 适配 |
| --- | --- | --- |
| `core/plugins/internal/profile/tool.py` | `update_user_profile` 支持 update／append；第一人称资料与场景经验分开 | 继续现有工具入口，增加明确字段语义；用户直接陈述是写入依据 |
| `utils/contracts/profile_fields.py` | 字段元数据集中维护，但兼容字段多于实际持久化字段 | 新 contract 明确五个有效字段，不照搬旧兼容字段 |
| `core/profiles/storage.py` 的 `_serialize_personal` | 实际只写姓名、称呼、时区、背景、偏好 | 五字段页面；空字段省略导出，UI 显示未填写 |
| 同文件 `_apply_layer_update` 与工具回执 | 根据写入后读回结果返回 written／dropped | SwiftData 保存成功且读回一致才能报“已记住” |
| `tests/unit/test_personal_background_field.py` | 覆盖背景多行文本序列化丢失与回读 | 增加 patch→持久化→重载→导出／导入的行为回归 |

参考仓库仍有 workspace／social_accounts／style_preference／generation_requirement 等兼容定义，但序列化不保存。其 API 文档存在旧描述；本方案以当前源码和行为测试为依据。

### 本机数据与 patch

- 五字段共用稳定 key、显示名、内容类型和导出规则，避免页面、工具、上下文各自维护字段列表。
- 保留 KnowledgeItem／来源／revision 机制；实施前评估在内容元数据中增加可选 `profileField` 的兼容解码方案。没有字段 key 的旧数据先完整读取，不能靠标题模糊匹配直接合并覆盖。
- 单值字段仅对明确关联的条目执行 revision 校验 patch；背景／偏好局部修改要针对原文片段。冲突时重读，不能让模型全量覆盖整份画像。
- 用户编辑、Agent 工具与后台候选整理共用持久化路径；提交前校验、保存后读回，失败不发成功通知。
- 同一事实不重复生成条目／版本；撤销仍遵守版本冲突与作用范围。
- SwiftData 为唯一数据源；USER.md 是 projection。训练设置仍从 CoachLifeProfile 读取，画像页只提供跳转。

## 2. 会话与记忆的信息层级

- 会话列表是独立 sheet：导航栏居中“对话”、右上角写字图标新建，搜索框在导航下方；正文按最近日期分组，当前会话以勾选与浅底表示。第二版不再使用大标题、副标题和实色大按钮。
- 点击新建直接进入空白聊天，保留 Milo 形象、统一输入栏与实时通话入口。用户在 2026-10-23 要求参考豆包；已查看 [2025 年 8 月公开手机截图](https://linux.do/t/topic/848679) 的列表右上角新建及新对话空态，不能由此推断当前 iOS 版本完全相同。最新稿见 [design.conversations.html](design.conversations.html)，用户已确认。
- 新建／切换只改变会话身份，个人知识库仍按账号共享；草稿、进行中的工具与待确认卡片保持会话归属。
- 聊天页导航栏右侧同时提供新建与通话，不能只在列表页放新建。两个入口分别提供可访问名称；窄屏优先收缩中间标题，不压缩触控区域。
- 记忆页默认“资料”，五字段形成可读个人档案；“记忆”“技能”保留检索和详情。把来源／版本作为按需展开的信息，不铺满主屏。
- 来源会话已删除仍显示“原会话已删除”与保留的证据，不生成失效跳转。
- HTML 展示编辑、未填写、空态、失败等状态。真实数据迁移与状态机要单独实现和测试，预览不替代原生验证。

## 3. 当前搜索为什么容易失败

静态证据（均为当前 App 源码）：

1. `Core/LLM/FitnessSearchTopic.swift` 只有七个主题，不能表达用户的一般问题。
2. `Core/LocalMilo/LocalBrowserPolicy.swift` 的 `searchURL` 强制拼接六个 `site:` 过滤词。
3. 同文件 `allows`／`sourceURL` 只允许固定站点；即使 Bing 返回正常公共网址，也会被过滤。
4. `Features/LocalMilo/LocalBrowserView.swift` 只提取 `li.b_algo` 内的 `h2 a` 与 `.b_caption`；页面改版、移动布局或验证码可能得到空集合。
5. 过滤后没有 URL 与 DOM 根本没抽到行被合并成同一种失败提示，无法区分真实无结果。

第 36 轮已经修复内容规则中的 WebKit 正则编译问题；这不等于解决了本轮的范围限制与提取脆弱性。没有用户失败时的 DOM／网络诊断，不能断言真机唯一根因。

### 新通道提案

- 将请求变成 `query + purpose(general/health) + count`。通用公开关键词不含整个聊天上下文；旧 `search_public_fitness(topic)` 暂作适配入口，防止旧工具流程骤断。
- 本轮先评估不新增收费依赖的独立公开搜索与正文读取通道，提取逻辑与 WebView UI 解耦。浏览用 Safari，读取用独立 transport／parser；不能从 Safari 回读 DOM，也不能把 Safari 的登录／验证状态假定为读取通道共享。
- 评估必须包含目标网络实测与脱敏 HTML fixtures；若只有模拟页面成功，不算搜索可用。需要服务端提供商时再明确范围、费用与部署依赖，不在本轮设计稿中假装已经解决。
- 每个结果记录 query/requestID、标题、规范化 URL、摘要、来源类型；`snippetOnly` 与 `bodyAvailable` 分开。健康优先按相关性与机构／文献类型排序，普通公共来源仍能进入结果。
- 页面无结果须有可识别证据；空 DOM 返回 extractionUnavailable。验证码、networkFailure、cancelled 分别返回；浏览可以继续，Milo 必须诚实说明尚未读取。
- 每次查询独立 generation；旧请求、旧页面回调不能覆盖新结果。失败／超时不关闭用户正在浏览的 Safari；用户主动关闭不误判成功。
- 公开 URL 校验与来源质量评分分离；协议、凭据、本地地址、私网 IPv4／IPv6、重定向、响应类型与尺寸独立限制。未来若采用服务端抓取，必须覆盖 DNS 解析到私网及重绑定，不能只查字符串域名。
- 不绕过验证码，不把付费墙、导航或验证页当正文。通用搜索并不承诺所有网页都可自动提取。

## 4. 配色不一致的证据与迁移

`Core/Design/Theme.swift` 同时存在三种背景：`canvas` 浅色为系统分组灰、`conversationCanvas` 为系统白、`Journal.canvas` 为 `#FFFEFA`；深色分别为 `#161719` 与 `#191A18`。

| 页面 | 当前引用 | 本轮目标 |
| --- | --- | --- |
| TodayView、RecordsView | Journal.canvas／Journal.action | 迁移到全局语义名称，保持暖白阅读体验 |
| PlanView、InsightsView、TrendsView、NutritionAnalysisView、SettingsView | Theme.canvas | 统一 page／surface，消除蓝灰与暖灰切换 |
| CoachChatView、KnowledgeChatViews、PersonalKnowledgeView | 聊天底／系统 List 或 Form 默认样式混用，需逐处核对 | 背景、列表、导航、输入控件共用 token |
| RealtimeCallView、照片预览 | 黑色媒体背景 | 保留媒体语义，不机械替换 |

迁移顺序：明确 [语义配色](design-system.md) → 共享组件与列表底 → 五个 Tab → 详情与弹层 → 浅深色和可访问性检查。对现有 `Theme.Journal` 建兼容别名，逐步消除独立值；不要简单全局字符串替换颜色。

## 5. 交付顺序

1. 新文档、设计稿、搜索最小复现。
2. 确认视觉与交互；验证独立检索通道，失败也明确记录。
3. 分批实现会话／资料、主题、搜索；每批针对行为验证。
4. 用户授权提交与构建后再运行正式 iOS CI；真机检查另记。


## 确认后的实现（2026-10-23）

- 搜索使用 Bing RSS 的公开结果，替代依赖 `li.b_algo` 的页面 DOM 提取；先拦截与关键词明显不符的返回，普通查询保留结果次序，健康查询将命中的权威机构来源前排，不排除其他公开站点。沿用原工具名兼容历史调用，参数扩展为 `query` / `purpose`，旧 `topic` 仍可解码。
- Safari 仅负责浏览；独立 URLSession 读取结果和正文，无 Safari Cookie／DOM 权限。用户关闭 Safari 后查看读取状态，点「使用搜索结果」才交给 Milo。验证、空结果、解析失败和网络失败保留页面，支持重试；取消、超时和下一次请求通过代际隔离。三分钟交互超时后终止本次工具等待，但浏览入口仍保留。
- 正文只支持公开 UTF-8 HTML；需要登录、JS 渲染、验证、其他编码或附件时如实提示，不假称已读取。读取通道限制 HTTPS、无凭据、443 端口，DNS 解析排除私网／保留地址，每次重定向重新检查，最多三跳，响应流限制 2 MB。DNS 检查为连接前校验，不宣称网络层固定地址防重绑定。
- 公开关键词最长 160 字，拒绝常见联系方式／凭据模式，并检查是否包含已保存的姓名或称呼；查询内容不附加个人上下文。规则无法穷尽所有敏感自然语言，模型提示同时要求只提取最小公共关键词。
- 五字段元数据保存在既有 KnowledgeContent；旧内容只做精确、无冲突映射，未知内容、重复字段和无效旧时区保留。更新仍使用已有版本化 patch 与持久化后读回。USER.md 仍为导出视图。
- 对话文字草稿保存在 ChatConversation，复用无消息且无草稿的空会话。聊天页当前只承载文字／语音转文字，照片附件仍属于原记一笔入口，本轮未新增聊天附件。
- 暖色主题收敛到共享 token，同时为原生 List／Form 的行和滚动底色接入主题。成功／危险分类色与相机、视频、Safari 保留原语义。
