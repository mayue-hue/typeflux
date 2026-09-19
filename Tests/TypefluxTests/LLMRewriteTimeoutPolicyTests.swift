@testable import Typeflux
import XCTest

final class LLMRewriteTimeoutPolicyTests: XCTestCase {
    func testShortTextUsesConfiguredBaseBudget() {
        let budget = LLMRewriteTimeoutPolicy.budget(
            sourceText: String(repeating: "中", count: 100),
            baseSeconds: 3
        )

        XCTAssertEqual(budget.estimatedInputUnits, 100)
        XCTAssertEqual(budget.firstOutputSeconds, 3)
        XCTAssertEqual(budget.totalSeconds, 3)
        XCTAssertEqual(budget.watchdogSeconds, 13)
    }

    func testLongChineseTextAddsOneAndAHalfSecondsPerFiftyUnits() {
        let expected: [(characters: Int, timeout: TimeInterval)] = [
            (200, 6),
            (500, 15),
            (1_000, 30),
            (1_500, 45)
        ]

        for item in expected {
            let budget = LLMRewriteTimeoutPolicy.budget(
                sourceText: String(repeating: "中", count: item.characters),
                baseSeconds: 3
            )
            XCTAssertEqual(budget.totalSeconds, item.timeout)
        }
    }

    func testCompactASCIIUsesApproximatelyOneUnitPerFourCharacters() {
        let sourceText = String(repeating: "a", count: 400)
        let budget = LLMRewriteTimeoutPolicy.budget(sourceText: sourceText, baseSeconds: 3)

        XCTAssertEqual(budget.estimatedInputUnits, 100)
        XCTAssertEqual(budget.totalSeconds, 3)
    }

    func testWhitespaceDoesNotIncreaseEstimatedInputUnits() {
        let budget = LLMRewriteTimeoutPolicy.budget(
            sourceText: "中\n\t   文",
            baseSeconds: 3
        )

        XCTAssertEqual(budget.estimatedInputUnits, 2)
    }

    func testTotalBudgetIsCappedAtNinetySeconds() {
        let budget = LLMRewriteTimeoutPolicy.budget(
            sourceText: String(repeating: "中", count: 10_000),
            baseSeconds: 3
        )

        XCTAssertEqual(budget.totalSeconds, 90)
        XCTAssertEqual(budget.watchdogSeconds, 100)
    }

    func testFirstOutputBudgetGrowsButStopsAtFifteenSeconds() {
        let medium = LLMRewriteTimeoutPolicy.budget(
            sourceText: String(repeating: "中", count: 1_500),
            baseSeconds: 3
        )
        let veryLong = LLMRewriteTimeoutPolicy.budget(
            sourceText: String(repeating: "中", count: 10_000),
            baseSeconds: 3
        )

        XCTAssertEqual(medium.firstOutputSeconds, 10)
        XCTAssertEqual(veryLong.firstOutputSeconds, 15)
    }

    func testLargerConfiguredBaseRemainsTheMinimum() {
        let budget = LLMRewriteTimeoutPolicy.budget(
            sourceText: String(repeating: "中", count: 200),
            baseSeconds: 30
        )

        XCTAssertEqual(budget.firstOutputSeconds, 30)
        XCTAssertEqual(budget.stallSeconds, 30)
        XCTAssertEqual(budget.totalSeconds, 33)
    }
}
