import Foundation
import SwiftData

/// 数据导出（隐私承诺的一部分：用户随时能把自己的数据带走）
@MainActor
enum DataExporter {

    struct Payload: Encodable {
        var app = "Moveliq"
        var exportedAt: Date
        var workouts: [WorkoutDTO]
        var meals: [MealDTO]
        var metrics: [MetricDTO]
        var bodyNotes: [NoteDTO]
        var healthSnapshots: [SnapshotDTO]
        var healthWorkouts: [HealthWorkoutDTO]
        var reports: [ReportDTO]
        var plans: [PlanDTO]
        var coachState: CoachStateDTO? = nil
    }

    struct WorkoutDTO: Encodable {
        var date: Date
        var title: String
        var note: String
        var source: String
        var exercises: [ExerciseDTO]
        var durationMinutes: Int? = nil
        var planDayUUID: UUID? = nil

        struct ExerciseDTO: Encodable {
            var name: String
            var weightKg: Double
            var reps: Int
            var sets: Int
            var rpe: Double?
        }
    }

    struct MealDTO: Encodable {
        var date: Date
        var mealType: String
        var source: String
        var items: [FoodDTO]

        struct FoodDTO: Encodable {
            var name: String
            var amountText: String
            var calories: Double
            var proteinG: Double
            var carbsG: Double
            var fatG: Double
            var isEstimated: Bool
        }
    }

    struct MetricDTO: Encodable {
        var date: Date
        var kind: String
        var value: Double
    }

    struct NoteDTO: Encodable {
        var photoData: Data? = nil
        var date: Date
        var text: String
        var status: String
    }

    struct SnapshotDTO: Encodable {
        var day: Date
        var sleepHours: Double
        var hrvMs: Double
        var restingHeartRate: Double
        var steps: Int
        var activeEnergyKcal: Double
    }

    struct HealthWorkoutDTO: Encodable {
        var date: Date
        var activityName: String
        var durationMinutes: Double
        var distanceKm: Double?
        var averageHeartRate: Double?
        var sourceName: String
    }

    struct ReportDTO: Encodable {
        var periodStart: Date
        var periodEnd: Date
        var headline: String
        var body: String
        var tags: [String]
    }

    struct PlanDTO: Encodable {
        var title: String
        var goal: String
        var weeks: Int
        var days: [PlanDayDTO]

        struct PlanDayDTO: Encodable {
            var date: Date
            var title: String
            var status: String
            var exercises: [PlanExerciseDTO]
            var scheduledStart: Date? = nil
            var durationMinutes: Int? = nil

            struct PlanExerciseDTO: Encodable {
                var name: String
                var setsText: String
                var targetWeightKg: Double?
            }
        }
    }

    struct CoachStateDTO: Encodable {
        var profileJSON: String
        var pluginsJSON: String
        var automationJSON: String
        var checkIns: [CheckInDTO]
        var operations: [OperationDTO]
        var links: [LinkDTO]
        struct CheckInDTO: Encodable {
            var id: UUID; var date: Date; var expiresAt: Date; var kind: String
            var sessionID: UUID?; var dayID: UUID?; var minutes: Int; var availableMinutes: Int?; var difficulty: String; var timing: String; var note: String
        }
        struct OperationDTO: Encodable {
            var id: UUID; var operationID: UUID; var date: Date; var kind: String; var payloadJSON: String; var state: String; var receipt: String
        }
        struct LinkDTO: Encodable {
            var planID: UUID; var dayID: UUID; var eventID: String; var alarmID: UUID?; var retiredAlarmIDs: [UUID]
            var desiredJSON: String; var calendarReceipt: String; var alarmReceipt: String; var error: String; var pending: Bool
        }
    }

