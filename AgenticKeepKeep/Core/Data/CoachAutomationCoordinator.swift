import Combine
import CryptoKit
import Foundation
import SwiftData

/// Account-scoped foreground orchestration. Models propose; local policy owns execution.
@MainActor
final class CoachAutomationCoordinator: ObservableObject {
    static let shared = CoachAutomationCoordinator()
    @Published private(set) var checking = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var conversations = 0
    private var foreground = true
    private var applying = Set<UUID>()

    func invalidate() { generation = UUID(); task?.cancel(); task = nil; checking = false }
    func setForeground(_ value: Bool, context: ModelContext) {
        foreground = value
        if value { schedule(context: context) } else { invalidate() }
    }
    func beginConversation() { conversations += 1; invalidate() }
    func endConversation(context: ModelContext) { conversations = max(0, conversations - 1); schedule(context: context) }
    func schedule(context: ModelContext) {
        guard foreground, conversations == 0, !checking else { return }
        invalidate(); let marker = generation
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled, self.generation == marker else { return }
            self.checking = true
            defer { if self.generation == marker { self.checking = false } }
            do { try await self.checkForChanges(context: context, marker: marker) }
            catch {
                guard !Task.isCancelled, self.generation == marker, AppModelContainer.active === context.container else { return }
                if let workspace = try? CoachLifeStore.workspace(context) {
                    workspace.automationError = "本次自动检查未完成：\(error.localizedDescription)"; try? context.save()
                }
            }
        }
    }
    private func checkForChanges(context: ModelContext, marker: UUID) async throws {
        let token = ServiceCredentials.session?.token
        try CoachLifeStore.checkAccount(context: context, token: token)
        let rules = try CoachLifeStore.automationRules(context)
        guard rules.enabled, rules.isValid, rules.validUntil == nil || rules.validUntil! > .now,
              try CoachLifeStore.profile(context).confirmed, LLMSettings.shared.isConfigured else { return }
        let signals = try evaluationSignals(context: context)
        let signature = try triggerSignature(signals: signals, context: context)
        let workspace = try CoachLifeStore.workspace(context)
        guard workspace.lastAutomationSignature != signature,
              workspace.lastAutomationAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        let lifeRevision = try CoachLifeContextBuilder.revision(context: context)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        if messages.contains(where: { ($0.hasPendingAdjustment || $0.hasPendingPlan) && $0.pendingLifeRevision == lifeRevision }) {
            workspace.lastAutomationSignature = signature; try context.save(); return
        }
        workspace.lastAutomationAttempt = .now; workspace.automationError = ""; try context.save()
        var coachContext = CoachContext()
        coachContext.lifeContext = try CoachLifeContextBuilder.summary(context: context, days: rules.horizonDays!)
        coachContext.planState = try CoachPlanContext.build(context: context, query: "查询进行中的课程表，调整未来安排", limit: 9000)
        let request = "这是用户已开启的前台自动检查。依据最新数据处理这些变化：\n"
            + signals.map { "\($0.title)：\($0.detail)" }.joined(separator: "\n")
            + "\n只为授权计划提出必要的未来调整（propose_plan_adjustment），不创建课程表、不调用独立系统写入。只使用真实ID/版本与具体日期时间。不要堆叠补课。需要澄清就先询问，不臆测身体状态。执行权限由本机判定，越界整批待确认。"
        let client = try LLMSettings.shared.makeRecordingClient()
        let reply = try await CoachAgent(client: client, policy: LLMSettings.shared.coachPolicy).reply(history: [], userMessage: request, context: coachContext)
        try Task.checkCancellation(); try CoachLifeStore.checkAccount(context: context, token: token)
        guard generation == marker, try CoachLifeStore.automationRules(context).revision == rules.revision,
              try CoachLifeContextBuilder.revision(context: context) == lifeRevision else { throw CoachPluginError.stale }
        let message = ChatMessage(role: .assistant, content: reply.text ?? "已检查最新日常安排。",
            pendingAdjustmentJSON: reply.adjustmentArgumentsJSON)
        message.conversationID = try PersonalKnowledgeStore.prepareConversation(context)
        message.pendingLifeRevision = lifeRevision
        if reply.adjustmentArgumentsJSON != nil {
            for old in try context.fetch(FetchDescriptor<ChatMessage>()) where old.hasPendingAdjustment && old.conversationID == message.conversationID { old.adjustmentDecisionRaw = "superseded" }
        }
        context.insert(message); workspace.lastAutomationSignature = signature; try context.save()
        _ = try await applyIfAuthorized(message: message, context: context, token: token)
    }
    private func triggerSignature(signals: [CoachLifeContextBuilder.Signal], context: ModelContext) throws -> String {
        let source = try CoachLifeContextBuilder.revision(context: context, includePlans: false, includeCalendarRevision: false)
            + signals.map { "\($0.id)|\($0.detail)" }.sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func evaluationSignals(context: ModelContext) throws -> [CoachLifeContextBuilder.Signal] {
        let signals = try CoachLifeContextBuilder.signals(context: context).filter {
            $0.id.hasPrefix("conflict-") || $0.id.hasPrefix("temporary-") || $0.id.hasPrefix("feedback-") || $0.id.hasPrefix("linked-")
        }
        return signals.isEmpty ? [.init(id: "routine", title: "检查近期训练与日常", detail: "核对前台每日检查、最新训练、健康摘要与反馈；没有必要变化就保留原计划。", prompt: "")] : signals
    }

    /// Returns nil when the proposal must remain in the existing confirmation flow.
    @discardableResult
    func applyIfAuthorized(message: ChatMessage, context: ModelContext, token: String?) async throws -> CoachAutomationRecord? {
        try CoachLifeStore.checkAccount(context: context, token: token); try Task.checkCancellation()
        guard message.hasPendingAdjustment, !applying.contains(message.uuid) else { return nil }
        let rules = try CoachLifeStore.automationRules(context)
        guard rules.enabled, rules.isValid, let json = message.pendingAdjustmentJSON,
              let draft = CoachLifeStore.decode(PlanAdjustmentDraft.self, json),
              let rawID = draft.planID, let id = UUID(uuidString: rawID),
              let plan = try context.fetch(FetchDescriptor<Plan>()).first(where: { $0.uuid == id }), plan.isActive,
              draft.revision == PlanMutationStore.revision(plan),
              message.pendingLifeRevision == (try CoachLifeContextBuilder.revision(context: context)) else { return nil }
        let history = try context.fetch(FetchDescriptor<CoachAutomationRecord>(sortBy: [SortDescriptor(\.date)]))
        let changes: [CoachAutomationChange]
        do { changes = try Self.changes(draft, plan: plan, rules: rules, history: history) }
        catch { return nil }
        let config = try CoachLifeStore.plugins(context)
        let IDs = Set(changes.map { $0.current.id })
        let links = try context.fetch(FetchDescriptor<CoachTrainingLink>()).filter { IDs.contains($0.dayID) }
        var evidence = CoachAutomationEvidence(verifiedAt: .now)
        evidence.accountMatches = true; evidence.versionsMatch = true
        evidence.changesToday = history.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) {
            $0 + (CoachLifeStore.decode([CoachAutomationDay].self, $1.beforeJSON)?.count ?? 0)
        }
        evidence.runningDayIDs = Set(try context.fetch(FetchDescriptor<WorkoutSessionDraft>()).compactMap(\.planDayUUID))
        evidence.writesCalendar = config.syncTrainingCalendar || links.contains { !$0.eventID.isEmpty || !$0.eventLookupDates.isEmpty }
        evidence.writesAlarms = config.syncTrainingAlarms || links.contains { $0.alarmID != nil || !$0.retiredAlarmIDs.isEmpty }
        let checks = try context.fetch(FetchDescriptor<CoachCheckIn>()).filter { $0.kind == "temporary" && $0.expiresAt > .now }
        let profile = try CoachLifeStore.profile(context)
        let concerns = profile.constraints + "\n" + checks.map(\.note).joined(separator: "\n")
        evidence.needsUserClarification = !profile.constraints.isEmpty || checks.contains { $0.availableMinutes == nil }
            || concerns.range(of: "疼|痛|受伤|伤病|不适|生病|发热|发烧|头晕|胸闷|恶心|先问我|先确认|不要自动", options: .regularExpression) != nil
        guard (!evidence.writesCalendar || (config.enabled.contains(.calendar) && config.syncTrainingCalendar)),
              (!evidence.writesAlarms || (config.enabled.contains(.alarms) && config.syncTrainingAlarms)) else { return nil }
        do { try CoachScheduleGuard.validate(draft, context: context); evidence.constraintsVerified = true }
        catch { return nil }
        for change in changes where change.proposed.status != PlanDayStatus.skipped.rawValue {
            guard let start = change.proposed.start, let minutes = change.proposed.minutes else { return nil }
            do { try CoachScheduleGuard.validate(start: start, minutes: minutes, excluding: change.current.id,
                excludingDayIDs: IDs, context: context) }
            catch { return nil }
        }
        guard CoachAutomationPolicy.evaluate(changes, rules: rules, evidence: evidence) == .automatic else { return nil }
        applying.insert(message.uuid); defer { applying.remove(message.uuid) }
        let record = CoachAutomationRecord(ruleID: rules.revision, planID: plan.uuid, messageID: message.uuid)
        record.beforeJSON = try CoachLifeStore.encode(changes.map(\.current))
        record.afterJSON = try CoachLifeStore.encode(changes.map(\.proposed))
        record.anchorJSON = try CoachLifeStore.encode(changes.map(\.anchor))
        record.reason = String(draft.summary.prefix(1000))
        guard let receipt = try PlanMutationStore.apply(message: message, context: context, audit: record) else { return nil }
        record.executionLifeRevision = try CoachLifeContextBuilder.revision(context: context, includeCalendarRevision: false)
        record.receipt = "已按你的授权自动调整。\(receipt)"; message.content += "\n已按你保存的范围自动完成；结果可在今日安排查看。"
        try context.save()
        do {
            try TrainingScheduleSync.enqueue(planID: plan.uuid, context: context, dayIDs: IDs, automation: record)
            record.state = "syncQueued"; try context.save()
            record.receipt += "\n" + (await TrainingScheduleSync.retry(context: context))
            let pending = try context.fetch(FetchDescriptor<CoachTrainingLink>()).contains { IDs.contains($0.dayID) && $0.pending }
            record.state = pending ? "partial" : "complete"; try context.save()
        } catch {
            record.state = "partial"; record.receipt += "\n关联同步待处理：\(error.localizedDescription)"; try? context.save()
        }
        if let workspace = try? CoachLifeStore.workspace(context), let signals = try? evaluationSignals(context: context) {
            workspace.lastAutomationSignature = (try? triggerSignature(signals: signals, context: context)) ?? ""; try? context.save()
        }
        NotificationCenter.default.post(name: .coachLifeChanged, object: nil)
        return record
    }

    static func snapshot(_ day: PlanDay, planID: UUID) -> CoachAutomationDay {
        .init(id: day.uuid, planID: planID, title: day.title, start: day.scheduledStart, minutes: day.durationMinutes,
            status: day.statusRaw, exercises: day.sortedExercises.map { .init(id: $0.uuid, name: $0.name, setsText: $0.setsText, weight: $0.targetWeightKg) }, note: day.note)
    }
    static func changes(_ draft: PlanAdjustmentDraft, plan: Plan, rules: CoachAutomationRules,
                        history: [CoachAutomationRecord]) throws -> [CoachAutomationChange] {
        try draft.changes.map { change in
            guard ["reschedule", "update", "deload", "skip"].contains(change.action), change.title == nil, change.exercises == nil,
                  change.weightReductionPercent == nil || change.action == "deload",
                  let id = change.dayID.flatMap(UUID.init(uuidString:)), let day = plan.days.first(where: { $0.uuid == id }) else { throw CoachPluginError.invalid }
            let current = snapshot(day, planID: plan.uuid)
            let anchor = history.filter { $0.ruleID == rules.revision && $0.planID == plan.uuid }.compactMap {
                CoachLifeStore.decode([CoachAutomationDay].self, $0.anchorJSON)?.first { $0.id == id }
            }.first ?? current
            var proposed = current
            proposed.note = change.detail
            if change.action == "skip" {
                guard change.startTime == nil, change.date == nil, change.durationMinutes == nil else { throw CoachPluginError.invalid }
                proposed.status = PlanDayStatus.skipped.rawValue
            } else if change.action == "deload" {
                guard change.startTime == nil, change.date == nil, change.durationMinutes == nil else { throw CoachPluginError.invalid }
                let percent = change.weightReductionPercent ?? 15
                guard (1...50).contains(percent) else { throw CoachPluginError.invalid }
                let factor = 1 - Double(percent) / 100
                for index in proposed.exercises.indices {
                    if let weight = proposed.exercises[index].weight { proposed.exercises[index].weight = (weight * factor * 2).rounded() / 2 }
                }
            } else {
                guard let oldStart = current.start else { throw CoachPluginError.invalid }
                let date: Date
                if let text = change.date { guard let parsed = PlanMutationStore.localDate(text) else { throw CoachPluginError.invalid }; date = parsed }
                else { date = day.date }
                let minute: Int
                if let text = change.startTime { guard let parsed = CoachLifeTime.minute(text) else { throw CoachPluginError.invalid }; minute = parsed }
                else { minute = Calendar.current.component(.hour, from: oldStart) * 60 + Calendar.current.component(.minute, from: oldStart) }
                guard let target = CoachLifeTime.at(minute: minute, on: date) else { throw CoachPluginError.invalid }
                proposed.start = target; proposed.minutes = change.durationMinutes ?? current.minutes
            }
            return .init(anchor: anchor, current: current, proposed: proposed)
        }
    }

    @discardableResult
    static func restore(_ record: CoachAutomationRecord, context: ModelContext) throws -> String {
        let token = ServiceCredentials.session?.token
        try CoachLifeStore.checkAccount(context: context, token: token)
        guard record.restoredAt == nil,
              let plan = try context.fetch(FetchDescriptor<Plan>()).first(where: { $0.uuid == record.planID }), plan.isActive,
              PlanMutationStore.revision(plan) == record.afterRevision,
              let originals = CoachLifeStore.decode([CoachAutomationDay].self, record.beforeJSON) else { throw CoachPluginError.stale }
        let IDs = Set(originals.map(\.id))
        let runningIDs = Set(try context.fetch(FetchDescriptor<WorkoutSessionDraft>()).compactMap(\.planDayUUID))
        guard IDs.isDisjoint(with: runningIDs) else { throw CoachPluginError.unavailable("相关训练已经开始，请先结束或保留本次训练草稿，再重新安排。") }
        var slots: [CoachTimeSlot] = []
        for old in originals {
            guard let day = plan.days.first(where: { $0.uuid == old.id }), day.status != .done,
                  let start = old.start, let minutes = old.minutes else { throw CoachPluginError.stale }
            try CoachScheduleGuard.validate(start: start, minutes: minutes, excluding: day.uuid, excludingDayIDs: IDs, context: context)
            let slot = CoachTimeSlot(start: start, end: start.addingTimeInterval(Double(minutes * 60)))
            guard !slots.contains(where: { $0.start < slot.end && $0.end > slot.start }) else { throw CoachPluginError.invalid }
            slots.append(slot)
            guard day.exercises.count == old.exercises.count else { throw CoachPluginError.stale }
        }
        try context.save()
        do {
            for old in originals {
                let day = plan.days.first { $0.uuid == old.id }!
                day.date = Calendar.current.startOfDay(for: old.start!); day.scheduledStart = old.start; day.durationMinutes = old.minutes
                day.statusRaw = old.status
                if let note = old.note { day.note = note }
                for value in old.exercises {
                    guard let exercise = day.exercises.first(where: { $0.uuid == value.id }) else { throw CoachPluginError.stale }
                    exercise.targetWeightKg = value.weight
                }
            }
            record.restoredAt = .now; record.state = "restored"; try context.save()
        } catch { context.rollback(); throw error }
        NotificationCenter.default.post(name: .coachLifeChanged, object: nil)
        do {
            try TrainingScheduleSync.enqueue(planID: plan.uuid, context: context, dayIDs: IDs)
            return "原课程安排已恢复，关联日历和闹钟待同步。"
        } catch {
            record.receipt += "\n原课程已恢复；关联同步未排队：\(error.localizedDescription)"; try? context.save()
            return "原课程已恢复；关联同步未完成，请在课程表确认同步。"
        }
    }
}
