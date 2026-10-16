import XCTest
import SwiftUI
import UIKit
@testable import AgenticKeepKeep

/// 设计系统 v2 的纯逻辑部分。
///
/// 视图长什么样测不了，但**映射关系**能测 —— 「同一概念永远同一个符号」「语义色只标记这是什么」
/// 这两条纪律靠的就是映射表，表错了整个界面的语义就乱了。
final class ThemeTests: XCTestCase {

    // MARK: - 记录类型 → 符号

    func testEveryKindHasBothSymbolVariants() {
        for kind in RecordKind.allCases {
            XCTAssertFalse(kind.symbol.isEmpty, "\(kind) 缺轮廓符号")
            XCTAssertFalse(kind.filledSymbol.isEmpty, "\(kind) 缺实心符号")
        }
    }

    func testSymbolsAreUniquePerKind() {
        let symbols = RecordKind.allCases.map(\.filledSymbol)
        XCTAssertEqual(Set(symbols).count, symbols.count, "两个类型共用了同一个符号，界面上会分不清")
    }

    func testWorkoutAndBodyUseFilledVariants() {
        // 训练与身体指标在图表、图标块里都以实心出现；这两个必须有 .fill
        XCTAssertEqual(RecordKind.workout.filledSymbol, "dumbbell.fill")
        XCTAssertEqual(RecordKind.body.filledSymbol, "scalemass.fill")
    }

    func testDisplayNamesAreChinese() {
        let names = RecordKind.allCases.map(\.displayName)
        XCTAssertEqual(names, ["训练", "饮食", "身体指标", "随笔", "运动记录"])
    }

    // MARK: - 语义色

    func testSemanticColorsMatchDesignSystem() {
        // 设计系统 §2：训练=强调色、饮食=绿、身体=蓝、笔记与只读=灰
        // 用 UIColor 比而不是比 Color —— SwiftUI 的 Color 相等性依赖底层 provider，
        // 转成 UIColor 才是「这两个色在屏幕上是不是同一个」
        assertSameColor(RecordKind.workout.color, Theme.accent, "训练")
        assertSameColor(RecordKind.meal.color, Theme.positive, "饮食")
        assertSameColor(RecordKind.body.color, Theme.info, "身体指标")
        assertSameColor(RecordKind.note.color, Color(uiColor: .systemGray), "笔记")
        assertSameColor(RecordKind.health.color, Color(uiColor: .systemGray), "HealthKit 运动")
    }

    func testHealthAndNoteShareTheReadOnlyGray() {
        // HealthKit 同步来的记录只读 —— 与待归类笔记同为中性灰，不占用语义色
        assertSameColor(RecordKind.health.color, RecordKind.note.color, "只读灰")
    }

    private func assertSameColor(
        _ lhs: Color,
        _ rhs: Color,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(resolved(lhs), resolved(rhs), label, file: file, line: line)
    }

    /// 把颜色在浅色外观下解成具体 RGBA 再比。
    /// 直接比 `UIColor` 不行 —— 它们各自包着一个**动态** provider，比的是 provider 不是颜色。
    private func resolved(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }

    // MARK: - RecordItem → RecordKind 映射

    func testRecordItemMapsPayloadToKind() {
        let session = WorkoutSession(date: .now, title: "胸")
        XCTAssertEqual(RecordItem(payload: .workout(session)).kind, .workout)

        let meal = MealEntry(date: .now, note: "牛肉面")
        XCTAssertEqual(RecordItem(payload: .meal(meal)).kind, .meal)

        let metric = BodyMetric(date: .now, kind: .weight, value: 72)
        XCTAssertEqual(RecordItem(payload: .metric(metric)).kind, .body)

        let note = RawNote(text: "今天状态一般")
        XCTAssertEqual(RecordItem(payload: .rawNote(note)).kind, .note)

        XCTAssertEqual(RecordItem(payload: .healthWorkout(Self.healthWorkout())).kind, .health)
    }

    /// HealthKit 运动记录（只读）
    private static func healthWorkout(sourceName: String = "Watch") -> HealthWorkout {
        HealthWorkout(
            healthKitUUID: UUID().uuidString,
            date: .now,
            activityName: "跑步",
            durationMinutes: 30,
            sourceName: sourceName
        )
    }

    // MARK: - 徽标色调
    //
    // 徽标只有两种正确搭配：实色底 + 白字、中性底 + 次级色字。
    // 黄底是唯一例外（白字读不出来），所以单列 .bright 一档。

    func testPendingNoteBadgeUsesBrightToneNotSolid() {
        // 用 .bright 而不是 .solid —— 黄底配白字是设计系统里点名的错误
        let note = RawNote(text: "练了")
        note.status = .pending
        let badge = RecordItem(payload: .rawNote(note)).badge

        guard let tone = badge?.tone, case .bright(let color) = tone else {
            return XCTFail("待归类徽标必须是 .bright（黄底深字），实际是 \(String(describing: badge?.tone))")
        }
        XCTAssertEqual(resolved(color), resolved(Theme.warning))
    }

