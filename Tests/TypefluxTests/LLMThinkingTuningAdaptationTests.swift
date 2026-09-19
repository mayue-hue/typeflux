@testable import Typeflux
import XCTest

final class LLMThinkingTuningAdaptationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now: Date!
    private var store: LLMThinkingTuningAdaptationStore!

    override func setUp() {
        super.setUp()
        suiteName = "LLMThinkingTuningAdaptationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        now = Date(timeIntervalSince1970: 1000)
        store = LLMThinkingTuningAdaptationStore(defaults: defaults, now: { self.now })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        now = nil
        super.tearDown()
    }

    func testStartsWithThinkingDisabledCandidate() throws {
        let candidate = try XCTUnwrap(store.candidate(for: baseURL))

        XCTAssertEqual(candidate.id, "thinking-disabled")
        XCTAssertEqual((candidate.parameters["thinking"] as? [String: String])?["type"], "disabled")
    }

    func testLocksSuccessfulCandidate() throws {
        let candidate = try XCTUnwrap(store.candidate(for: baseURL))

        store.recordSuccess(baseURL: baseURL, candidate: candidate, containsThinking: false)

        XCTAssertEqual(store.candidate(for: baseURL)?.id, candidate.id)
        XCTAssertEqual(store.state(for: baseURL).mode, .locked)
    }

    func testUnsupportedParameterAdvancesToNextCandidate() throws {
        let first = try XCTUnwrap(store.candidate(for: baseURL))

        store.recordUnsupportedParameter(baseURL: baseURL, candidate: first)

        XCTAssertEqual(store.candidate(for: baseURL)?.id, "enable-thinking-false")
        XCTAssertEqual(store.state(for: baseURL).mode, .probing)
    }

    func testLockedCandidateRegressesWhenThinkingReturns() throws {
        let first = try XCTUnwrap(store.candidate(for: baseURL))
        store.recordSuccess(baseURL: baseURL, candidate: first, containsThinking: false)

        store.recordSuccess(baseURL: baseURL, candidate: first, containsThinking: true)

        XCTAssertEqual(store.state(for: baseURL).mode, .probing)
        XCTAssertEqual(store.candidate(for: baseURL)?.id, "enable-thinking-false")
        XCTAssertEqual(store.state(for: baseURL).failures.first?.reason, .regressed)
    }

    func testUnsupportedStateCoolsDownForTwentyFourHours() {
        for candidate in LLMThinkingTuningCandidate.all {
            store.recordUnsupportedParameter(baseURL: baseURL, candidate: candidate)
        }

        XCTAssertNil(store.candidate(for: baseURL))

        now = now.addingTimeInterval(LLMThinkingTuningAdaptationStore.cooldownInterval + 1)

        XCTAssertEqual(store.candidate(for: baseURL)?.id, "thinking-disabled")
        XCTAssertEqual(store.state(for: baseURL).mode, .probing)
    }

    func testNormalizesEquivalentBaseURLs() throws {
        let upper = try XCTUnwrap(URL(string: "https://EXAMPLE.com/v1/"))
        let lower = try XCTUnwrap(URL(string: "https://example.com/v1"))

        XCTAssertEqual(
            LLMThinkingTuningAdaptationStore.normalizedBaseURLKey(upper),
            LLMThinkingTuningAdaptationStore.normalizedBaseURLKey(lower)
        )
    }

    func testSettingsStoreClearsAdaptationWhenCustomBaseURLChanges() throws {
        let settings = SettingsStore(defaults: defaults)
        settings.llmRemoteProvider = .custom
        settings.setLLMBaseURL(baseURL.absoluteString, for: .custom)
        let candidate = try XCTUnwrap(store.candidate(for: baseURL))
        store.recordSuccess(baseURL: baseURL, candidate: candidate, containsThinking: false)
        XCTAssertEqual(store.state(for: baseURL).mode, .locked)

        settings.setLLMBaseURL("https://other.example.com/v1", for: .custom)

        XCTAssertEqual(store.state(for: baseURL).mode, .probing)
    }

    func testSettingsStoreClearsOnlyPreviousAndNextCustomBaseURLStates() throws {
        let settings = SettingsStore(defaults: defaults)
        settings.llmRemoteProvider = .custom
        let nextBaseURL = try XCTUnwrap(URL(string: "https://other.example.com/v1"))
        let unrelatedBaseURL = try XCTUnwrap(URL(string: "https://unrelated.example.com/v1"))

        settings.setLLMBaseURL(baseURL.absoluteString, for: .custom)
        for url in [baseURL, nextBaseURL, unrelatedBaseURL] {
            let candidate = try XCTUnwrap(store.candidate(for: url))
            store.recordSuccess(baseURL: url, candidate: candidate, containsThinking: false)
            XCTAssertEqual(store.state(for: url).mode, .locked)
        }

        settings.setLLMBaseURL(nextBaseURL.absoluteString, for: .custom)

        XCTAssertEqual(store.state(for: baseURL).mode, .probing)
        XCTAssertEqual(store.state(for: nextBaseURL).mode, .probing)
        XCTAssertEqual(store.state(for: unrelatedBaseURL).mode, .locked)
    }

    private var baseURL: URL {
        URL(string: "https://llm.example.com/v1")!
    }
}
