import Foundation

/// User-owned configuration. No model tool can create or expand this authority.
struct CoachAutomationRules: Codable, Equatable {
    enum Action: String, Codable, CaseIterable { case move, shorten, reduceWeight, skip }
    var enabled = false
    var revision = UUID()
    var planIDs: Set<UUID> = []
    var actions: Set<Action> = []
    var validUntil: Date?
    var horizonDays: Int?
    var dailyChangeLimit: Int?
    var minimumLeadMinutes: Int?
    var maximumStartShiftMinutes: Int?
    var maximumDateShiftDays: Int?
    var minimumSessionMinutes: Int?
    var maximumShorteningPercent: Int?
    var maximumWeightReductionPercent: Int?
    var syncCalendar = false
    var syncAlarms = false

    var summary: String {
        guard enabled, isValid else { return "自动调整未启用或规则未完整保存，所有调整先确认。" }
        var permissions: [String] = []
        if actions.contains(.move) { permissions.append("时间相对原安排最多移动\(maximumStartShiftMinutes!)分钟/跨\(maximumDateShiftDays!)天") }
        if actions.contains(.shorten) { permissions.append("最多缩短\(maximumShorteningPercent!)%，保留至少\(minimumSessionMinutes!)分钟") }
        if actions.contains(.reduceWeight) { permissions.append("已有动作重量最多降低\(maximumWeightReductionPercent!)%") }
        if actions.contains(.skip) { permissions.append("可跳过本次未来训练") }
        return "用户已保存的自动调整范围：仅计划ID \(planIDs.map(\.uuidString).sorted().joined(separator: ","))；\(permissions.joined(separator: "；"))。未来\(horizonDays!)天，每天最多\(dailyChangeLimit!)项，开练前\(minimumLeadMinutes!)分钟停止；日历自动同步=\(syncCalendar)，闹钟自动同步=\(syncAlarms)。\(validUntil.map { "有效至\(CoachLifeTime.iso($0))。" } ?? "")模型只能提出方案，是否自动执行由本机重新校验；不可修改授权。"
    }

    var isValid: Bool {
        guard enabled else { return true }
        guard !planIDs.isEmpty, !actions.isEmpty,
              let horizonDays, (1...14).contains(horizonDays),
              let dailyChangeLimit, (1...20).contains(dailyChangeLimit),
              let minimumLeadMinutes, (0...1440).contains(minimumLeadMinutes) else { return false }
        if actions.contains(.move) {
            guard let maximumStartShiftMinutes, (1...10080).contains(maximumStartShiftMinutes),
                  let maximumDateShiftDays, (0...7).contains(maximumDateShiftDays) else { return false }
        }
        if actions.contains(.shorten) {
            guard let minimumSessionMinutes, (10...180).contains(minimumSessionMinutes),
                  let maximumShorteningPercent, (1...90).contains(maximumShorteningPercent) else { return false }
        }
        if actions.contains(.reduceWeight) {
            guard let maximumWeightReductionPercent, (1...50).contains(maximumWeightReductionPercent) else { return false }
        }
        return true
    }
}

/// Snapshots must be assembled from current local records, never trusted model identities.
struct CoachAutomationDay: Codable, Equatable {
    struct Exercise: Codable, Equatable {
        var id: UUID
        var name: String
        var setsText: String
        var weight: Double?
    }
    var id: UUID
    var planID: UUID
    var title: String
    var start: Date?
    var minutes: Int?
    var status: String = "pending"
    var exercises: [Exercise] = []
    var note: String? = nil
}

struct CoachAutomationChange: Equatable {
    /// Original state under this rule revision; repeated automatic changes retain this anchor.
    var anchor: CoachAutomationDay
    var current: CoachAutomationDay
    var proposed: CoachAutomationDay
}

/// Produced by trusted App adapters after fresh account, plan, calendar and schedule validation.
/// These flags are not model arguments and do not replace CoachScheduleGuard/system revalidation.
struct CoachAutomationEvidence {
    var verifiedAt: Date
    var accountMatches = false
    var versionsMatch = false
    var constraintsVerified = false
    var needsUserClarification = true
    var runningDayIDs: Set<UUID> = []
    var changesToday = 0
    var writesCalendar = false
    var writesAlarms = false
}

enum CoachAutomationDecision: Equatable {
    enum Reason: String, Codable {
        case disabled, incompleteRules, expired, unverified, clarification, systemScope
        case dailyLimit, identity, planScope, running, unknownTime, timing, unsupported, actionScope, magnitude
    }
    case automatic
    case needsConfirmation(Reason)
}

