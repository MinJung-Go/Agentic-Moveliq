import SwiftUI
import SwiftData

/// 洞察：本周报告 hero 卡 + 分析工具 + 历史报告
struct InsightsView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @Query(sort: [SortDescriptor(\AnalysisReport.periodEnd, order: .reverse)])
    private var reports: [AnalysisReport]

    /// 近 7 天训练，用来画 hero 卡的迷你柱状图与 KPI
    @Query private var recentWorkouts: [WorkoutSession]

    @State private var isGenerating = false
    @State private var errorText: String?

    private let settings = LLMSettings.shared

    init() {
        let since = Calendar.current.startOfDay(for: .now).addingTimeInterval(-6 * 86_400)
        _recentWorkouts = Query(
            filter: #Predicate<WorkoutSession> { $0.date >= since },
            sort: [SortDescriptor(\WorkoutSession.date)]
        )
    }

    /// 本周报告
    private var latest: AnalysisReport? { reports.first }

    private var history: [AnalysisReport] { Array(reports.dropFirst()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    Group {
                        if let latest {
                            heroCard(latest)
                        } else {
                            emptyState
                        }
                    }
                    .staggeredAppear(0)

                    toolsCard.staggeredAppear(1)

                    if !history.isEmpty {
                        historySection.staggeredAppear(2)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.l)
            }
            .background(Theme.canvas)
            .navigationTitle("洞察")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await generate() }
                    } label: {
                        if isGenerating {
                            PulsingDots(tint: Theme.accent)
                        } else {
                            Label("生成报告", systemImage: "sparkles")
                        }
                    }
                    .disabled(isGenerating)
                }
            }
        }
    }

    // MARK: - 报告 hero 卡

    /// KPI 行扫一眼就知道这周发生了什么；引文用衬线，和正文拉开距离
    private func heroCard(_ report: AnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Text("本期报告")
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
                Text(report.periodText)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }

            if !recentWorkouts.isEmpty {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    kpi(title: "手动训练", value: "\(recentWorkouts.count)", unit: "次")
                    kpi(title: "总容量", value: Format.number(weekVolume), unit: "kg")
                    kpi(title: "训练日", value: "\(trainedDayCount)", unit: "天")
                }
            }

            Text(report.headline)
                .font(Theme.Font.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !report.tags.isEmpty {
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(report.tags, id: \.self) { tag in
                        Badge(tag)
                    }
                }
            }

            if !recentWorkouts.isEmpty {
                VStack(spacing: Theme.Spacing.s) {
                    MiniBarChart(values: dailyVolume)
                    HStack {
                        Text(weekdayLabel(daysAgo: 6))
                        Spacer(minLength: 0)
                        Text(weekdayLabel(daysAgo: 0))
                    }
                    .font(Theme.Font.badge)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.tertiaryLabel)
                }
            }

            NavigationLink {
                ReportDetailView(report: report)
            } label: {
                HStack {
                    Text("查看完整报告")
                    Spacer(minLength: Theme.Spacing.s)
                    Image(systemName: "chevron.right")
                        .font(Theme.Font.caption)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    private func kpi(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Font.badge)
                .fontWeight(.regular)
                .foregroundStyle(Theme.secondaryLabel)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Font.metric)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(Theme.Font.badge)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 11)
        .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
    }

    // MARK: - 近 7 天

    /// 每天一格，没有训练的那天是 0（图上会留一根矮柱，看得出「这天没练」）
    private var dailyVolume: [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (0..<7).reversed().map { daysAgo in
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return 0 }
            return recentWorkouts
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.totalVolumeKg }
        }
    }

    private var weekVolume: Double {
        recentWorkouts.reduce(0) { $0 + $1.totalVolumeKg }
    }

    private var trainedDayCount: Int {
        Set(recentWorkouts.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    private func weekdayLabel(daysAgo: Int) -> String {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = daysAgo == 0 ? "今天" : "EEE"
        return formatter.string(from: date)
    }

    // MARK: - 空态

    /// 给的是「下一步做什么」，不是一句「暂无数据」（FR15.6）
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            EmptyStateView(
                symbol: "chart.bar.fill",
                tint: Theme.accent,
                title: "还没有分析报告",
                message: "同步健康数据或添加记录后，就能分析近 7 天的活动与恢复；不必记满 7 天。"
            )

            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    HStack(spacing: Theme.Spacing.s) {
                        PulsingDots(tint: nil)
                        Text("正在分析…")
                    }
                } else {
                    Text("生成分析报告")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isGenerating)

            if !settings.isConfigured {
                Text("请先登录并确认云端 AI 服务可用")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .card()
    }

    // MARK: - 分析工具

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(text: "分析工具")
            VStack(spacing: 0) {
                NavigationLink {
                    TrendsView()
                } label: {
                    toolRow(
                        symbol: "chart.line.uptrend.xyaxis",
                        tint: Theme.info,
                        title: "趋势图表",
                        subtitle: "体重 · 估算 1RM · 每周容量 · 睡眠"
                    )
                }
                .buttonStyle(.plain)

                RowDivider()

                NavigationLink {
                    NutritionAnalysisView()
                } label: {
                    toolRow(
                        symbol: "fork.knife",
                        tint: Theme.positive,
                        title: "饮食分析",
                        subtitle: "日均热量 · 宏营养素 · 蛋白质缺口"
                    )
                }
                .buttonStyle(.plain)
            }
            .card()
        }
    }

    // MARK: - 历史报告

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(text: "历史报告", trailing: "\(history.count) 份")
            VStack(spacing: 0) {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, report in
                    NavigationLink {
                        ReportDetailView(report: report)
                    } label: {
                        toolRow(
                            symbol: "note.text",
                            tint: Theme.accent,
                            title: report.periodText,
                            subtitle: report.headline
                        )
                    }
                    .buttonStyle(.plain)
                    // 这里是 ScrollView 不是 List，swipeActions 不生效，用长按菜单
                    .contextMenu {
                        Button("删除报告", role: .destructive) { delete(report) }
                    }

                    if index < history.count - 1 {
                        RowDivider()
                    }
                }
            }
            .card()
        }
    }

    private func toolRow(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            SymbolChip(symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryLabel)
        }
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
    }

    // MARK: - 动作

    private func generate() async {
        guard settings.isConfigured else {
            errorText = "请先登录并确认云端 AI 服务可用"
            return
        }

        isGenerating = true
        errorText = nil
        defer { isGenerating = false }

        do {
            let digest = try DataAggregator.digest(days: 7, context: context)
            guard digest.hasData else {
                errorText = "近 7 天没有可分析的训练、饮食或健康数据，请先同步或记录"
                return
            }

            let agent = AnalystAgent(client: try settings.makeRecordingClient())
            let draft = try await agent.generateReport(from: digest)

            let report = AnalysisReport(
                periodStart: digest.periodStart,
                periodEnd: digest.periodEnd,
                headline: draft.headline,
                body: draft.body,
                tags: draft.tags,
                citedDataText: draft.citedData
            )
            context.insert(report)
            try context.save()

            Haptics.success()
            appState.showToast("报告已生成")
        } catch {
            errorText = "生成失败：\(error.localizedDescription)"
        }
    }

    private func delete(_ report: AnalysisReport) {
        context.delete(report)
        try? context.save()
        Haptics.warning()
    }
}

