import XCTest
import SwiftData
@testable import AgenticKeepKeep

@MainActor
final class RecordImporterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try AppModelContainer.inMemory()
        return ModelContext(container)
    }

    func testFailedPhotoIsPersistedWithTextAndExported() throws {
        let context = try makeContext()
        let photo = Data([1, 2, 3, 4])
        try RecordImporter.storeRawNote("营养标签", failureReason: "cancelled", to: context, photoData: photo)
        let note = try XCTUnwrap(context.fetch(FetchDescriptor<RawNote>()).first)
        XCTAssertEqual(note.text, "营养标签")
        XCTAssertEqual(note.photoData, photo)
        XCTAssertEqual(note.status, .pending)
        let payload = try DataExporter.makePayload(context: context)
        XCTAssertEqual(payload.bodyNotes.first?.photoData, photo)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }

    func testImportsWorkout() throws {
        let context = try makeContext()

        let record = ParsedRecord(
            kind: .workout,
            workout: ParsedWorkout(
                title: "腿日",
                exercises: [
                    ParsedExercise(name: "深蹲", weightKg: 100, reps: 5, sets: 5),
                    ParsedExercise(name: "腿举", weightKg: 200, reps: 10, sets: 3)
                ],
                rpe: 8,
                note: "有点累"
            )
        )

        let summary = try RecordImporter.apply([record], to: context)

        XCTAssertEqual(summary.workouts, 1)
        XCTAssertEqual(summary.total, 1)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].title, "腿日")
        XCTAssertEqual(sessions[0].source, .text)
        XCTAssertEqual(sessions[0].sets.count, 2)

        let squat = try XCTUnwrap(sessions[0].sets.first { $0.exerciseName == "深蹲" })
        XCTAssertEqual(squat.weightKg, 100)
        XCTAssertEqual(squat.reps, 5)
        XCTAssertEqual(squat.setCount, 5)
        XCTAssertEqual(squat.rpe, 8)
        XCTAssertEqual(squat.order, 0)
    }

    func testGeneratesTitleWhenMissing() throws {
        let context = try makeContext()

        let record = ParsedRecord(
            kind: .workout,
            workout: ParsedWorkout(exercises: [
                ParsedExercise(name: "卧推", weightKg: 80, reps: 8, sets: 5),
                ParsedExercise(name: "飞鸟", weightKg: 12, reps: 12, sets: 3),
                ParsedExercise(name: "臂屈伸", weightKg: 30, reps: 10, sets: 3)
            ])
        )

        _ = try RecordImporter.apply([record], to: context)

        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertTrue(session.title.contains("卧推"))
        XCTAssertTrue(session.title.contains("3 个动作"))
    }

    func testImportsMealWithFoodItems() throws {
        let context = try makeContext()

        let record = ParsedRecord(
            kind: .meal,
            meal: ParsedMeal(
                mealType: "lunch",
                items: [
                    ParsedFood(name: "牛肉面", amountText: "1 碗", calories: 650, proteinG: 30, carbsG: 85, fatG: 18)
                ],
                note: "出差在外吃的"
            )
        )

        let summary = try RecordImporter.apply([record], to: context)

        XCTAssertEqual(summary.meals, 1)
        let meal = try XCTUnwrap(try context.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(meal.mealType, .lunch)
        XCTAssertEqual(meal.items.count, 1)
        XCTAssertEqual(meal.totalCalories, 650)
        XCTAssertTrue(meal.containsEstimate, "AI 估算的食物应标记为估算值")
        XCTAssertEqual(meal.items.first?.amountText, "1 碗")
    }

    func testMealTypeFallsBackToInference() throws {
        let context = try makeContext()

        let record = ParsedRecord(
            kind: .meal,
            meal: ParsedMeal(mealType: "brunch", items: [ParsedFood(name: "三明治", calories: 400)])
        )

        _ = try RecordImporter.apply([record], to: context)

        let meal = try XCTUnwrap(try context.fetch(FetchDescriptor<MealEntry>()).first)
        // 无法识别的餐次名 → 按时间推断，不崩溃
        XCTAssertTrue(MealType.allCases.contains(meal.mealType))
    }

    func testImportsMetric() throws {
        let context = try makeContext()

        let record = ParsedRecord(kind: .metric, metric: ParsedMetric(kind: "weight", value: 74.5))
        let summary = try RecordImporter.apply([record], to: context)

        XCTAssertEqual(summary.metrics, 1)
        let metric = try XCTUnwrap(try context.fetch(FetchDescriptor<BodyMetric>()).first)
        XCTAssertEqual(metric.kind, .weight)
        XCTAssertEqual(metric.value, 74.5)
    }

    func testUnclassifiedNoteBecomesRawNote() throws {
        let context = try makeContext()

        let record = ParsedRecord(kind: .note, note: "昨晚只睡了5小时")
        let summary = try RecordImporter.apply([record], to: context)

        XCTAssertEqual(summary.notes, 1)
        let note = try XCTUnwrap(try context.fetch(FetchDescriptor<RawNote>()).first)
        XCTAssertEqual(note.text, "昨晚只睡了5小时")
        XCTAssertEqual(note.status, .pending)
    }

    func testEmptyNoteIsSkipped() throws {
        let context = try makeContext()

        let record = ParsedRecord(kind: .note, note: "")
        let summary = try RecordImporter.apply([record], to: context)

        XCTAssertEqual(summary.total, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RawNote>()), 0)
    }

    func testStoreRawNoteOnFailure() throws {
        let context = try makeContext()

        try RecordImporter.storeRawNote("深蹲100kg 5×5，有点累", failureReason: "解析超时", to: context)

        let note = try XCTUnwrap(try context.fetch(FetchDescriptor<RawNote>()).first)
        XCTAssertEqual(note.status, .pending)
        XCTAssertEqual(note.failureReason, "解析超时")
        XCTAssertEqual(note.text, "深蹲100kg 5×5，有点累")
    }

    func testImportsMixedRecordsAndRelatesThemToDate() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let records = [
            ParsedRecord(kind: .workout, workout: ParsedWorkout(exercises: [ParsedExercise(name: "深蹲", weightKg: 100, reps: 5, sets: 5)])),
            ParsedRecord(kind: .meal, meal: ParsedMeal(items: [ParsedFood(name: "牛肉面", calories: 650)])),
            ParsedRecord(kind: .metric, metric: ParsedMetric(kind: "weight", value: 74.5)),
            ParsedRecord(kind: .note, note: "今天状态一般")
        ]

        let summary = try RecordImporter.apply(records, to: context, date: date)

        XCTAssertEqual(summary.workouts, 1)
        XCTAssertEqual(summary.meals, 1)
        XCTAssertEqual(summary.metrics, 1)
        XCTAssertEqual(summary.notes, 1)
        XCTAssertEqual(summary.total, 4)

        let meal = try XCTUnwrap(try context.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(meal.date, date)
    }
}
