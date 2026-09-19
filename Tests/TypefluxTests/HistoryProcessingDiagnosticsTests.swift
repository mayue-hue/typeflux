@testable import Typeflux
import XCTest

final class HistoryProcessingDiagnosticsTests: XCTestCase {
    func testPipelineTimingRoundTripPreservesRaceAndLLMOutcomes() throws {
        for outcome: LLMProcessingOutcome in [.timedOutFallback, .requestFailedFallback] {
            let timing = HistoryPipelineTiming(
                asrRace: Self.raceDiagnostics(),
                llmOutcome: Self.llmDiagnostics(outcome: outcome)
            )

            let data = try JSONEncoder().encode(timing)
            let decoded = try JSONDecoder().decode(HistoryPipelineTiming.self, from: data)

            XCTAssertEqual(decoded, timing)
            XCTAssertTrue(decoded.hasData)
            XCTAssertEqual(decoded.generatedStats().asrRace, timing.asrRace)
            XCTAssertEqual(decoded.generatedStats().llmOutcome, timing.llmOutcome)
        }
    }

    func testPipelineTimingDecodesLegacyPayloadWithoutDiagnostics() throws {
        let decoded = try JSONDecoder().decode(HistoryPipelineTiming.self, from: Data("{}".utf8))

        XCTAssertNil(decoded.asrRace)
        XCTAssertNil(decoded.llmOutcome)
        XCTAssertFalse(decoded.hasData)
    }

    func testLLMOutcomeComputesDurationAndClampsReversedDates() {
        let start = Date(timeIntervalSince1970: 100)
        let completed = LLMProcessingOutcomeDiagnostics(
            startedAt: start,
            completedAt: start.addingTimeInterval(3.004),
            timeoutMilliseconds: 3_000,
            outcome: .timedOutFallback,
            usedTranscriptFallback: true
        )
        let reversed = LLMProcessingOutcomeDiagnostics(
            startedAt: start,
            completedAt: start.addingTimeInterval(-1),
            timeoutMilliseconds: -20,
            outcome: .failed,
            usedTranscriptFallback: false
        )

        XCTAssertEqual(completed.durationMilliseconds, 3_004)
        XCTAssertEqual(completed.timeoutMilliseconds, 3_000)
        XCTAssertEqual(reversed.durationMilliseconds, 0)
        XCTAssertEqual(reversed.timeoutMilliseconds, 0)
        XCTAssertEqual(LLMProcessingOutcomeDiagnostics.clampedMilliseconds(for: .infinity), Int.max)
        XCTAssertEqual(LLMProcessingOutcomeDiagnostics.clampedMilliseconds(for: .nan), 0)
    }

    func testLLMOutcomePreservesDynamicTimeoutDiagnostics() throws {
        let start = Date(timeIntervalSince1970: 100)
        let outcome = LLMProcessingOutcomeDiagnostics(
            startedAt: start,
            completedAt: start.addingTimeInterval(10),
            timeoutMilliseconds: 15_000,
            outcome: .timedOutFallback,
            usedTranscriptFallback: true,
            baseTimeoutMilliseconds: 3_000,
            estimatedInputUnits: 500,
            firstOutputTimeoutMilliseconds: 5_000,
            stallTimeoutMilliseconds: 10_000,
            timeoutKind: .stalledOutput
        )

        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(LLMProcessingOutcomeDiagnostics.self, from: data)

        XCTAssertEqual(decoded, outcome)
        XCTAssertEqual(decoded.baseTimeoutMilliseconds, 3_000)
        XCTAssertEqual(decoded.estimatedInputUnits, 500)
        XCTAssertEqual(decoded.timeoutKind, .stalledOutput)
    }

    private static func raceDiagnostics() -> ASRRaceDiagnostics {
        let start = Date(timeIntervalSince1970: 1_000)
        return ASRRaceDiagnostics(
            startedAt: start,
            selectedAt: start.addingTimeInterval(3),
            priorityWindowMilliseconds: 3_000,
            decisionDurationMilliseconds: 3_000,
            selectedSource: .local,
            selectionReason: .localAtPriorityDeadline,
            cloudPriorityWindowExceeded: true,
            cloudAttempt: ASRAttemptDiagnostics(
                outcome: .cancelled,
                durationMilliseconds: 3_000
            ),
            localAttempt: ASRAttemptDiagnostics(
                outcome: .succeeded,
                durationMilliseconds: 720,
                completedAt: start.addingTimeInterval(0.72)
            )
        )
    }

    private static func llmDiagnostics(outcome: LLMProcessingOutcome) -> LLMProcessingOutcomeDiagnostics {
        let start = Date(timeIntervalSince1970: 1_003)
        return LLMProcessingOutcomeDiagnostics(
            startedAt: start,
            completedAt: start.addingTimeInterval(3),
            timeoutMilliseconds: 3_000,
            outcome: outcome,
            usedTranscriptFallback: true
        )
    }
}