enum CoachAutomationPolicy {
    /// This is an eligibility decision only. It performs no database or system writes.
    static func evaluate(_ changes: [CoachAutomationChange], rules: CoachAutomationRules,
                         evidence: CoachAutomationEvidence, now: Date = .now,
                         calendar: Calendar = .current) -> CoachAutomationDecision {
        guard rules.enabled else { return .needsConfirmation(.disabled) }
        guard rules.isValid else { return .needsConfirmation(.incompleteRules) }
        if let until = rules.validUntil, until <= now { return .needsConfirmation(.expired) }
        guard evidence.accountMatches, evidence.versionsMatch, evidence.constraintsVerified,
              (0...60).contains(now.timeIntervalSince(evidence.verifiedAt)) else { return .needsConfirmation(.unverified) }
        guard !evidence.needsUserClarification else { return .needsConfirmation(.clarification) }
        guard (!evidence.writesCalendar || rules.syncCalendar), (!evidence.writesAlarms || rules.syncAlarms) else { return .needsConfirmation(.systemScope) }
        guard !changes.isEmpty, evidence.changesToday >= 0,
              changes.count <= rules.dailyChangeLimit! - evidence.changesToday else { return .needsConfirmation(.dailyLimit) }
        guard Set(changes.map { $0.current.id }).count == changes.count else { return .needsConfirmation(.identity) }
        guard let horizon = calendar.date(byAdding: .day, value: rules.horizonDays!, to: now) else { return .needsConfirmation(.timing) }
        for change in changes {
            let anchor = change.anchor, current = change.current, proposed = change.proposed
            guard anchor.id == current.id, current.id == proposed.id,
                  anchor.planID == current.planID, current.planID == proposed.planID else { return .needsConfirmation(.identity) }
            guard rules.planIDs.contains(current.planID) else { return .needsConfirmation(.planScope) }
            guard !evidence.runningDayIDs.contains(current.id) else { return .needsConfirmation(.running) }
            guard current.status == "pending", anchor.status == "pending",
                  current.title == proposed.title, anchor.title == current.title,
                  ["pending", "skipped"].contains(proposed.status) else { return .needsConfirmation(.unsupported) }
            guard let start = current.start, let originalStart = anchor.start, let target = proposed.start,
                  let minutes = current.minutes, let originalMinutes = anchor.minutes, let targetMinutes = proposed.minutes,
                  [minutes, originalMinutes, targetMinutes].allSatisfy({ (10...180).contains($0) }) else { return .needsConfirmation(.unknownTime) }
            let lead = Double(rules.minimumLeadMinutes! * 60)
            guard start > now, target > now, start.timeIntervalSince(now) >= lead,
                  target.timeIntervalSince(now) >= lead, start <= horizon, target <= horizon else { return .needsConfirmation(.timing) }
            if let until = rules.validUntil, start > until || target > until { return .needsConfirmation(.expired) }
            if proposed.status == "skipped" {
                guard rules.actions.contains(.skip) else { return .needsConfirmation(.actionScope) }
                guard target == start, targetMinutes == minutes, current.exercises == proposed.exercises else { return .needsConfirmation(.unsupported) }
                continue
            }
            if target != start || target != originalStart {
                guard rules.actions.contains(.move) else { return .needsConfirmation(.actionScope) }
                let dates = calendar.dateComponents([.day], from: calendar.startOfDay(for: originalStart), to: calendar.startOfDay(for: target)).day ?? Int.max
                guard abs(target.timeIntervalSince(originalStart)) <= Double(rules.maximumStartShiftMinutes! * 60),
                      abs(dates) <= rules.maximumDateShiftDays! else { return .needsConfirmation(.magnitude) }
            }
            if targetMinutes != minutes || targetMinutes != originalMinutes {
                guard rules.actions.contains(.shorten) else { return .needsConfirmation(.actionScope) }
                guard targetMinutes <= minutes, targetMinutes <= originalMinutes,
                      targetMinutes >= rules.minimumSessionMinutes!,
                      (originalMinutes - targetMinutes) * 100 <= originalMinutes * rules.maximumShorteningPercent! else { return .needsConfirmation(.magnitude) }
            }
            guard Set(current.exercises.map(\.id)).count == current.exercises.count,
                  Set(anchor.exercises.map(\.id)).count == anchor.exercises.count,
                  Set(proposed.exercises.map(\.id)).count == proposed.exercises.count,
                  current.exercises.map(\.id) == proposed.exercises.map(\.id),
                  anchor.exercises.map(\.id) == current.exercises.map(\.id) else { return .needsConfirmation(.unsupported) }
            for exercise in proposed.exercises {
                guard let old = current.exercises.first(where: { $0.id == exercise.id }),
                      let original = anchor.exercises.first(where: { $0.id == exercise.id }),
                      exercise.name == old.name, old.name == original.name,
                      exercise.setsText == old.setsText, old.setsText == original.setsText else { return .needsConfirmation(.unsupported) }
                guard [exercise.weight, old.weight, original.weight].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }) else { return .needsConfirmation(.unsupported) }
                if exercise.weight != old.weight || exercise.weight != original.weight {
                    guard rules.actions.contains(.reduceWeight) else { return .needsConfirmation(.actionScope) }
                    guard let weight = exercise.weight, let previous = old.weight, let baseline = original.weight,
                          weight > 0, baseline > 0, weight <= previous, weight <= baseline,
                          (baseline - weight) * 100 <= baseline * Double(rules.maximumWeightReductionPercent!) + 0.000001 else { return .needsConfirmation(.magnitude) }
                }
            }
            var previousTraining = current; previousTraining.note = proposed.note
            guard previousTraining != proposed else { return .needsConfirmation(.unsupported) }
        }
        return .automatic
    }
}
