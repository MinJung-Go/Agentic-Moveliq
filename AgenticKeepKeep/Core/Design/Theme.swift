import SwiftUI
import UIKit

/// 共享设计token；第九轮视觉调整见 docs/09-ui-refinement/design-notes.md。
enum Theme {

    // MARK: - 强调色（全 App 唯一的交互色）

    static let accent = Color("AccentColor")
    static let onAccent = Color(red: 36.0 / 255, green: 22.0 / 255, blue: 0)
    static let userBubble = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)
            : UIColor(red: 0.89, green: 0.89, blue: 0.92, alpha: 1)
    })

    /// 次级按钮底（强调色淡底 + 强调色字）。
    ///
    /// **只允许出现在按钮上** —— 那是 iOS tinted button 的固有样式。不要把这个做法
    /// 搬到卡片、徽标、警示条上：语义色被摊薄成一块看不清的底，同色文字又丢掉了对比度。
    static let accentSoft = accent.opacity(0.16)

    // MARK: - 表面

    /// 页面底色：浅色保留系统分组底色，深色使用炭黑 #161719。
    static let canvas = surface(light: .systemGroupedBackground, dark: 0x161719)
    /// 聊天与报告正文：浅色白底、深色炭黑。
    static let conversationCanvas = surface(light: .systemBackground, dark: 0x161719)
    /// 首页局部表面：与课程容器建立柔和层次，不改聊天及全局卡片。
    static let homeCanvas = surface(light: UIColor(red: 250/255.0, green: 250/255.0, blue: 252/255.0, alpha: 1), dark: 0x161719)
    static let homePanel = surface(light: UIColor(red: 240/255.0, green: 240/255.0, blue: 244/255.0, alpha: 1), dark: 0x232528)
    /// 卡片：浅色白底，深色 #232528。
    static let card = surface(light: .secondarySystemGroupedBackground, dark: 0x232528)
    /// 卡片内嵌块：指标块、字段行、缩略图、思考区容器（浅色 `#F2F2F7` / 深色 `#2C2E32`）
    static let cardNested = surface(light: .tertiarySystemGroupedBackground, dark: 0x2C2E32)
    /// 中性填充：徽标底、未强调的柱、行内代码、图表里的非重点序列
    static let chip = surface(light: .tertiarySystemFill, dark: 0x232528)

    private static func surface(light: UIColor, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: CGFloat((dark >> 16) & 0xFF) / 255,
                          green: CGFloat((dark >> 8) & 0xFF) / 255,
                          blue: CGFloat(dark & 0xFF) / 255, alpha: 1)
                : light.resolvedColor(with: trait)
        })
    }

    /// 0.5pt 分隔线与描边：深色用白 8.5%、浅色用黑 5.5%。
    ///
    /// 只用于**导航层顶部分隔线**与**列表行分隔线**。不要拿它给卡片描边 ——
    /// iOS 的分组列表本来就没有边框，靠底色差分层；加了描边会显"web 味"。
    static let hairline = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.085)
            : UIColor.black.withAlphaComponent(0.055)
    })

    // MARK: - 语义色（内容分类，不参与交互）

    static let positive = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemYellow)
    static let danger = Color(uiColor: .systemRed)
    static let info = Color(uiColor: .systemBlue)

    static let secondaryLabel = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.71, green: 0.71, blue: 0.75, alpha: 1)
            : UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1)
    })
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)

    // MARK: - 间距（基准 8，结构值只用这几档）

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - 圆角（只有这几档，不出现中间值；胶囊直接用 Capsule()）

    enum Radius {
        /// 紧凑控件、内联标签、徽标
        static let compact: CGFloat = 8
        /// 卡片内嵌元素（指标块、字段行、缩略图）
        static let inner: CGFloat = 12
        /// 所有卡片与 sheet
        static let card: CGFloat = 20
    }

    // MARK: - 字体角色
    //
    // 字重阶梯只有 400 / 600 / 700 —— **不使用 500**，中间强调一律 600。
    // 用系统语义字号而非写死 point size，以跟随动态字体。
    // **一律不设负字距**：界面以中文为主，汉字字面本来就是等宽方块，收字距会让笔画相贴。

    enum Font {
        static let largeTitle = SwiftUI.Font.largeTitle.weight(.bold)   // 34
        static let title = SwiftUI.Font.title3.weight(.semibold)        // 20
        static let headline = SwiftUI.Font.headline                     // 17 semibold
        static let body = SwiftUI.Font.body                             // 17
        static let subheadline = SwiftUI.Font.subheadline               // 15
        static let footnote = SwiftUI.Font.footnote                     // 13
        static let caption = SwiftUI.Font.caption                       // 12
        static let badge = SwiftUI.Font.caption2.weight(.semibold)      // 11

        /// 报告引文：衬线（New York）。系统自带，不是引入外部字体 ——
        /// 编辑场景的语感，和正文的 SF 拉开距离（FR14.3）
        static let quote = SwiftUI.Font.system(.body, design: .serif)
        static let quoteLarge = SwiftUI.Font.system(.title3, design: .serif).weight(.semibold)

        /// 指标数字：等宽，变化时不跳动
        static let metric = SwiftUI.Font.title2.weight(.bold).monospacedDigit()       // 22
        static let metricSmall = SwiftUI.Font.headline.monospacedDigit()              // 17 semibold
        static let mono = SwiftUI.Font.caption.monospaced()                           // 12
        static let monoSmall = SwiftUI.Font.caption2.monospacedDigit()                // 11
    }
}