/// 报告详情：连续阅读排版，旧正文只在展示时分段；AI 依据默认折叠。
struct ReportDetailView: View {

    let report: AnalysisReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack {
                        Text(report.periodText)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                        Spacer(minLength: 0)
                        Text("AI 生成")
                            .font(Theme.Font.badge)
                            .fontWeight(.regular)
                            .foregroundStyle(Theme.secondaryLabel)
                    }

                    Text(report.headline)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if !report.tags.isEmpty {
                        WrapLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(report.tags, id: \.self) { tag in
                                Text("• \(tag)")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.s)

                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(ReportTextLayout.paragraphs(in: report.body).enumerated()), id: \.offset) { _, paragraph in
                        MarkdownText(content: paragraph, blockSpacing: 18)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !report.citedDataText.isEmpty {
                    citedDataCard
                }

                Text("报告由 AI 基于本地聚合数据生成，仅供参考，不构成医疗建议。")
                    .font(Theme.Font.badge)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.l)
        }
        .background(Theme.conversationCanvas)
        .navigationTitle("分析报告")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 「AI 依据」默认折叠 —— 结论要摆出来，依据留给想核对的人
    private var citedDataCard: some View {
        DisclosureGroup {
            Text(report.citedDataText)
                .font(Theme.Font.caption.monospaced())
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Spacing.s)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                Text("AI 依据")
                    .font(Theme.Font.footnote.weight(.semibold))
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
}

#Preview {
    InsightsView()
        .environmentObject(AppState())
        .modelContainer(try! AppModelContainer.inMemory())
}
