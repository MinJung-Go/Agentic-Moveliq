import XCTest
@testable import AgenticKeepKeep

final class ReadingPresentationTests: XCTestCase {
    func testLongReportSplitsOnlyAtSentenceEndsWithoutLosingCharacters() {
        let sentence = "本周活动能量日均仅94kcal，步数约3780步，建议逐步恢复日常活动并核对记录。"
        let body = String(repeating: sentence, count: 9)
        let paragraphs = ReportTextLayout.paragraphs(in: body)
        XCTAssertGreaterThan(paragraphs.count, 1)
        XCTAssertEqual(paragraphs.joined(), body)
        XCTAssertTrue(paragraphs.allSatisfy { $0.hasSuffix("。") })
    }

    func testNumbersAndUnitsAreNeverSplit() {
        let body = String(repeating: "本周体重74.5kg，训练30–45分钟，蛋白质7g，饮水1.5L。", count: 9)
        let paragraphs = ReportTextLayout.paragraphs(in: body)
        XCTAssertGreaterThan(paragraphs.count, 1)
        XCTAssertEqual(paragraphs.joined(), body)
        XCTAssertTrue(paragraphs.allSatisfy { !$0.hasPrefix("5kg") && !$0.hasSuffix("74.") })
    }

    func testExistingNewlinesAndMarkdownRemainUntouched() {
        let long = String(repeating: "本周训练较少，需要核对记录。", count: 20)
        for body in ["## 结论\n\n\(long)\n- 恢复训练", "**\(long)**", "[\(long)](https://example.com)", "`\(long)`"] {
            XCTAssertEqual(ReportTextLayout.paragraphs(in: body), [body])
        }
    }

    func testShortAndEmptyReportsRemainUnchanged() {
        for body in ["", "建议先核对记录，再恢复活动。", "No workouts. Check the records."] {
            XCTAssertEqual(ReportTextLayout.paragraphs(in: body), [body])
        }
    }

    func testQuotesAndParentheticalSentencesStayTogether() {
        let prefix = String(repeating: "先记录活动，", count: 20)
        let sentence = "（备注：这是补充。不能在括号内断段。）“逐步恢复。继续记录。”"
        let body = prefix + sentence + String(repeating: "记录完整后才能分析。", count: 15)
        let paragraphs = ReportTextLayout.paragraphs(in: body)
        XCTAssertEqual(paragraphs.joined(), body)
        XCTAssertTrue(paragraphs.first?.hasSuffix("”") == true)
        XCTAssertTrue(paragraphs.first?.contains(sentence) == true)
    }

    func testLongTextWithoutSafeSentenceBoundaryIsPreserved() {
        let body = String(repeating: "Please check Dr. Li's advice at 7.30 before training, ", count: 9)
        XCTAssertEqual(ReportTextLayout.paragraphs(in: body), [body])
    }

    func testStructuredFoodNamesUseAtMostTwoNamesAndExactItemCount() {
        XCTAssertEqual(RecordDisplayName.meal(names: ["蜜橘", "柑橘", "米饭"], fallback: "旧摘要"), "蜜橘、柑橘 等 3 项")
        XCTAssertEqual(RecordDisplayName.meal(names: ["牛肉面"], fallback: "旧摘要"), "牛肉面")
    }

    func testOnlyCompleteLongTrailingFoodAnnotationIsCompacted() {
        XCTAssertEqual(RecordDisplayName.compactFoodName("石榴籽（剥好的石榴粒，装于密封袋）"), "石榴籽")
        XCTAssertEqual(RecordDisplayName.compactFoodName("石榴籽 (peeled seeds, packed in a sealed bag)"), "石榴籽")
    }

    func testFoodQualifiersAndMalformedAnnotationsArePreserved() {
        for name in ["牛奶（无乳糖）", "鸡胸肉(熟重)", "牛奶（有机）250ml", "石榴籽（剥好的石榴粒，装于密封袋", "（剥好的石榴粒，装于密封袋）", "牛奶（原味（没有加糖），独立包装）"] {
            XCTAssertEqual(RecordDisplayName.compactFoodName(name), name)
        }
    }

    func testMissingStructuredNamesKeepOriginalFallback() {
        for names in [[], [""], ["米饭", " "]] {
            XCTAssertEqual(RecordDisplayName.meal(names: names, fallback: "完整原始描述（需核对）"), "完整原始描述（需核对）")
        }
    }
}