    static func makePayload(context: ModelContext) throws -> Payload {
        let workouts = try context.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
        let meals = try context.fetch(
            FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
        let metrics = try context.fetch(
            FetchDescriptor<BodyMetric>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
        let notes = try context.fetch(
            FetchDescriptor<RawNote>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
        let snapshots = try context.fetch(
            FetchDescriptor<HealthSnapshot>(sortBy: [SortDescriptor(\.day, order: .reverse)])
        )
        let healthWorkouts = try context.fetch(
            FetchDescriptor<HealthWorkout>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
        let reports = try context.fetch(
            FetchDescriptor<AnalysisReport>(sortBy: [SortDescriptor(\.periodEnd, order: .reverse)])
        )
        let plans = try context.fetch(FetchDescriptor<Plan>())

        var payload = Payload(
            exportedAt: .now,
            workouts: workouts.map { session in
                WorkoutDTO(
                    date: session.date,
                    title: session.title,
                    note: session.note,
                    source: session.source.rawValue,
                    exercises: session.sets.sorted { $0.order < $1.order }.map {
                        WorkoutDTO.ExerciseDTO(
                            name: $0.exerciseName,
                            weightKg: $0.weightKg,
                            reps: $0.reps,
                            sets: $0.setCount,
                            rpe: $0.rpe
                        )
                    }, durationMinutes: session.durationMinutes, planDayUUID: session.planDayUUID
                )
            },
            meals: meals.map { meal in
                MealDTO(
                    date: meal.date,
                    mealType: meal.mealType.rawValue,
                    source: meal.source.rawValue,
                    items: meal.items.map {
                        MealDTO.FoodDTO(
                            name: $0.name,
                            amountText: $0.amountText,
                            calories: $0.calories,
                            proteinG: $0.proteinG,
                            carbsG: $0.carbsG,
                            fatG: $0.fatG,
                            isEstimated: $0.isEstimated
                        )
                    }
                )
            },
            metrics: metrics.map {
                MetricDTO(date: $0.date, kind: $0.kind.rawValue, value: $0.value)
            },
            bodyNotes: notes.map {
                NoteDTO(photoData: $0.photoData, date: $0.date, text: $0.text, status: $0.status.rawValue)
            },
            healthSnapshots: snapshots.map {
                SnapshotDTO(
                    day: $0.day,
                    sleepHours: $0.sleepHours,
                    hrvMs: $0.hrvMs,
                    restingHeartRate: $0.restingHeartRate,
                    steps: $0.steps,
                    activeEnergyKcal: $0.activeEnergyKcal
                )
            },
            healthWorkouts: healthWorkouts.map {
                HealthWorkoutDTO(
                    date: $0.date,
                    activityName: $0.activityName,
                    durationMinutes: $0.durationMinutes,
                    distanceKm: $0.distanceKm,
                    averageHeartRate: $0.averageHeartRate,
                    sourceName: $0.sourceName
                )
            },
            reports: reports.map {
                ReportDTO(
                    periodStart: $0.periodStart,
                    periodEnd: $0.periodEnd,
                    headline: $0.headline,
                    body: $0.body,
                    tags: $0.tags
                )
            },
            plans: plans.map { plan in
                PlanDTO(
                    title: plan.title,
                    goal: plan.goal.rawValue,
                    weeks: plan.weeks,
                    days: plan.sortedDays.map { day in
                        PlanDTO.PlanDayDTO(
                            date: day.date,
                            title: day.title,
                            status: day.status.rawValue,
                            exercises: day.sortedExercises.map {
                                PlanDTO.PlanDayDTO.PlanExerciseDTO(
                                    name: $0.name,
                                    setsText: $0.setsText,
                                    targetWeightKg: $0.targetWeightKg
                                )
                            }, scheduledStart: day.scheduledStart, durationMinutes: day.durationMinutes
                        )
                    }
                )
            }
        )
        let workspace = try context.fetch(FetchDescriptor<CoachWorkspace>()).first
        payload.coachState = CoachStateDTO(profileJSON: workspace?.profileJSON ?? "", pluginsJSON: workspace?.pluginsJSON ?? "", automationJSON: workspace?.automationJSON ?? "",
            checkIns: try context.fetch(FetchDescriptor<CoachCheckIn>()).map { .init(id: $0.uuid, date: $0.date, expiresAt: $0.expiresAt, kind: $0.kind, sessionID: $0.sessionID, dayID: $0.dayID, minutes: $0.minutes, availableMinutes: $0.availableMinutes, difficulty: $0.difficulty, timing: $0.timing, note: $0.note) },
            operations: try context.fetch(FetchDescriptor<CoachActionRecord>()).map { .init(id: $0.uuid, operationID: $0.operationID, date: $0.date, kind: $0.kind, payloadJSON: $0.payloadJSON, state: $0.state, receipt: $0.receipt) },
            links: try context.fetch(FetchDescriptor<CoachTrainingLink>()).map { .init(planID: $0.planID, dayID: $0.dayID, eventID: $0.eventID, alarmID: $0.alarmID, retiredAlarmIDs: $0.retiredAlarmIDs, desiredJSON: $0.desiredJSON, calendarReceipt: $0.calendarReceipt, alarmReceipt: $0.alarmReceipt, error: $0.error, pending: $0.pending) })
        return payload
    }

    /// 写出 JSON 文件，返回可分享的文件地址
    static func exportFile(context: ModelContext) throws -> URL {
        let payload = try makePayload(context: context)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let name = "keepkeep-export-\(formatter.string(from: .now)).json"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