    func testClassifiedNoteHasNoBadge() {
        let note = RawNote(text: "练了")
        note.status = .categorized
        XCTAssertNil(RecordItem(payload: .rawNote(note)).badge)
    }

    /// 只读来源只是标注，不该跳出来抢注意力；且来源名不带 Emoji（Emoji 当图标是禁用项）
    func testHealthWorkoutBadgeIsNeutralAndPlain() {
        let badge = RecordItem(payload: .healthWorkout(Self.healthWorkout())).badge
        XCTAssertEqual(badge?.text, "Watch")
        guard let tone = badge?.tone, case .neutral = tone else {
            return XCTFail("HealthKit 来源徽标应为中性，实际是 \(String(describing: badge?.tone))")
        }
    }

    func testMealListNameDoesNotRewriteFullRecordOrFoodNames() {
        let meal = MealEntry(note: "原始备注")
        let name = "石榴籽（剥好的石榴粒，装于密封袋）"
        meal.items = [FoodItem(name: name, calories: 220)]
        let item = RecordItem(payload: .meal(meal))
        XCTAssertEqual(item.displayTitle, "石榴籽")
        XCTAssertEqual(item.title, name)
        XCTAssertEqual(meal.items.first?.name, name)
        XCTAssertEqual(meal.note, "原始备注")
    }

    func testEstimatedMealRemainsMarkedAsSourceInList() {
        let meal = MealEntry()
        meal.items = [FoodItem(name: "米饭", isEstimated: true)]
        let badge = RecordItem(payload: .meal(meal)).badge
        XCTAssertEqual(badge?.text, "AI 估算")
        guard case .neutral? = badge?.tone else { return XCTFail("估算来源应使用中性标注") }
    }

    func testCompactMealStillSearchesAndReadsAllFoodNames() {
        let meal = MealEntry(note: "下午加餐")
        let names = ["蜜橘 / 柑橘", "维他港式奶茶（原味，250ml）"]
        meal.items = names.map { FoodItem(name: $0, calories: 80, isEstimated: false) }
        let item = RecordItem(payload: .meal(meal))
        XCTAssertEqual(item.listHeading.name, names[0])
        XCTAssertEqual(item.listHeading.itemCount, 2)
        XCTAssertFalse(item.displayTitle.contains("维他"))
        XCTAssertTrue(item.matchesSearch("维他"))
        XCTAssertTrue(item.matchesSearch("250ml"))
        XCTAssertTrue(item.matchesSearch("下午加餐"))
        XCTAssertTrue(item.matchesSearch(" "))
        XCTAssertFalse(item.matchesSearch("深蹲"))
        XCTAssertTrue(item.accessibilityTitle.contains(names[1]))
        XCTAssertEqual(meal.items.map(\.name), names)
        XCTAssertEqual(meal.note, "下午加餐")
        XCTAssertNil(item.badge, "照片/展示精简不应改变估算来源")
    }

    func testRecordSearchKeepsNotesAndNonMealTitles() {
        let session = WorkoutSession(title: "Full Body A")
        XCTAssertTrue(RecordItem(payload: .workout(session)).matchesSearch("body"))
        let note = RawNote(text: "今天练了深蹲，稍后补组数")
        let item = RecordItem(payload: .rawNote(note))
        XCTAssertEqual(item.listHeading.name, note.text)
        XCTAssertEqual(item.listHeading.itemCount, 1)
        XCTAssertTrue(item.matchesSearch("稍后补组数"))
    }

    // MARK: - 间距与圆角阶梯

    func testSpacingScaleIsBaseEight() {
        // 结构值只用这几档，不允许视图里出现 10 / 14 / 18 这种中间值
        let values = [
            Theme.Spacing.xs, Theme.Spacing.s, Theme.Spacing.m,
            Theme.Spacing.l, Theme.Spacing.xl, Theme.Spacing.xxl,
        ]
        XCTAssertEqual(values, [4, 8, 12, 16, 24, 32])
    }

    func testRadiusLadderHasNoMiddleValues() {
        XCTAssertEqual(Theme.Radius.compact, 8)
        XCTAssertEqual(Theme.Radius.inner, 12)
        XCTAssertEqual(Theme.Radius.card, 20)
    }

    // MARK: - 问候语

    func testGreetingBoundaries() {
        // 5 点前算晚上，5–11 早上，12–17 下午，18 点起晚上
        XCTAssertEqual(Format.greeting(at: 4), "晚上好")
        XCTAssertEqual(Format.greeting(at: 5), "早上好")
        XCTAssertEqual(Format.greeting(at: 11), "早上好")
        XCTAssertEqual(Format.greeting(at: 12), "下午好")
        XCTAssertEqual(Format.greeting(at: 17), "下午好")
        XCTAssertEqual(Format.greeting(at: 18), "晚上好")
        XCTAssertEqual(Format.greeting(at: 23), "晚上好")
    }
}

private extension Format {
    /// 造一个当天指定小时的时间点
    static func greeting(at hour: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0, of: Date()
        ) ?? Date()
        return greeting(date)
    }
}
