import SwiftData
import SwiftUI

@MainActor
struct CoachDashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var health = HealthKitService.shared
    @Query private var plans: [Plan]
    @Query(sort: [SortDescriptor(\WorkoutSession.date, order: .reverse)]) private var sessions: [WorkoutSession]
    @Query(sort: [SortDescriptor(\CoachCheckIn.date, order: .reverse)]) private var checks: [CoachCheckIn]
    @Query(sort: [SortDescriptor(\CoachActionRecord.date, order: .reverse)]) private var actions: [CoachActionRecord]
    @Query private var links: [CoachTrainingLink]
    @Query(sort: [SortDescriptor(\CoachAutomationRecord.date, order: .reverse)]) private var automatic: [CoachAutomationRecord]
    @Query private var workspaces: [CoachWorkspace]
    @Query private var messages: [ChatMessage]
    @ObservedObject private var automation = CoachAutomationCoordinator.shared
    @State private var signals: [CoachLifeContextBuilder.Signal] = []
    @State private var checkedAt: Date?
    @State private var error: String?
    @State private var syncing = false
    @State private var chat: ChatEntry?
    private struct ChatEntry: Identifiable { let id = UUID(); var text: String }
    private var today: [PlanDay] {
        plans.filter(\.isActive).flatMap(\.days).filter { Calendar.current.isDateInToday($0.date) }.sorted { ($0.scheduledStart ?? $0.date) < ($1.scheduledStart ?? $1.date) }
    }
    private var weekSessions: [WorkoutSession] { sessions.filter { $0.date >= Date().addingTimeInterval(-7 * 86400) && $0.date <= .now } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Format.day(.now)).font(.caption).foregroundStyle(Theme.Journal.metadata)
                    Text("让训练融入你的日常").font(.title2.weight(.semibold))
                    Text("结合实际时间、最近训练与你的反馈，安排能执行的下一步。")
                        .foregroundStyle(Theme.Journal.secondary)
                }
                if !signals.isEmpty { signalsSection }
                if automation.checking { ProgressView("Milo 正在检查最新安排…").font(.footnote) }
                if let issue = workspaces.first?.automationError, !issue.isEmpty { Text(issue).font(.footnote).foregroundStyle(Theme.Journal.secondary) }
                if messages.contains(where: \.hasPendingAdjustment) {
                    Button("查看 Milo 的待确认调整") { chat = ChatEntry(text: "") }.buttonStyle(PrimaryButtonStyle())
                }
                ForEach(automatic.prefix(8), id: \.uuid) { CoachAutomationResultCard(record: $0) }
                todaySection
                NavigationLink { CoachTemporaryStateView() } label: { Label("今天有变化", systemImage: "text.bubble") }
                    .buttonStyle(SecondaryButtonStyle())
                ForEach(checks.filter { $0.kind == "temporary" && $0.expiresAt > .now }.prefix(5), id: \.uuid) { check in
                    NavigationLink { CoachTemporaryStateView(checkIn: check) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(check.note).lineLimit(3)
                            Text("至 \(CoachLifeTime.display(check.expiresAt)) · 点击修改或移除").font(.caption).foregroundStyle(Theme.Journal.secondary)
                        }.frame(minHeight: 44, alignment: .leading)
                    }
                }
                if actions.contains(where: { ["pending", "partial", "executing"].contains($0.state) }) {
                    Text("待确认的系统操作").font(.headline)
                    ForEach(actions.filter { ["pending", "partial", "executing"].contains($0.state) }.prefix(12), id: \.uuid) { CoachPluginActionCard(action: $0) }
                }
                if !links.isEmpty { synchronizationSection }
                if actions.contains(where: { $0.state == "succeeded" }) {
                    DisclosureGroup("最近系统操作结果") {
                        ForEach(actions.filter { $0.state == "succeeded" }.prefix(6), id: \.uuid) { CoachPluginActionCard(action: $0) }
                    }
                }
                feedbackSection
                reviewSection
                DisclosureGroup("安排依据与更新时间") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text((try? CoachLifeStore.profile(context).summary) ?? "生活偏好尚未读取。")
                        Text("健康快照：\(health.lastSyncDate.map(CoachLifeTime.display) ?? "尚未同步")；并非实时监测。")
                        Text("日历只覆盖已授权且选定的范围；空白不等于能训练。具体变化原因以当前提案为准。")
                        if let checkedAt { Text("本次检查：\(CoachLifeTime.display(checkedAt))") }
                    }.font(.footnote).foregroundStyle(Theme.Journal.secondary).padding(.top, 8)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                NavigationLink("修改目标与生活偏好") { CoachLifeProfileView() }
                NavigationLink("自动调整范围") { CoachAutomationSettingsView() }
                NavigationLink("管理插件") { CoachPluginsView() }
            }.padding(24)
        }
        .background(Theme.Journal.canvas).navigationTitle("今日安排").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $chat, onDismiss: evaluate) { CoachChatView(initialMessage: $0.text) }
        .task { evaluate() }
        .onReceive(NotificationCenter.default.publisher(for: .coachLifeChanged)) { _ in evaluate() }
        .onReceive(health.$lastSyncDate) { _ in evaluate() }
        .onChange(of: scenePhase) { _, value in if value == .active { evaluate() } }
        .onChange(of: checks.count) { evaluate() }
        .refreshable { evaluate() }
    }
    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("有些安排需要再看看").font(.headline)
            ForEach(signals) { signal in
                VStack(alignment: .leading, spacing: 8) {
                    Text(signal.title).font(.subheadline.weight(.semibold))
                    Text(signal.detail).font(.footnote).foregroundStyle(Theme.Journal.secondary)
                    Button("和 Milo 重新安排") { chat = ChatEntry(text: signal.prompt) }.buttonStyle(PrimaryButtonStyle())
                    Button("保留原计划") {
                        do { try CoachLifeContextBuilder.dismiss(signal, context: context); evaluate() } catch { self.error = error.localizedDescription }
                    }.buttonStyle(SecondaryButtonStyle())
                }.padding(16).background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今天的训练").font(.headline)
            if today.isEmpty {
                Text("今天没有已确认的训练安排。").foregroundStyle(Theme.Journal.secondary)
                Button("结合日常，安排这一周") { chat = ChatEntry(text: "先查询我的最新生活约束、训练和健康摘要及所选日历；必要信息不足先澄清，再安排未来一周的具体训练时间/时长与动作，解释依据并生成待确认课程表。") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            ForEach(today, id: \.uuid) { day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.title).font(.headline)
                    Text(day.scheduledStart.map(CoachLifeTime.display) ?? "尚未设置具体时间")
                    if let minutes = day.durationMinutes { Text("预计 \(minutes) 分钟").font(.subheadline) }
                    Text(day.exerciseSummary).font(.footnote).foregroundStyle(Theme.Journal.secondary)
                    if !day.note.isEmpty { Text(day.note).font(.footnote).foregroundStyle(Theme.Journal.secondary) }
                    if day.status == .pending { NavigationLink("开始训练") { WorkoutSessionView(planDay: day) }.buttonStyle(PrimaryButtonStyle()) }
                    else { Text(day.status == .done ? "已确认完成" : "已跳过").font(.caption) }
                    Button("这次安排需要调整") { chat = ChatEntry(text: "先查最新生活摘要和课程表，再和我核对训练日\(day.uuid)今天的可用时间与状态，只提出必要调整，等待我确认。") }
                        .buttonStyle(SecondaryButtonStyle())
                }.padding(16).background(Theme.Journal.panel, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    private var synchronizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关联日历与提醒").font(.headline)
            ForEach(links.filter(\.pending).prefix(8), id: \.uuid) { link in
                VStack(alignment: .leading, spacing: 4) {
                    if !link.calendarReceipt.isEmpty { Text(link.calendarReceipt) }
                    if !link.alarmReceipt.isEmpty { Text(link.alarmReceipt) }
                    Text(link.error.isEmpty ? "课程表已保存，关联操作待完成。" : link.error).foregroundStyle(Theme.Journal.secondary)
                }.font(.footnote)
            }
            if links.contains(where: \.pending) { Button(syncing ? "正在重试…" : "确认并重试未完成项") {
                syncing = true
                Task { error = await TrainingScheduleSync.retry(context: context); syncing = false }
            }.buttonStyle(SecondaryButtonStyle()).disabled(syncing) }
            let completed = links.filter { !$0.pending && (!$0.calendarReceipt.isEmpty || !$0.alarmReceipt.isEmpty) }
            if !completed.isEmpty {
                DisclosureGroup("已完成的关联同步") {
                    ForEach(completed.prefix(8), id: \.uuid) { link in
                        VStack(alignment: .leading, spacing: 4) {
                            let title = plans.flatMap(\.days).first { $0.uuid == link.dayID }?.title ?? "关联训练"
                            Text(title).font(.subheadline)
                            if !link.calendarReceipt.isEmpty { Text(link.calendarReceipt).font(.footnote) }
                            if !link.alarmReceipt.isEmpty { Text(link.alarmReceipt).font(.footnote) }
                        }.padding(.vertical, 6)
                    }
                }
            }
        }
    }
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("练完以后，告诉 Milo").font(.headline)
            let pending = weekSessions.filter { session in !checks.contains { $0.kind == "feedback" && $0.sessionID == session.uuid } }
            if pending.isEmpty { Text("训练后的难度与时间反馈，会帮助下一次安排。").font(.subheadline).foregroundStyle(Theme.Journal.secondary) }
            ForEach(pending.prefix(3), id: \.uuid) { session in
                NavigationLink { CoachFeedbackView(sessionID: session.uuid, dayID: session.planDayUUID, suggestedMinutes: session.durationMinutes ?? 0) } label: {
                    HStack { VStack(alignment: .leading) { Text(session.title); Text(CoachLifeTime.display(session.date)).font(.caption).foregroundStyle(Theme.Journal.secondary) }; Spacer(); Image(systemName: "chevron.right") }
                }.frame(minHeight: 44)
            }
            let reviewed = weekSessions.filter { session in checks.contains { $0.kind == "feedback" && $0.sessionID == session.uuid } }
            if !reviewed.isEmpty {
                DisclosureGroup("查看或修改已有反馈") {
                    ForEach(reviewed.prefix(7), id: \.uuid) { session in
                        NavigationLink(session.title) { CoachFeedbackView(sessionID: session.uuid, dayID: session.planDayUUID, suggestedMinutes: session.durationMinutes ?? 0) }.frame(minHeight: 44)
                    }
                }
            }
        }
    }
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("这一周，找到适合的节奏").font(.headline)
            Text("近7天已记录 \(weekSessions.count) 次训练。缺少记录不直接算作未完成，健康运动与课程记录不重复相加。")
                .font(.subheadline).foregroundStyle(Theme.Journal.secondary)
            Button("一起复盘，再安排下周") { chat = ChatEntry(text: "先查询生活约束、最近7天实际完成与反馈、最新健康摘要和未来日历。复盘哪些安排可执行，哪些受生活影响，区分漏记与未训练；询问需要更新的目标，再提出下周具体待确认计划，不机械堆叠补课。") }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
    private func evaluate() {
        do { signals = try CoachLifeContextBuilder.signals(context: context); checkedAt = .now }
        catch { self.error = "尚未完成检查：\(error.localizedDescription)" }
    }
}

