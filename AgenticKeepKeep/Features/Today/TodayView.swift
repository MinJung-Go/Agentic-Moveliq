import SwiftUI
import SwiftData

/// 今日：紧凑问候、课程行动、记录列表与共用消息输入栏。
struct TodayView: View {

    @ScaledMetric(relativeTo: .subheadline) private var greetingDetailSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var planTitleSize: CGFloat = 16
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var health = HealthKitService.shared

    @Query private var workouts: [WorkoutSession]
    @Query private var meals: [MealEntry]
    @Query private var metrics: [BodyMetric]
    @Query private var notes: [RawNote]
    @Query private var healthWorkouts: [HealthWorkout]
    @Query private var snapshots: [HealthSnapshot]
    @Query private var planDays: [PlanDay]
    @Query private var plans: [Plan]
    @Query private var trainingDrafts: [WorkoutSessionDraft]
    @AppStorage(MiloPersona.nameKey) private var miloName = "Milo"
    private var displayName: String { MiloPersona(name: miloName).name }
    private struct ChatEntry: Identifiable {
        let id = UUID()
        let text: String
    }
    @State private var chatEntry: ChatEntry?
    @State private var choosesIntent = false
    @State private var coachingSignalCount = 0

    /// 今日页输入条里敲的内容（还没提交，所以不进 ViewModel）
    @State private var showsHealthDetails = false
    @State private var draftText = ""
    @StateObject private var dictation = VoiceInput()
    @State private var draftPhoto: Data?
    @FocusState private var isInputFocused: Bool

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        _workouts = Query(
            filter: #Predicate<WorkoutSession> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\WorkoutSession.date, order: .reverse)]
        )
        _meals = Query(
            filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\MealEntry.date, order: .reverse)]
        )
        _metrics = Query(
            filter: #Predicate<BodyMetric> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\BodyMetric.date, order: .reverse)]
        )
        _notes = Query(
            filter: #Predicate<RawNote> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\RawNote.date, order: .reverse)]
        )
        _healthWorkouts = Query(
            filter: #Predicate<HealthWorkout> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\HealthWorkout.date, order: .reverse)]
        )
        _snapshots = Query(filter: #Predicate<HealthSnapshot> { $0.day == start })
        _planDays = Query(filter: #Predicate<PlanDay> { $0.date >= start && $0.date < end })
    }

    private var items: [RecordItem] {
        RecordItemBuilder.build(
            workouts: workouts,
            meals: meals,
            metrics: metrics,
            notes: notes,
            healthWorkouts: healthWorkouts
        )
    }

    private var todayPlanDay: PlanDay? {
        let days = planDays.filter { $0.plan?.isActive == true }.sorted { $0.order < $1.order }
        return days.first(where: { $0.status == .pending }) ?? days.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    greeting.staggeredAppear(0)
                    NavigationLink { CoachDashboardView() } label: {
                        Label(coachingSignalCount > 0 ? "今日安排 · \(coachingSignalCount)项需要再看看" : "今日安排 · 结合日常一起规划", systemImage: "calendar.badge.clock")
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain)
                    planSection.staggeredAppear(1)
                    recordsSection.staggeredAppear(2)
                    if !snapshots.isEmpty { healthSection }
                }
                .padding(.horizontal, Theme.Journal.inset)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.Journal.canvas)
            .foregroundStyle(Theme.Journal.label)
            .tint(Theme.Journal.action)
            .toolbarBackground(Theme.Journal.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.Journal.canvas, for: .tabBar)
            .navigationTitle("Moveliq")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandMark(size: 28) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dictation.finish(); chatEntry = ChatEntry(text: "") } label: {
                        Image(systemName: "bubble.left.and.bubble.right").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("与 \(displayName) 的对话")
                }
            }
            .sheet(item: $chatEntry) { entry in
                CoachChatView(initialMessage: entry.text, onMessageSubmitted: {
                    if draftText == entry.text { draftText = "" }
                })
            }
            .confirmationDialog("这句话要怎么处理？", isPresented: $choosesIntent, titleVisibility: .visible) {
                Button("整理为记录") { openLogSheet() }
                Button("继续对话") { openChat() }
                Button("返回修改", role: .cancel) { isInputFocused = true }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .refreshable { await syncHealth(force: true) }
            .task { refreshCoachSignals(); await syncHealth(force: false); refreshCoachSignals() }
            .onReceive(NotificationCenter.default.publisher(for: .coachLifeChanged)) { _ in refreshCoachSignals() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in refreshCoachSignals() }
            .onChange(of: health.lastSyncDate) { refreshCoachSignals() }
        }
    }

    // MARK: - 问候
    private func refreshCoachSignals() { coachingSignalCount = (try? CoachLifeContextBuilder.signals(context: context).count) ?? 0 }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(Format.day(.now))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Journal.metadata)
                    Text(Format.greeting())
                        .font(.title.weight(.semibold))
                    Text("今天也按自己的节奏来。")
                        .font(.system(size: greetingDetailSize))
                        .foregroundStyle(Theme.Journal.secondary)
                }
                Spacer(minLength: 0)
                MiloAvatar(size: 76)
            }
            .frame(minHeight: 98)
            ViewThatFits(in: .horizontal) {
                HStack { quickChat("我有点累"); quickChat(plans.contains { $0.isActive } ? "看看今天怎么练" : "一起制定训练计划") }
                VStack(alignment: .leading) { quickChat("我有点累"); quickChat(plans.contains { $0.isActive } ? "看看今天怎么练" : "一起制定训练计划") }
            }
        }
    }

    private func quickChat(_ text: String) -> some View {
        Button { dictation.finish(); chatEntry = ChatEntry(text: text) } label: {
            Text(text).font(Theme.Font.footnote)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(Theme.Journal.secondary)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                        .strokeBorder(Theme.Journal.line, lineWidth: 1)
                }
        }.buttonStyle(.plain)
    }

    // MARK: - 健康快照

    @ViewBuilder
    private var healthSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let snapshot = snapshots.first {
                DisclosureGroup(isExpanded: $showsHealthDetails) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s),
                                   count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                    spacing: Theme.Spacing.s
                ) {
                    StatTile(
                        symbol: "moon.fill",
                        tint: Theme.info,
                        title: "睡眠",
                        value: Format.number(snapshot.sleepHours, decimals: 1),
                        unit: "小时",
                        delta: snapshot.sleepHours > 0 && snapshot.sleepHours < 6.5 ? "偏低 · 目标 7.5h" : "目标 7.5h",
                        deltaTint: snapshot.sleepHours > 0 && snapshot.sleepHours < 6.5 ? Theme.warning : Theme.secondaryLabel
                    )
                    StatTile(
                        symbol: "waveform.path.ecg",
                        tint: Theme.accent,
                        title: "HRV",
                        value: Format.number(snapshot.hrvMs),
                        unit: "ms",
                        delta: snapshot.hrvMs > 0 && snapshot.hrvMs < 35 ? "偏低" : "正常",
                        deltaTint: snapshot.hrvMs > 0 && snapshot.hrvMs < 35 ? Theme.warning : Theme.secondaryLabel
                    )
                    StatTile(
                        symbol: "figure.walk",
                        tint: Theme.positive,
                        title: "活动量",
                        value: "\(snapshot.steps)",
                        unit: "步",
                        delta: "今天",
                        deltaTint: Theme.secondaryLabel
                    )
                    StatTile(
                        symbol: "heart.fill",
                        tint: Theme.danger,
                        title: "静息心率",
                        value: Format.number(snapshot.restingHeartRate),
                        unit: "bpm",
                        delta: "正常",
                        deltaTint: Theme.secondaryLabel
                    )
                }
                .padding(.top, Theme.Spacing.m)
                } label: {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label(snapshot.sleepHours > 0 ? "昨晚睡眠 \(Format.number(snapshot.sleepHours, decimals: 1)) 小时" : "今日身体状态", systemImage: "moon.fill")
                            .font(Theme.Font.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("查看睡眠、HRV、步数与静息心率")
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
                .padding(.vertical, Theme.Spacing.m)
                .overlay(alignment: .top) { Divider() }
            } else {
                SectionHeader(text: "身体状态")
                unauthorizedHealthCard
            }
        }
    }

    /// FR15.4：先说明读什么、存在哪，再给授权按钮 —— 不直接弹系统授权框
    private var unauthorizedHealthCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: healthIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(healthIconColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(healthTitle)
                        .font(Theme.Font.subheadline.weight(.semibold))
                    Text(healthDetail)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if health.authorizationState != .unavailable {
                Button {
                    Task {
                        await health.authorizeAndSync(into: context)
                    }
                } label: {
                    Text(health.authorizationActionTitle)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(health.isAuthorizing || health.isSyncing)
            }
        }
        .card()
    }

    private var healthIcon: String {
        switch health.authorizationState {
        case .unsupportedSigning, .failed: return "exclamationmark.triangle.fill"
        case .unavailable: return "iphone.slash"
        default: return "heart.text.square"
        }
    }

    private var healthIconColor: Color {
        switch health.authorizationState {
        case .unsupportedSigning, .failed: return Theme.warning
        case .unavailable: return Theme.secondaryLabel
        default: return Theme.accent
        }
    }

    private var healthTitle: String {
        switch health.authorizationState {
        case .unsupportedSigning: return "健康数据需要重新授权"
        case .unavailable: return "此设备不支持健康数据"
        case .failed: return "健康数据授权失败"
        default: return "还没接入健康数据"
        }
    }

    private var healthDetail: String {
        switch health.authorizationState {
        case .unsupportedSigning:
            return HealthKitService.signingHelp
        case .unavailable:
            return "该设备不提供 HealthKit。"
        case .failed:
            return health.lastError ?? "可以稍后重试。"
        default:
            return "只读读取睡眠、HRV、静息心率与步数，仅保存在本机。"
        }
    }

    // MARK: - 今日课程

    @ViewBuilder
    private var planSection: some View {
        if let day = todayPlanDay {
            let plan = day.plan
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                journalHeader("今日课程", trailing: weekLabel(plan))
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    // 状态色条：今天该练什么，一眼能看出状态
                    Capsule()
                        .fill(day.status == .done ? Theme.positive : Theme.accent)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack(alignment: .center, spacing: Theme.Spacing.m) {
                            SymbolChip("dumbbell.fill", tint: Theme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(day.title)
                                    .font(Theme.Font.headline)
                                if let start = day.scheduledStart {
                                    Text("\(CoachLifeTime.display(start))\(day.durationMinutes.map { " · \($0)分钟" } ?? "")")
                                        .font(.footnote).foregroundStyle(Theme.Journal.secondary)
                                }
                                Text(day.exerciseSummary)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }

                        if let plan, !plan.days.isEmpty {
                            ProgressBar(
                                value: Double(plan.completedCount) / Double(plan.days.count),
                                tint: day.status == .done ? Theme.positive : Theme.accent
                            )
                            HStack(spacing: Theme.Spacing.s) {
                                Text("已完成 \(plan.completedCount) / \(plan.days.count) 次")
                                Spacer(minLength: 0)
                                Text("\(day.exercises.count) 个动作")
                            }
                            .font(Theme.Font.badge)
                            .foregroundStyle(Theme.secondaryLabel)
                            .monospacedDigit()
                        }

                        // 两个 ButtonStyle 是不同类型，不能走三元表达式，只能分支
                        if day.status == .done {
                            Button("标记为未完成") { toggleDay(day) }
                                .buttonStyle(SecondaryButtonStyle())
                        } else {
                            // 主按钮从「标记完成」改成「开始训练」——
                            // 直接勾完成是旧做法，现在跟着计划练一遍就自动完成
                            NavigationLink {
                                WorkoutSessionView(planDay: day)
                            } label: {
                                Text(trainingDrafts.contains { $0.planDayUUID == day.uuid } ? "继续训练" : "开始训练")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding(Theme.Spacing.l)
                .background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: Theme.Journal.panelRadius))
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                journalHeader("今日课程")
                Button {
                    appState.selectedTab = .plan
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "calendar")
                            .font(.system(size: 19))
                            .foregroundStyle(Theme.Journal.action)
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plans.contains { $0.isActive } ? "今天没有安排训练" : "还没有训练计划")
                                .font(.system(size: planTitleSize, weight: .medium))
                                .foregroundStyle(Theme.Journal.label)
                            Text(plans.contains { $0.isActive } ? "查看课程表，按自己的节奏来" : "和 \(displayName) 一起安排第一份计划")
                                .font(Theme.Font.footnote)
                                .foregroundStyle(Theme.Journal.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(Theme.Font.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Journal.metadata)
                    }
                    .padding(Theme.Spacing.l)
                    .frame(minHeight: 88)
                    .background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: Theme.Journal.panelRadius))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleDay(_ day: PlanDay) {
        withAnimation(.snappy) {
            day.status = day.status == .done ? .pending : .done
        }
        try? context.save()
        Haptics.tap()
    }

    /// 「第 2 / 4 周」
    private func weekLabel(_ plan: Plan?) -> String? {
        guard let plan else { return nil }
        let week = Format.currentWeek(since: plan.startDate, total: plan.weeks)
        return "第 \(week) / \(plan.weeks) 周"
    }

    private func journalHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Journal.label)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(Theme.Journal.metadata)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - 今日已记录

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                journalHeader("今日记录", trailing: items.isEmpty ? nil : "\(items.count) 条")
                Button("查看全部") { appState.selectedTab = .records }
                    .font(Theme.Font.caption).frame(minHeight: 44)
            }

            if items.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("今天还没有记录").font(Theme.Font.subheadline)
                    Text("在下面说一句「深蹲100kg 5×5」试试")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .padding(.vertical, Theme.Spacing.m)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            RecordDetailView(item: item)
                        } label: {
                            RecordRow(item: item)
                        }
                        .buttonStyle(.plain)
                        if index < min(items.count, 3) - 1 { RecordRowDivider() }
                    }
                }
            }
        }
    }

    // MARK: - 输入条

    private var inputBar: some View {
        MessageComposer(
            text: $draftText,
            photo: $draftPhoto,
            dictation: dictation,
            focus: $isInputFocused,
            placeholder: "和 \(displayName) 说说…",
            identifier: "today",
            background: Theme.Journal.canvas,
            horizontalInset: Theme.Journal.inset,
            fieldBackground: Theme.Journal.fill,
            accessoryTint: Theme.Journal.action,
            onSend: routeInput
        )
    }

    private func routeInput() {
        isInputFocused = false
        switch HomeInputRouter.destination(text: draftText, hasPhoto: draftPhoto != nil) {
        case .empty: break
        case .chat: openChat()
        case .record: openLogSheet()
        case .choose: choosesIntent = true
        }
    }

    private func openChat() {
        guard draftPhoto == nil else { openLogSheet(); return }
        chatEntry = ChatEntry(text: draftText)
        isInputFocused = false
    }

    private func openLogSheet() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || draftPhoto != nil else { return }
        isInputFocused = false
        appState.pendingLogText = text
        appState.pendingLogPhoto = draftPhoto
        draftText = ""
        draftPhoto = nil
        Haptics.tap()
        appState.isQuickLogPresented = true
    }

    // MARK: - 健康同步

    private func syncHealth(force: Bool) async {
        guard health.isAvailable else { return }
        if !force, let last = health.lastSyncDate, Date().timeIntervalSince(last) < 3_600 {
            return
        }
        guard health.hasRequestedAuthorization || force else { return }
        await health.sync(days: 30, into: context)
    }
}

/// 健康指标小方块。
///
/// 图标是**彩色符号直接放在中性底上**（不是实色容器）—— 小尺寸下容器会喧宾夺主，
/// 而这里的重点是指标数字。见设计系统 §2「语义色的用法只有一种」。
struct StatTile: View {

    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let unit: String
    let delta: String
    var deltaTint: Color = Theme.secondaryLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Text(title)
                    .font(Theme.Font.badge)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Font.metric)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.top, 7)

            Text(delta)
                .font(Theme.Font.badge)
                .fontWeight(.regular)
                .foregroundStyle(deltaTint)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 11)
        .background(Theme.cardNested, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
    }
}

#Preview {
    TodayView()
        .environmentObject(AppState())
        .modelContainer(try! AppModelContainer.inMemory())
}