/// 图表配色。全 App 的图必须像**同一个人画的**，所以各图表从这里取，不要各写各的。
///
/// 纪律（设计系统 §9）：一张图最多三个色相；序列多于三个时用同色相深浅区分，不用彩虹配色；
/// 目标线与均值线用灰色，**不是**彩色 —— 目标不是数据序列。
enum ChartColor {

    static let training = Theme.accent
    static let body = Theme.info
    static let recovery = Color(uiColor: .systemPurple)
    /// 目标线 / 均值线 / 未记录的日子
    static let baseline = Color(uiColor: .systemGray)

    /// 同色相的三档深浅，给「同一指标的不同序列」用
    static let strong = 1.0
    static let medium = 0.6
    static let faint = 0.32
}

// MARK: - 记录类型 → 符号与语义色

/// 一种记录类型对应固定的符号与语义色，全 App 一致（今日 / 记录 / 详情 / 课程表不换）。
enum RecordKind: String, CaseIterable, Identifiable {
    case workout
    case meal
    case body
    case note
    /// HealthKit 同步来的运动记录（只读）
    case health

    var id: String { rawValue }

    /// 与文字并排时用的轮廓变体（不抢文字）
    var symbol: String {
        switch self {
        case .workout: return "dumbbell"
        case .meal: return "fork.knife"
        case .body: return "scalemass"
        case .note: return "note.text"
        case .health: return "figure.run"
        }
    }

    /// 图标容器与 Tab 栏用的实心变体（部分符号没有实心版，退回轮廓）
    var filledSymbol: String {
        switch self {
        case .workout: return "dumbbell.fill"
        case .meal: return "fork.knife"
        case .body: return "scalemass.fill"
        case .note: return "note.text"
        case .health: return "figure.run"
        }
    }

    /// 图标容器的实色底
    var color: Color {
        switch self {
        case .workout: return Theme.accent
        case .meal: return Theme.positive
        case .body: return Theme.info
        case .note, .health: return Color(uiColor: .systemGray)
        }
    }

    var displayName: String {
        switch self {
        case .workout: return "训练"
        case .meal: return "饮食"
        case .body: return "身体指标"
        case .note: return "随笔"
        case .health: return "运动记录"
        }
    }
}

// MARK: - 图标

/// 语义色图标容器；暖橙/亮黄使用深色前景，其余保留调用方语义。
///
/// 不用 Emoji（彩色、基线随字体变化、无法着色）、不加渐变与投影（会破坏渲染模式）、
/// 不用淡底同色符号（那是「AI 味」的来源，见 `Theme` 顶部第 3 条）。
struct SymbolChip: View {

    let symbol: String
    var tint: Color = Theme.accent
    /// 默认按语义底色选择前景，调用方仍可显式覆盖。
    var symbolColor: Color = .white
    var compact = false