@MainActor
struct CoachFeedbackView: View {
    var sessionID: UUID?
    var dayID: UUID?
    var suggestedMinutes = 0
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 0
    @State private var difficulty = "刚好"
    @State private var timing = "合适"
    @State private var note = ""
    @State private var existing: CoachCheckIn?
    @State private var error: String?
    @State private var token: String?
    var body: some View {
        Form {
            Section {
                Text("这次练得怎么样？").font(.title2.weight(.semibold))
                Text("可以稍后补充，实际训练记录已经单独保存。文字备注保留本机，难度与时间反馈以汇总用于后续规划。")
                    .font(.footnote).foregroundStyle(Theme.secondaryLabel)
            }
            Section {
                Stepper(minutes == 0 ? "实际时长：暂未提供" : "实际时长 \(minutes) 分钟", value: $minutes, in: 0...300)
                Picker("这次难度", selection: $difficulty) { ForEach(["偏轻", "刚好", "偏难"], id: \.self) { Text($0).tag($0) } }
                Picker("时间安排", selection: $timing) { ForEach(["合适", "有点赶", "需要换时间"], id: \.self) { Text($0).tag($0) } }
                TextField("补充备注（仅保存在本机）", text: $note, axis: .vertical).lineLimit(2...5)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
            Button("告诉 Milo") { save() }.buttonStyle(PrimaryButtonStyle())
            Button("稍后再说") { dismiss() }.buttonStyle(SecondaryButtonStyle())
        }
        .navigationTitle("训练后反馈").navigationBarTitleDisplayMode(.inline)
        .task {
            token = ServiceCredentials.session?.token
            if let sessionID {
                let values = try? context.fetch(FetchDescriptor<CoachCheckIn>())
                existing = values?.first { $0.kind == "feedback" && $0.sessionID == sessionID }
            }
            minutes = existing?.minutes ?? suggestedMinutes; difficulty = existing?.difficulty ?? "刚好"
            timing = existing?.timing ?? "合适"; note = existing?.note ?? ""
        }
    }
    private func save() {
        do {
            try CoachLifeStore.checkAccount(context: context, token: token)
            guard note.count <= 1000 else { throw CoachPluginError.invalid }
            try context.save()
            let value = existing ?? CoachCheckIn(); if existing == nil { context.insert(value) }
            value.sessionID = sessionID; value.dayID = dayID; value.minutes = minutes; value.difficulty = difficulty; value.timing = timing; value.note = note
            do { try context.save() } catch { context.rollback(); throw error }
            NotificationCenter.default.post(name: .coachLifeChanged, object: nil); dismiss()
        } catch { self.error = "反馈尚未保存：\(error.localizedDescription)" }
    }
}
