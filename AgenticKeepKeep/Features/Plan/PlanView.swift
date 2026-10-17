import SwiftUI
import SwiftData

/// 课程表：计划头卡 + 训练日列表 + 常驻教练入口
struct PlanView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @Query(sort: [SortDescriptor(\Plan.createdAt, order: .reverse)])
    private var plans: [Plan]

    @AppStorage(MiloPersona.nameKey) private var miloName = "Milo"
    private var displayName: String { MiloPersona(name: miloName).name }

    @State private var isChatPresented = false
    @State private var pendingDeletion: PlanDeletionTarget?

    private var activePlan: Plan? {
        plans.first { $0.isActive }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = activePlan {
                    planContent(plan)
                } else {
                    emptyState
                }
            }
            .background(Theme.canvas)
            .navigationTitle("课程表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink("管理课程表") { PlanManagementView() }
                        if let plan = activePlan {
                            Button("删除当前课程表", role: .destructive) { pendingDeletion = PlanDeletionTarget(plan) }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("课程表操作")
                }
            }
            .confirmPlanDeletion($pendingDeletion)
            .sheet(isPresented: $isChatPresented) {
                CoachChatView()
            }
        }
    }

    /// 空态：把「找 AI 教练」做成主行动，而不是藏在小图标里
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                EmptyStateView(
                    symbol: "calendar",
                    tint: Theme.accent,
                    title: "没有进行中的课程表",
                    message: "告诉 \(displayName) 你的目标、每周能练几天、有什么器械，它会排一份周期化计划。"
                )

                Button("和 \(displayName) 聊聊") {
                    isChatPresented = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.Spacing.xl)
            }
            .padding(.top, Theme.Spacing.xl)
        }
    }

    private func planContent(_ plan: Plan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                planHeader(plan)
                TutorialProgressView(names: plan.days.flatMap { $0.exercises.map(\.name) })
                daysSection(plan)
                coachEntry
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
        }
    }

    // MARK: - 计划头卡

    private func planHeader(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(plan.title)
                .font(Theme.Font.title)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(plan.goal.displayName) · 第 \(Format.currentWeek(since: plan.startDate, total: plan.weeks)) / \(plan.weeks) 周")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)
            ProgressView(value: plan.days.isEmpty ? 0 : Double(plan.completedCount) / Double(plan.days.count))
                .tint(Theme.accent)
            Text("已完成 \(plan.completedCount) / \(plan.days.count) 次训练")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
        }
        .card()
    }

    // MARK: - 训练日

    /// 今天置顶，其余按时间排：未来由近及远，过去的由近及远（最近的在前）
    private func orderedDays(_ plan: Plan) -> [PlanDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let sorted = plan.sortedDays

        let todayDays = sorted.filter { calendar.isDate($0.date, inSameDayAs: today) }
        let rest = sorted.filter { !calendar.isDate($0.date, inSameDayAs: today) }
        let upcoming = rest.filter { $0.date > today }
        let past = rest.filter { $0.date < today }.reversed()

        return todayDays + upcoming + past
    }

    @ViewBuilder
    private func daysSection(_ plan: Plan) -> some View {
        let days = orderedDays(plan)

        if days.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(text: "训练日")
                Text("这份计划还没有排训练日，和 \(displayName) 补一份。")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(text: "训练日", trailing: "今天置顶")
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        NavigationLink {
                            PlanDayDetailView(day: day)
                        } label: {
                            PlanDayRow(day: day)
                        }
                        .buttonStyle(.plain)

                        if index < days.count - 1 {
                            RowDivider(inset: 0)
                        }
                    }
                }
                .card()
            }
        }
    }

    /// 常驻的教练入口 —— 不再需要去列表末尾找
    private var coachEntry: some View {
        Button {
            isChatPresented = true
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                SymbolChip("wand.and.stars", tint: Theme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("让 \(displayName) 调整计划")
                        .font(Theme.Font.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("按完成情况与恢复状态调整")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Theme.Spacing.xs)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 训练日行

/// 一天训练：左侧状态色条 + 勾选圆点 + 日期/主题/动作 + 状态徽标。
/// 已完成与已跳过的行**降字重**，让未完成的那几天自然跳出来。
struct PlanDayRow: View {

    let day: PlanDay

    private var isToday: Bool { Calendar.current.isDateInToday(day.date) }

    private var isDimmed: Bool { day.status != .pending }

    private var barColor: Color {
        switch day.status {
        case .done: return Theme.positive
        case .skipped: return Color(uiColor: .systemGray)
        case .pending: return isToday ? Theme.accent : Theme.chip
        }
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day.date) { return "今天 · \(Format.shortDay(day.date))" }
        if calendar.isDateInTomorrow(day.date) { return "明天 · \(Format.shortDay(day.date))" }
        return Format.shortDay(day.date)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Capsule()
                .fill(barColor)
                .frame(width: 3)
                .padding(.vertical, 13)

            checkCircle

            VStack(alignment: .leading, spacing: 2) {
                Text(dateLabel)
                    .font(Theme.Font.caption)
                    .foregroundStyle(isToday ? Theme.accent : Theme.secondaryLabel)

                Text(day.title)
                    .font(isDimmed ? Theme.Font.subheadline : Theme.Font.subheadline.weight(.semibold))
                    .foregroundStyle(isDimmed ? Theme.secondaryLabel : Color.primary)
                if let start = day.scheduledStart {
                    Text("\(CoachLifeTime.display(start))\(day.durationMinutes.map { " · \($0)分钟" } ?? "")").font(.footnote).foregroundStyle(Theme.secondaryLabel)
                }

                Text(day.exerciseSummary)
                    .font(Theme.Font.badge)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.xs)

            statusBadge
        }
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var checkCircle: some View {
        switch day.status {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 23, height: 23)
                .background(Theme.positive, in: Circle())

        case .skipped:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(uiColor: .systemGray))
                .frame(width: 23, height: 23)
                .overlay(Circle().strokeBorder(Color(uiColor: .systemGray), lineWidth: 1.8))

        case .pending:
            Circle()
                .strokeBorder(Theme.tertiaryLabel, lineWidth: 1.8)
                .frame(width: 23, height: 23)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch day.status {
        case .done: Badge("已完成", tone: .solid(Theme.positive))
        case .skipped: Badge("已跳过")
        case .pending: Badge("待做", tone: isToday ? .bright(Theme.accent) : .neutral)
        }
    }
}

// MARK: - 单个训练日

/// 训练日详情：状态分段控件 + 动作清单（可拖拽排序）
struct PlanDayDetailView: View {

    @Bindable var day: PlanDay
    @Environment(\.modelContext) private var context
    @State private var deletionID: UUID?
    @State private var deletionName = ""
    @State private var isDeleteConfirmationPresented = false
    @State private var deletionError: String?
    @State private var syncMessage: String?
    @State private var isSyncing = false

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $day.status) {
                    Text("待做").tag(PlanDayStatus.pending)
                    Text("已完成").tag(PlanDayStatus.done)
                    Text("已跳过").tag(PlanDayStatus.skipped)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                TextField("主题", text: $day.title)
                DatePicker("日期", selection: Binding(get: { day.date }, set: { date in
                    if let start = day.scheduledStart {
                        let minute = Calendar.current.component(.hour, from: start) * 60 + Calendar.current.component(.minute, from: start)
                        guard let adjusted = CoachLifeTime.at(minute: minute, on: date) else { syncMessage = "该日期不存在这个当地时间，请重新安排。"; return }
                        day.scheduledStart = adjusted
                    }
                    day.date = date
                }), displayedComponents: .date)
                if let start = day.scheduledStart {
                    Text("具体开始：\(CoachLifeTime.display(start))").font(.footnote)
                }
                TextField("备注（调整说明）", text: $day.note, axis: .vertical)
                    .lineLimit(1...3)
                if day.scheduledStart != nil {
                    Button(isSyncing ? "正在同步…" : "保存并同步关联日历与提醒") { syncSchedule() }.disabled(isSyncing)
                    if let syncMessage { Text(syncMessage).font(.footnote).foregroundStyle(Theme.secondaryLabel) }
                }
            } header: {
                Text("训练日")
            }

            Section {
                ForEach(day.sortedExercises, id: \.uuid) { exercise in
                    PlanExerciseRow(exercise: exercise)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // 这里只请求确认，不用 destructive 角色提前触发行移除动画。
                            Button {
                                deletionID = exercise.uuid
                                deletionName = exercise.name
                                isDeleteConfirmationPresented = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(Theme.danger)
                        }
                }
                .onMove(perform: move)

                Button {
                    addExercise()
                } label: {
                    Label("添加动作", systemImage: "plus.circle")
                }
            } header: {
                Text("动作")
            } footer: {
                Text("点动作查看训练参数；点「编辑」拖动排序，左滑可删除。")
            }
        }
        .confirmationDialog("删除动作？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除动作", role: .destructive) {
                guard let id = deletionID else { return }
                do {
                    try PlanExerciseStore.delete(id: id, day: day, context: context)
                } catch { deletionError = error.localizedDescription }
                deletionID = nil
            }
            Button("取消", role: .cancel) { deletionID = nil }
        } message: {
            Text("将从当天课程表移除「\(deletionName)」，已记录的训练不受影响。")
        }
        .alert("删除失败", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("好", role: .cancel) { deletionError = nil }
        } message: { Text(deletionError ?? "请稍后重试。") }
        .navigationTitle(Format.relativeDay(day.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .onChange(of: day.status) { _, _ in _ = prepareSync() }
        .onChange(of: day.date) { _, _ in _ = prepareSync() }
        .safeAreaInset(edge: .bottom) {
            // 已完成的日子也能从这里重开（补练）
            NavigationLink {
                WorkoutSessionView(planDay: day)
            } label: {
                Text(day.status == .done ? "再练一次" : "开始训练")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(day.exercises.isEmpty)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xs)
            .background(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    Theme.canvas
                }
            }
        }
    }

    private func prepareSync() -> Bool {
        guard let id = day.plan?.uuid else { return false }
        do {
            try TrainingScheduleSync.enqueue(planID: id, context: context)
            syncMessage = "课程表已保存。若修改了未来安排，请确认同步；系统中的旧日程与提醒尚未改动。"
            NotificationCenter.default.post(name: .coachLifeChanged, object: nil)
            return true
        } catch { syncMessage = "同步尚未准备好：\(error.localizedDescription)"; return false }
    }
    private func syncSchedule() {
        guard !isSyncing, prepareSync() else { return }; isSyncing = true
        Task { syncMessage = await TrainingScheduleSync.retry(context: context); isSyncing = false }
    }

    /// 拖拽排序：`onMove` 只给出新的顺序，`order` 字段要自己写回去
    private func move(from source: IndexSet, to destination: Int) {
        var ordered = day.sortedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in ordered.enumerated() {
            exercise.order = index
        }
        try? context.save()
        Haptics.tap()
    }

    private func addExercise() {
        let order = (day.exercises.map(\.order).max() ?? -1) + 1
        let exercise = PlanExercise(name: "新动作", setsText: "3×10", order: order)
        exercise.day = day
        context.insert(exercise)
        try? context.save()
    }
}

struct PlanExerciseRow: View {
    let exercise: PlanExercise

    var body: some View {
        NavigationLink {
            PlanExerciseDetailView(exercise: exercise)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(exercise.name.isEmpty ? "未命名动作" : exercise.name)
                    .font(Theme.Font.subheadline.weight(.semibold))
                HStack(spacing: Theme.Spacing.m) {
                    Text(exercise.setsText.isEmpty ? "组次未设置" : exercise.setsText)
                    if let weight = exercise.targetWeightKg {
                        Text("\(Format.number(weight)) kg")
                    }
                }
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .accessibilityIdentifier("plan-exercise-\(exercise.uuid.uuidString)")
    }
}

#Preview {
    PlanView()
        .environmentObject(AppState())
        .modelContainer(try! AppModelContainer.inMemory())
}
