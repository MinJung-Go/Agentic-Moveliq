import Foundation
import SwiftData
import SwiftUI

/// 记录流里的统一条目：把不同类型的记录聚合成一种可展示的结构
struct RecordItem: Identifiable {

    enum Payload {
        case workout(WorkoutSession)
        case meal(MealEntry)
        case metric(BodyMetric)
        case rawNote(RawNote)
        case healthWorkout(HealthWorkout)
    }

    let payload: Payload

    var id: String { uuid.uuidString }

    var uuid: UUID {
        switch payload {
        case .workout(let model): return model.uuid
        case .meal(let model): return model.uuid
        case .metric(let model): return model.uuid
        case .rawNote(let model): return model.uuid
        case .healthWorkout(let model): return model.uuid
        }
    }

    var date: Date {
        switch payload {
        case .workout(let model): return model.date
        case .meal(let model): return model.date
        case .metric(let model): return model.date
        case .rawNote(let model): return model.date
        case .healthWorkout(let model): return model.date
        }
    }

    var kind: RecordKind {
        switch payload {
        case .workout: return .workout
        case .meal: return .meal
        case .metric: return .body
        case .rawNote: return .note
        case .healthWorkout: return .health
        }
    }

    var title: String {
        switch payload {
        case .workout(let model):
            return model.title.isEmpty ? "训练" : model.title
        case .meal(let model):
            return model.summary
        case .metric(let model):
            return "\(model.kind.displayName) \(Format.number(model.value, decimals: model.kind == .weight ? 1 : 0))\(model.kind.unit)"
        case .rawNote(let model):
            return model.text
        case .healthWorkout(let model):
            var text = model.activityName
            if let km = model.distanceKm, km > 0 {
                text += " \(Format.number(km, decimals: 1)) km"
            }
            return text
        }
    }

    /// 列表用短名称；详情与辅助朗读仍使用完整 title。
    var displayTitle: String {
        guard case .meal(let meal) = payload else { return title }
        return RecordDisplayName.meal(names: meal.items.map(\.name), fallback: title)
    }

    var subtitle: String? {
        switch payload {
        case .workout(let model):
            var parts: [String] = []
            let sets = model.sets.sorted { $0.order < $1.order }
            if let first = sets.first {
                parts.append(first.displayText)
                if sets.count > 1 { parts.append("等 \(sets.count) 个动作") }
            }
            if let rpe = sets.compactMap(\.rpe).first {
                parts.append("RPE \(Format.number(rpe))")
            }
            if !model.note.isEmpty { parts.append(model.note) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")

        case .meal(let model):
            var parts: [String] = []
            if model.totalCalories > 0 {
                parts.append("~\(Format.number(model.totalCalories)) kcal")
            }
            if model.totalProteinG > 0 {
                parts.append("蛋白质 ≈\(Format.number(model.totalProteinG))g")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")

        case .metric(let model):
            return model.note.isEmpty ? nil : model.note

        case .rawNote(let model):
            return model.status == .pending ? "未归类 · 点按修正或重新解析" : model.status.displayName

        case .healthWorkout(let model):
            var parts: [String] = []
            if let pace = model.paceText { parts.append("配速 \(pace)") }
            if let heartRate = model.averageHeartRate {
                parts.append("平均心率 \(Format.number(heartRate))")
            }
            if parts.isEmpty { parts.append(model.durationText) }
            return parts.joined(separator: " · ")
        }
    }

    /// 是否带照片（记录流里显示相机徽标）。
    /// 只读 MealEntry.hasPhoto 这个轻量标记，不触碰 externalStorage 的原图。
    var hasPhoto: Bool {
        if case .meal(let model) = payload {
            return model.hasPhoto
        }
        return false
    }

    /// 右上角来源徽标。色调语义见 `BadgeTone` —— 默认中性，只有需要它跳出来时才用实色
    var badge: (text: String, tone: BadgeTone)? {
        switch payload {
        case .workout:
            return nil
        case .meal(let model):
            return model.containsEstimate ? ("AI 估算", .neutral) : nil
        case .metric:
            return nil
        case .rawNote(let model):
            // 黄色是亮色，必须配深字 —— 用 .bright 而不是 .solid
            return model.status == .pending ? ("待归类", .bright(Theme.warning)) : nil
        case .healthWorkout(let model):
            return (model.sourceName, .neutral)
        }
    }

    /// HealthKit 同步的数据只读（源数据在 HealthKit）
    var isEditable: Bool {
        switch payload {
        case .healthWorkout: return false
        default: return true
        }
    }

    var isPendingNote: Bool {
        if case .rawNote(let model) = payload {
            return model.status == .pending
        }
        return false
    }
}

// MARK: - 组装

enum RecordItemBuilder {

    static func build(
        workouts: [WorkoutSession],
        meals: [MealEntry],
        metrics: [BodyMetric],
        notes: [RawNote],
        healthWorkouts: [HealthWorkout]
    ) -> [RecordItem] {
        var items: [RecordItem] = []
        items.append(contentsOf: workouts.map { RecordItem(payload: .workout($0)) })
        items.append(contentsOf: meals.map { RecordItem(payload: .meal($0)) })
        items.append(contentsOf: metrics.map { RecordItem(payload: .metric($0)) })
        items.append(contentsOf: notes.map { RecordItem(payload: .rawNote($0)) })
        items.append(contentsOf: healthWorkouts.map { RecordItem(payload: .healthWorkout($0)) })
        return items.sorted { $0.date > $1.date }
    }

    /// 按天分组（保持时间倒序）
    static func groupedByDay(_ items: [RecordItem]) -> [RecordGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { RecordGroup(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }
}

/// 按天分组的记录（用结构体而非元组：ForEach 的 id 需要 key path）
struct RecordGroup: Identifiable {
    let day: Date
    let items: [RecordItem]

    var id: Date { day }
}