    init(
        _ symbol: String,
        tint: Color = Theme.accent,
        symbolColor: Color? = nil,
        compact: Bool = false
    ) {
        self.symbol = symbol
        self.tint = tint
        self.symbolColor = symbolColor ?? ((tint == Theme.accent || tint == Theme.warning) ? Theme.onAccent : .white)
        self.compact = compact
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: compact ? 15 : 18, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(symbolColor)
            .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
            .background(
                tint,
                in: RoundedRectangle(
                    cornerRadius: compact ? Theme.Radius.compact : Theme.Radius.inner,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }
}

/// 记录类型的图标容器（今日 / 记录 / 详情共用，保证同一类型处处同形同色）
struct RecordIcon: View {

    let kind: RecordKind
    var compact = false

    var body: some View {
        Image(systemName: kind.filledSymbol)
            .font(.system(size: compact ? 17 : 20, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(kind.color)
            .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
            .accessibilityHidden(true)
    }
}

// MARK: - 卡片

private struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Theme.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
    }
}

extension View {
    /// 统一卡片容器：圆角 20 + 内边距 16，**无描边、无阴影** —— 靠卡面与页面底色差分层。
    ///
    /// 一度加过 1pt hairline，那是从 Apple 官网（**网页**）的 utility card 规则搬来的；
    /// iOS 的分组列表没有边框。见 `docs/04-ui-polish/design-system.md` §7。
    func card(padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// 分组标题。**放在卡片外面** —— 放进卡片当第一行是网页卡片的做法（FR13.5）。
struct SectionHeader: View {

    let text: String
    var trailing: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(text)
                .font(Theme.Font.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .monospacedDigit()
            }
        }
        .padding(.bottom, Theme.Spacing.xs)
    }
}

/// 列表行分隔线：0.5pt，**左缩进 48pt** 与主行文字对齐，不通栏（FR13.6）。
struct RowDivider: View {

    var inset: CGFloat = 48

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// 徽标外观。
///
/// 语义色只有两种正确搭配 —— **实色底 + 白字**，或**中性底 + 次级色字**。
/// 亮色（黄）是唯一例外：白字在黄底上读不出来，得配深字，所以单列一档。
/// 做成枚举而不是 `Color?` 参数，是为了让「黄底配了白字」这种错**写不出来**。
enum BadgeTone {
    /// 中性：chip 底 + 次级色字。**默认** —— 徽标是标注，不是按钮
    case neutral
    /// 实色底 + 白字
    case solid(Color)
    /// 亮色底 + 深字（黄色专用）
    case bright(Color)
}

/// 小徽标
struct Badge: View {

    let text: String
    var tone: BadgeTone

    init(_ text: String, tone: BadgeTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(Theme.Font.badge)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 3)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: Theme.Radius.compact, style: .continuous)
            )
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch tone {
        case .neutral: return Theme.chip
        case .solid(let color), .bright(let color): return color
        }
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Theme.secondaryLabel
        case .solid: return .white
        case .bright: return .black
        }
    }
}

/// 来源是辅助文字，列表和详情共用同一字号与前景。
struct RecordSourceLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Theme.secondaryLabel)
    }
}

/// 空态：符号 40pt → 标题 17/600 → 说明 13/次级（居中）→ 可选一个主按钮
///
/// 参数顺序按「符号 → 色调 → 文案」排，与 `SymbolChip` 一致；
/// 成员初始化器要求实参按声明顺序出现，所以 `tint` 必须在 `title` 前面。
struct EmptyStateView: View {

    let symbol: String
    var tint: Color = Theme.tertiaryLabel
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.secondaryLabel)
            if let message {
                Text(message)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

// MARK: - 按钮样式

/// 橙底深字的主要动作，禁用时采用中性填充。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.headline)
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.secondaryLabel)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.vertical, 13)
            .padding(.horizontal, Theme.Spacing.l)
            .background(isEnabled ? Theme.accent : Theme.chip,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.inner))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 次级操作采用轻量文字，保留44pt触控高度。
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? tint : Theme.secondaryLabel)
            .frame(minHeight: 44)
            .padding(.horizontal, Theme.Spacing.m)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 文字级动作：无底，强调色字。
/// 刻意不叫 `PlainButtonStyle` —— SwiftUI 自带同名类型，重名会把它遮住。
struct PlainActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var font: Font = Theme.Font.subheadline.weight(.semibold)
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(isEnabled ? tint : Theme.secondaryLabel)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - 格式化

enum Format {

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }

    /// 「今天 / 昨天 / 9月8日」
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return shortDayFormatter.string(from: date)
    }

    static func number(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f", value)
    }

    /// 按时间问候（今日页顶部）
    static func greeting(_ date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }

    /// 从起始日算到今天是第几周（1 起，夹在 `1...total` 之间）
    static func currentWeek(since start: Date, total: Int) -> Int {
        let calendar = Calendar.current
        let elapsed = calendar.dateComponents(
            [.weekOfYear],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: .now)
        ).weekOfYear ?? 0
        return min(max(elapsed + 1, 1), max(total, 1))
    }
}

/// App 内使用独立图片资源，避免依赖 AppIcon 的运行时名称。
struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityLabel("Moveliq")
    }
}
