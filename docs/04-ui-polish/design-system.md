# Moveliq 设计系统（DESIGN.md）

- 版本：2.2 · 2026-10-15（纠正历史文档与当前 Theme 的差异）
- 用途：共用组件与主题的现行基线；历史截图不代表当前实现。第 33 轮[组件统一需求](../33-home-report-readability/requirements.md)与[交互稿](../33-home-report-readability/design.html)已确认并接入 SwiftUI；0.5.15 的 CI 已通过，后续 R6 的原生 CI 与真机验证独立记录于本轮清单。
- 参考：[awesome-design-md](https://github.com/VoltAgent/awesome-design-md) 的 `apple` 条目 · Apple Human Interface Guidelines · Liquid Glass（iOS 26）

## 第 33 轮 R6 局部应用（第五版已确认）

2026-10-15 用户确认第五版及首页 24pt 对齐细化，已接入代码；本次原生构建和 504 项 XCTest 已通过，IPA 结果见本轮清单，真机效果待验证；下文通用规则仍适用于其他页面。R6 局部差异如下：

- 首页与记录页使用 `Theme.Journal`：近白暖底（浅 `#FFFEFA` / 深 `#191A18`）、课程表面（`#F3F0E8` / `#262723`），正文、次级文字、来源和描边各有对应浅深色值。不改变聊天、报告、全局 card 或 RecordKind 语义色映射。
- 页面与首页输入栏外边距为 24pt，课程容器圆角 16pt。首页快捷对话为 12pt 圆角的中性细描边按钮；不将描边推广到内容卡片。
- 记录行不套外层卡片：42pt 时间栏 + 16pt 间隔 + 连续内容栏。名称 17pt/500，项数 13pt/400，摘要 14pt/400，来源和时间 12pt/400；字号随动态字体缩放。极大辅助功能字号将时间移到内容上方，分隔线同步通栏。
- 第一项名称用于扫读，全文保留在详情、搜索和辅助朗读中。照片仅用 hasPhoto 标记，来源和只读语义保留；R6 列表来源随行内 Text 换行，详情继续使用原有 RecordSourceLabel。
- 记录筛选默认视觉高度 32pt、触控高度不少于 44pt；辅助功能字号下随内容扩大。搜索与原生 List 的分组/滑动删除保留，分隔线从正文起点开始。
- 消息输入组件形状与行为不变，通过参数为首页指定 24pt 外边距与局部填充；聊天及记一笔仍默认 16pt。

## 1. 视觉基调

一个**数据工具**，不是内容产品。使用者打开它只有三个动作：记一笔、看一眼、问教练。界面存在的意义是让这三件事更快、更可信，而不是更好看。

因此采用 Apple 官网那套纪律的 iOS 版本：**UI 后退，内容说话**。

- **克制**：一个强调色、一套圆角阶梯、一处阴影规则。没有装饰性渐变、没有彩色图标底、没有拟物质感
- **排版承担层次**：靠字重与字号建立主次，而不是靠颜色与边框
- **深色优先**：默认深色下设计，浅色是同一套语义色的换挡，不是两套设计
- **数字是主角**：所有数值等宽对齐，变化时有过渡，不跳动

**三条不做**：不加第二个强调色 · 不给卡片加阴影 · 不用渐变当装饰。

## 2. 颜色

### 强调色（唯一）

| 角色 | 深色 | 浅色 | 用途 |
|---|---|---|---|
| `accent` | `#DBAB65` | `#F4B353` | 主要动作与品牌点缀，以 AccentColor 资源为准 |
| `onAccent` | `#241600` | 同 | 暖橙实底上的文字、图标与进度指示 |

**只有这一个可交互色**，没有第二个，也没有"强调色的淡色版本"当装饰底用。

强调色**不做大面积填充**。整屏橙色只应出现在：一个主按钮 + 若干小面积徽标/图标。

### 语义色（内容分类，非交互）

| 类型 | 色 | 用途 |
|---|---|---|
| 训练 | 品牌暖橙 `Theme.accent` | 训练记录、课程、容量类图表 |
| 饮食 | `systemGreen` | 饮食记录、热量达标 |
| 身体 | `systemBlue` | 体重/指标、恢复类图表 |
| 笔记 | `systemGray` | 待归类笔记、只读的 HealthKit 记录 |
| 警示 | `systemYellow` | 待归类提示、恢复不足 |
| 危险 | `systemRed` | 删除、错误及需警示的中止；普通停止生成可用中性控件 |

**按语义选择前景：较深实色底配白色符号；暖橙/亮黄底配深色符号；中性表面可用语义色图标。** `SymbolChip` 对暖橙/亮黄默认使用 onAccent，其余语义色使用白色；调用方可以显式指定前景。

> **不要**把语义色刷成 16% 淡底、再用同色写字。那是「AI 生成界面」最典型的套路 ——
> 语义色被摊薄成一块谁也看不清的底，同色文字又丢掉了对比度，层次和对比一起没了。
> Apple 的设置页是**实色方块 + 白色符号**，警示行是**中性表面 + 彩色图标**。
> 一句话：**要么实色，要么中性，没有中间态**。

**语义色只表达"这是什么"，不表达"可以点"** —— 这是和强调色的分工。

### 表面

| 角色 | 深色 | 浅色 |
|---|---|---|
| `canvas` | `#161719` | 系统 systemGroupedBackground |
| `card` | `#232528` | 系统 secondarySystemGroupedBackground |
| `cardNested` | `#2C2E32` | 系统 tertiarySystemGroupedBackground |
| `hairline` | `white @ 8.5%` | `black @ 5.5%` |
| `label` | `#FFFFFF` | `#000000` |
| `labelSecondary` | 当前 Theme 约 RGB 0.71/0.71/0.75 | 当前 Theme 约 RGB 0.35/0.35/0.38 |
| `labelTertiary` | 系统 tertiaryLabel | 系统 tertiaryLabel |

正文色直接用系统 `label`（浅色下即纯黑 / 深色下即纯白）—— 那是 iOS 自己的做法。

> 一度想按 apple.com 的做法把正文改成 `#1D1D1F`（近黑墨）。那是**网页**正文的规则：
> 浏览器里纯黑压白底太生硬。iOS 上 `label` 本来就是纯黑，改成近黑墨反而偏离系统基准，
> 而且要为了一点点色差把自定义色铺到每个文本视图上。**不采用** —— 同 §7 的卡片描边，是同一类误搬。

## 3. 排版

SF Pro 全系统字体，**不引入自定义字体**。通用字重阶梯 **400 / 600 / 700**；已确认的 R6 Journal 名称和课程标题局部采用 500，见上文。

| 角色 | 字号 | 字重 | 用途 |
|---|---|---|---|
| `largeTitle` | 34 | 700 | 页面大标题（导航栏折叠为 17 semibold） |
| `title3` | 20 | 600 | 卡片主标题、报告引文 |
| `headline` | 17 | 600 | 列表主行、按钮文字 |
| `body` | 17 | 400 | 正文（**17 不是 16** —— 阅读而非扫视的节奏） |
| `subheadline` | 15 | 400 | 次要行 |
| `footnote` | 13 | 400 | 辅助说明 |
| `caption` | 12 | 400 | 时间戳、标签 |
| `caption2` | 11 | 600 | 徽标 |
| `metric` | 21–26 | 700 | 指标数字，`.monospacedDigit()` |

**规则**：
- **字距一律 0**。西文大标题可以按 Apple 的做法收一点（`-0.2 → -0.4`），但本项目界面以中文为主，
  汉字字面本来就是等宽方块，**加负字距会让笔画相贴、整行发挤** —— 设计稿里踩过一次，全部清零。
- 数字一律 `.monospacedDigit()` + `.contentTransition(.numericText())`
- 动态字体：使用 `.font(.body)` 等语义字号，不写死 point size

### Markdown 在气泡里的排版

AI 回复是 Markdown，但气泡不是文档。规则：**保留结构，去掉层级**。

| 语法 | 渲染 |
|---|---|
| `#` ~ `######` | 不渲染为标题，做成 **17pt / 600** 的加粗行（气泡里不需要六级标题） |
| `- ` / `* ` | 转真项目符号 `•`，左缩进 17pt，符号用 `labelTertiary` |
| `1. ` | 转序号，`tabular-nums` 对齐，同样悬挂缩进 |
| `**粗体**` | `600` 字重（不用 700，正文里 700 太吵） |
| `` `代码` `` | 等宽 14pt + `chip` 底 + 圆角 5，用于重量、组次这类数值 |
| `---` | 转 0.5pt 分隔线，用于「问题 / 方案」分段 |
| 段落 | 行高 1.5，段间距 6pt |

> 现状：`MarkdownText` 把 `#` 和 `- ` 降级成了纯文本。实现时按本表补齐，且**渲染失败必须回退为原文**，不能因为格式问题丢内容。

## 4. 圆角

阶梯只有四档，按角色取，**不出现中间值**：

| 档 | 值 | 用途 |
|---|---|---|
| `compact` | 8 | 紧凑控件、内联标签底 |
| `inner` | 12 | 卡片内嵌元素（指标块、字段行、缩略图） |
| `card` | 20 | 所有卡片、sheet |
| `pill` | `Capsule()` | 按钮、输入框、分段控件、徽标 |

嵌套时沿阶梯降档（卡片 20 → 内嵌 12 → 紧凑 8），而不是按共边公式算同心值。

**实现**：连续曲率 `RoundedRectangle(cornerRadius:style: .continuous)`，不用 `.circular`。

## 5. 间距

基准 8，结构值只用 `4 / 8 / 12 / 16 / 24 / 32`。

| Token | 值 | 用途 |
|---|---|---|
| `xs` | 4 | 图标与文字 |
| `s` | 8 | 行内元素 |
| `m` | 12 | 卡片之间 |
| `l` | 16 | 页边距、卡片内边距（列表卡） |
| `xl` | 24 | 区块之间 |
| `xxl` | 32 | 空态、大留白 |

**触控区一律 ≥ 44pt**，图标按钮用 `.frame(minWidth:44, minHeight:44)` 或 `.contentShape` 扩展，视觉尺寸可以更小。

## 6. 图标（本轮的改进重点）

### 来源

| 场景 | 用什么 |
|------|--------|
| **App 内** | **SF Symbols**（系统内置，无需引入任何依赖）—— 它就是 Apple 自家那套图标，光学尺寸随字号自动适配 |
| **设计稿（HTML）** | **[Ionicons](https://ionicons.com)（MIT）** —— SF Symbols 不可再分发。Ionicons 的实心字形是经典 iOS 观感（iconfont 上流传的 `ios-*` 那套就是它），覆盖全、体积小、MIT 可商用 |

> 为什么不自己在 SVG 里画：手绘近似（均匀描边、无光学层次）和系统图标放一起会立刻显廉价 —— 这是 v2.0 初稿被否掉的原因。**专业图标集的路径是设计师按光学尺寸逐档调过的，不要用代码去模仿。**

### 原则

Apple 的图标纪律：**SF Symbols 是表意工具，不是装饰**。三条落地规则：

1. **同一概念永远同一个符号** —— 训练在今日/记录/详情/课程表里都是 `dumbbell.fill`，不换
2. **字重按场景选，而不是统一描边** —— 图标容器与 Tab 用 **Fill/Solid**（Apple 设置页那种实心字形）；与文字并排的轻量标记用 Regular/Bold；空态大尺寸用 **Duotone/Hierarchical**（双层比单色实心耐看）
3. **渲染模式分层** —— 多层符号用 `.symbolRenderingMode(.hierarchical)` 产生深度，而不是给图标加渐变或阴影

### 禁用

- **不用 Emoji 当图标**：彩色、基线随系统字体变化、无法着色、无法响应动态字体
- **不给图标加渐变或投影**：会破坏渲染模式，且在深色下变脏
- **不自制徽标/外框**：容器统一用色块，不画在符号里

### 符号表

| 概念 | 符号 | 变体 | 渲染模式 | 语义色 |
|---|---|---|---|---|
| 训练记录 / 课程 | `dumbbell.fill` | fill | hierarchical | orange |
| 饮食 / 热量 | `fork.knife` | outline | hierarchical | green |
| 体重 / 身体指标 | `scalemass.fill` | fill | hierarchical | blue |
| 待归类笔记 | `note.text` | outline | hierarchical | gray |
| HealthKit 运动 | `figure.run` | outline | hierarchical | gray |
| 睡眠 | `moon.fill` | fill | hierarchical | blue |
| HRV | `waveform.path.ecg` | outline | monochrome | orange |
| 步数 / 活动量 | `figure.walk` | outline | hierarchical | green |
| 静息心率 | `heart.fill` | fill | hierarchical | red |
| 思考过程 | `brain` | outline | hierarchical | orange |
| AI / 生成 | `sparkles` | outline | hierarchical | orange |
| 今日 Tab | `house.fill` | fill | monochrome | accent |
| 记录 Tab | `list.bullet` | outline→fill | monochrome | accent |
| 课程表 Tab | `calendar` | outline→fill | monochrome | accent |
| 洞察 Tab | `chart.bar.fill` | fill | monochrome | accent |
| 设置 Tab | `slider.horizontal.3` | outline | monochrome | accent |
| 只读 | `lock.fill` | fill | hierarchical | tertiary |
| 连接正常 | `checkmark.circle.fill` | fill | hierarchical | green |
| 停止生成 | `stop.circle.fill` | fill | hierarchical | red |
| 调整计划 | `wand.and.stars` | outline | hierarchical | orange |

### 设计稿 ↔ App 对照

设计稿用 Ionicons，App 用 SF Symbols，两边必须**同义同形**，不许一处分叉：

| 概念 | 设计稿（Ionicons） | App（SF Symbols，iOS 17 全部可用） |
|---|---|---|
| 训练 | `barbell` | `dumbbell.fill` |
| 饮食 | `restaurant` | `fork.knife` |
| 身体指标 | `scale` | `scalemass.fill` |
| 笔记 | `document-text` | `note.text` |
| 运动（只读） | `walk` | `figure.run` |
| 睡眠 | `moon` | `moon.fill` |
| HRV | `pulse` | `waveform.path.ecg` |
| 步数 | `footsteps` | `figure.walk` |
| 心率 | `heart` | `heart.fill` |
| 思考过程 | `bulb` | `brain` |
| 热量 | `flame` | `flame.fill` |
| 目标 | `locate` | `target` |
| 调整计划 | `color-wand` | `wand.and.stars` |
| 拖拽排序 | `reorder-three` | `line.3.horizontal` |
| 空态（大尺寸） | `*-outline` 变体 | `.hierarchical` 渲染 |

### 图标容器

```
36×36 · 圆角 12 · 语义色实底 + 对应前景（深底白色、暖橙底 onAccent）· 符号 17–19pt
紧凑版：30×30 · 圆角 8 · 符号 15pt
警示类（黄色）用深色符号 —— 白字在黄底上读不出来
```

## 7. 深度与层次

**整个系统只有一个阴影**，且只用于浮层与导航层：

| 层 | 处理 |
|---|---|
| 内容卡 | **只有卡面色，没有描边**。卡片与页面的底色差本身就是分层 |
| 内嵌块 | 换 `cardNested` 表面色 |
| 导航层（Tab 栏 / 输入条） | **通栏实底 + 顶部 0.5pt 分隔线** |
| 模态 sheet | 系统 sheet，内容用 `card` 表面 |

**关于卡片描边**：一度给卡片加了 1pt hairline —— 那是从 Apple 官网（**网页**）的
utility card 规则搬来的。iOS 的分组列表**没有边框**，靠 `secondarySystemGroupedBackground`
与 `systemGroupedBackground` 的底色差分层。加了描边就会显"web 味"。

**关于导航层**：试过 iOS 26 的浮动玻璃胶囊，但**内容会从胶囊的缝隙与边距里透出来** ——
浮动玻璃的前提是 `backdrop-filter` 生效，一旦模糊不渲染（无 GPU 环境、部分浏览器），
背后内容就直接显形。经典 iOS 的 Tab 栏本来就是通栏实底，也更符合"极简"。
玻璃是加分项，不该是结构的一部分。

> **真机落地方式（2026-09-13 定）**：上面那段现象出在 HTML 设计稿（`backdrop-filter` 不可靠），
> 真机上的系统 Tab 栏本身不漏内容。但 CI 用的是 **Xcode 26 / iOS 26 SDK**，App 在 iOS 26 上
> 会被默认套上悬浮玻璃胶囊 —— 与「通栏实底」不符。因此在 `Info.plist` 里设了
> `UIDesignRequiresCompatibility = YES`，把全 App 外观锁在 iOS 26 之前那一套。
>
> 代价是同时放弃 iOS 26 的其他新外观。这是**有意为之**：本设计系统整套语法
> （inset grouped 列表、通栏 Tab 栏、卡片无描边）都建立在经典 iOS 上。

层次靠**表面色变化**建立，不靠阴影也不靠描边。

## 8. 组件

### 按钮

| 类型 | 样式 | 用途 |
|---|---|---|
| `primary` | 暖橙实底 + onAccent 深字 + inner 圆角 12；基准高度至少 50，17pt 半粗体 | 主要提交动作（保存、加入课程表、生成报告）；同一决策区域只突出一个 |
| `secondary` | 无底 + 主文字色 + 15pt 半粗体，操作范围至少 44pt | 次级动作（换个方案、不采用）；快捷对话可使用中性底作为独立变体 |
| `plain` | 无底 + 操作色/次级色，操作范围至少 44pt | 文字级动作（复制、移除）；PlainActionButtonStyle 自带 44pt 最小操作范围 |
| `destructive` | 红色语义文字或系统 destructive 按钮 | 删除等破坏性动作；停止生成使用独立停止控件，不等同于删除 |

**按下态统一轻量透明度反馈**：主按钮约 0.8、次按钮约 0.7；不强制缩放。支持减弱动态效果。**不使用渐变填充**。

消息发送保留 36pt 圆形视觉、44pt 操作范围；不会随主按钮改成全宽矩形。忙碌时禁止重复提交，加载指示器继承当前前景色；禁用用中性底/次级文字，不固定画白色加载点。开始训练与课程修改确认共用 PrimaryButtonStyle，删除确认保持独立红色语义。

### 卡片

```
背景 card · 圆角 20 · 内边距 16 · 无描边、无阴影 · 卡间距 12
标题行：12pt 600 labelSecondary + 右侧可选说明（11pt tertiary）
```

### 列表（iOS inset grouped）

这是让界面「像原生 App」最关键的三个细节，缺一个就显网页感：

```
分组标题：放在卡片【外面】—— 13pt / 600 / labelSecondary，左侧与卡片文字对齐
         右侧可跟数量与日期（13pt / labelTertiary / 等宽数字）
卡片    ：卡面色 + 圆角 20 + 内边距 16，【没有边框】
行      ：左 图标容器（36 或 30）
         中 主行 17/600 + 副行 13/labelSecondary
         右 12pt labelTertiary 的等宽时间戳，或徽标
         垂直内边距 11
分隔线  ：0.5pt，【左缩进 48】与主行文字对齐，不通栏
```

- 分组标题**不要**放进卡片里当第一行 —— 那是网页卡片的做法
- 分隔线不通栏，要从图标之后开始，与文字左对齐
- 卡片之间留 12pt，分组之间留 24pt

### 徽标

```
默认：11pt 600 · padding 3×8 · 圆角 8 · chip 中性底 + labelSecondary 字
强调：同一个形状换实色底 + 白字（黄底配深字，白字读不出来）
```

徽标是**标注**不是**按钮**，默认中性；只有需要它跳出来时才用实色。第 33 轮将“AI 估算”收为无底的次级来源文字，列表/详情共用 RecordSourceLabel；待归类仍保留警示语义。

### 思考区（教练对话）

思考过程有个容易做砸的地方：**折叠态被做成了一个空盒子**。它没有内容却占了整行宽度和
40+pt 高度，里面只放一行小字 —— 又重又空，第一眼像加载失败的占位。

规则：**有内容才有容器，没内容就只是一行字。**

| 状态 | 形态 |
|---|---|
| 折叠（已结束） | **无容器、无背景**。`brain + 思考过程 · 12s + ›`，12pt / 600 / `labelTertiary`，宽度贴合文字（`fit-content`）。像一行"查看详情" |
| 展开 / 思考中 | 才有容器：`cardNested` 底、圆角 **12**（`inner` 档）、内边距 11×13；表头转强调色 + 600；正文 12pt / `labelSecondary` / 行距 9pt |
| 生成中 | 表头追加已用秒数（等宽数字）与三点脉冲。**不做扫光/流光** —— 那是装饰，且每秒重绘 |

> 判据：把折叠态截图单独拎出来看，如果它像一个"控件"而不是一句"说明"，就是做重了。

### 空态

```
符号（40pt，tertiary）→ 标题 17/600 → 说明 13/secondary（居中，最多两行）→ 可选一个主按钮
```

## 9. 图表

图表是**数据表达**，不是装饰。一套配色、一套形态，全 App 的图看起来必须像同一个人画的。

### 配色

| 序列 | 色 | 用途 |
|---|---|---|
| 训练 | `ChartColor.training`（当前为 Theme.accent） | 训练容量、估算 1RM |
| 身体 | `systemBlue` | 体重、体脂、腰围 |
| 恢复 | `systemPurple` | 睡眠、HRV |
| 目标 / 基线 | `systemGray` | 目标线、均值线、未记录的日子 |

**规则**：
- 一张图最多 **3 个色相**；序列多于 3 个时用**同色相深浅**区分（100% / 60% / 32%），不用彩虹配色
- 目标线用**灰色虚线**（`6 5`），不用彩色 —— 目标不是数据序列
- 柱状图只让**被强调的那一根**用实色，其余用 `chip` 中性灰；"哪根是本周"靠颜色而不是靠标注
- 折线 2.2pt 圆角端点；面积填充同色 14%
- 坐标轴文字 9.5pt `labelTertiary`，只画水平网格线，不画竖线

### 形态选择

| 数据 | 形态 |
|---|---|
| 连续时间序列（体重、1RM） | 折线 + 面积 |
| 离散周期比较（每周容量、每日热量） | 柱状 |
| 达标率 / 单值进度（今日概览、计划完成度） | 进度环 |

## 10. 动效与反馈

| 场景 | 处理 |
|---|---|
| 数字变化 | `.contentTransition(.numericText())` |
| 列表插入 / 删除 | `.snappy` + `.transition(.move(edge:).combined(with: .opacity))` |
| 卡片首次出现 | 透明度渐入，错峰 40ms，位移不超过 8pt |
| 按钮按下 | 轻量透明度反馈，按需触感；减弱动态效果时避免附加动画 |
| 操作成功 | `Haptics.success()` + 顶部 toast |
| 流式输出 | **节流 60ms 合并刷新**，避免每个 chunk 重建 `AttributedString` |
| 减弱动态效果 | `accessibilityReduceMotion` 为真时全部降级为无动画、无错峰 |

## 11. Do / Don't

**Do**
- 用排版建立层次：大标题 34/700，**中文不设负字距**（负字距只给西文/数字）
- 一屏只放一个主按钮
- 语义色只标记"这是什么"，强调色只标记"可以点"
- 图标用 `.hierarchical` 渲染模式产生深度
- 所有间距取自 4/8/12/16/24/32

**Don't**
- 不用 Emoji 当图标
- 不加第二个强调色、不做装饰性渐变（按钮、进度条、柱状图一律实色）
- **不把语义色刷成淡底再用同色写字** —— 要么实色底 + 白符号，要么中性底 + 彩色图标
- 不给卡片/按钮/文字加阴影
- 不用字重 500
- 不混用圆角值（8 / 12 / 20 / pill 之外不出现别的值）
- 不把强调色铺满整块背景
- **不给中文加负字距**（汉字字面是等宽方块，负字距会让笔画相贴）
