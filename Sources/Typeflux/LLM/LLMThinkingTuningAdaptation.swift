import Foundation

struct LLMThinkingTuningCandidate: Equatable {
    let id: String
    let parameters: [String: Any]

    static let all: [LLMThinkingTuningCandidate] = [
        LLMThinkingTuningCandidate(
            id: "thinking-disabled",
            parameters: ["thinking": ["type": "disabled"]]
        ),
        LLMThinkingTuningCandidate(
            id: "enable-thinking-false",
            parameters: ["enable_thinking": false]
        ),
        LLMThinkingTuningCandidate(
            id: "reasoning-effort-none",
            parameters: ["reasoning": ["effort": "none"]]
        ),
        LLMThinkingTuningCandidate(
            id: "openrouter-reasoning-exclude",
            parameters: [
                "reasoning": [
                    "effort": "none",
                    "exclude": true
                ],
                "include_reasoning": false
            ]
        ),
        LLMThinkingTuningCandidate(
            id: "thinking-and-enable-thinking",
            parameters: [
                "thinking": ["type": "disabled"],
                "enable_thinking": false
            ]
        ),
        LLMThinkingTuningCandidate(
            id: "thinking-and-reasoning-effort",
            parameters: [
                "thinking": ["type": "disabled"],
                "reasoning": ["effort": "none"]
            ]
        ),
        LLMThinkingTuningCandidate(
            id: "all-known-thinking-controls",
            parameters: [
                "thinking": ["type": "disabled"],
                "enable_thinking": false,
                "reasoning": [
                    "effort": "none",
                    "exclude": true
                ],
                "include_reasoning": false
            ]
        )
    ]

    static func candidate(id: String) -> LLMThinkingTuningCandidate? {
        all.first { $0.id == id }
    }

    static func index(of candidateID: String) -> Int? {
        all.firstIndex { $0.id == candidateID }
    }

    static func == (lhs: LLMThinkingTuningCandidate, rhs: LLMThinkingTuningCandidate) -> Bool {
        lhs.id == rhs.id
    }
}

enum LLMThinkingTuningFailureReason: String, Codable, Equatable {
    case unsupportedParameter
    case ineffective
    case regressed
}

struct LLMThinkingTuningCandidateFailure: Codable, Equatable {
    let candidateID: String
    let reason: LLMThinkingTuningFailureReason
    let observedAt: Date
}

struct LLMThinkingTuningAdaptationState: Codable, Equatable {
    enum Mode: String, Codable {
        case probing
        case locked
        case unsupported
    }

    var mode: Mode
    var nextCandidateIndex: Int
    var lockedCandidateID: String?
    var lockedAt: Date?
    var unsupportedMarkedAt: Date?
    var failures: [LLMThinkingTuningCandidateFailure]

    static func probing(
        nextCandidateIndex: Int = 0,
        failures: [LLMThinkingTuningCandidateFailure] = []
    ) -> LLMThinkingTuningAdaptationState {
        LLMThinkingTuningAdaptationState(
            mode: .probing,
            nextCandidateIndex: nextCandidateIndex,
            lockedCandidateID: nil,
            lockedAt: nil,
            unsupportedMarkedAt: nil,
            failures: failures
        )
    }

    static func locked(
        candidateID: String,
        lockedAt: Date,
        failures: [LLMThinkingTuningCandidateFailure]
    ) -> LLMThinkingTuningAdaptationState {
        LLMThinkingTuningAdaptationState(
            mode: .locked,
            nextCandidateIndex: 0,
            lockedCandidateID: candidateID,
            lockedAt: lockedAt,
            unsupportedMarkedAt: nil,
            failures: failures
        )
    }

    static func unsupported(
        markedAt: Date,
        failures: [LLMThinkingTuningCandidateFailure]
    ) -> LLMThinkingTuningAdaptationState {
        LLMThinkingTuningAdaptationState(
            mode: .unsupported,
            nextCandidateIndex: 0,
            lockedCandidateID: nil,
            lockedAt: nil,
            unsupportedMarkedAt: markedAt,
            failures: failures
        )
    }
}

final class LLMThinkingTuningAdaptationStore: @unchecked Sendable {
    static let cooldownInterval: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let now: () -> Date
    private let defaultsKey = "llm.custom.thinkingTuning.adaptationStates"
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func candidate(for baseURL: URL) -> LLMThinkingTuningCandidate? {
        locked {
            candidateLocked(for: baseURL)
        }
    }

    func applyCandidate(
        to body: inout [String: Any],
        for baseURL: URL
    ) -> LLMThinkingTuningCandidate? {
        guard let candidate = candidate(for: baseURL) else { return nil }
        for (key, value) in candidate.parameters {
            body[key] = value
        }
        return candidate
    }

    func recordUnsupportedParameter(baseURL: URL, candidate: LLMThinkingTuningCandidate?) {
        guard let candidate else { return }
        locked {
            recordFailureLocked(baseURL: baseURL, candidate: candidate, reason: .unsupportedParameter)
        }
    }

    func recordSuccess(
        baseURL: URL,
        candidate: LLMThinkingTuningCandidate?,
        containsThinking: Bool
    ) {
        guard let candidate else { return }
        locked {
            if containsThinking {
                let state = stateLocked(for: baseURL)
                let reason: LLMThinkingTuningFailureReason = if state.mode == .locked,
                                                                state.lockedCandidateID == candidate.id {
                    .regressed
                } else {
                    .ineffective
                }
                recordFailureLocked(baseURL: baseURL, candidate: candidate, reason: reason)
                return
            }

            let key = Self.normalizedBaseURLKey(baseURL)
            var states = loadStates()
            let failures = states[key]?.failures ?? []
            states[key] = .locked(candidateID: candidate.id, lockedAt: now(), failures: failures)
            saveStates(states)
        }
    }

    func state(for baseURL: URL) -> LLMThinkingTuningAdaptationState {
        locked {
            stateLocked(for: baseURL)
        }
    }

    func reset(baseURL: URL) {
        let key = Self.normalizedBaseURLKey(baseURL)
        locked {
            var states = loadStates()
            states.removeValue(forKey: key)
            saveStates(states)
        }
    }

    func resetAll() {
        locked {
            defaults.removeObject(forKey: defaultsKey)
        }
    }

    static func normalizedBaseURLKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil

        var value = components.string ?? url.absoluteString
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private func candidateLocked(for baseURL: URL) -> LLMThinkingTuningCandidate? {
        let key = Self.normalizedBaseURLKey(baseURL)
        var states = loadStates()
        let state = states[key] ?? .probing()

        switch state.mode {
        case .locked:
            guard let candidateID = state.lockedCandidateID else {
                states[key] = .probing()
                saveStates(states)
                return LLMThinkingTuningCandidate.all.first
            }
            return LLMThinkingTuningCandidate.candidate(id: candidateID)

        case .unsupported:
            if let markedAt = state.unsupportedMarkedAt,
               now().timeIntervalSince(markedAt) < Self.cooldownInterval {
                return nil
            }
            states[key] = .probing()
            saveStates(states)
            return LLMThinkingTuningCandidate.all.first

        case .probing:
            let index = min(max(state.nextCandidateIndex, 0), LLMThinkingTuningCandidate.all.count)
            guard index < LLMThinkingTuningCandidate.all.count else { return nil }
            return LLMThinkingTuningCandidate.all[index]
        }
    }

    private func stateLocked(for baseURL: URL) -> LLMThinkingTuningAdaptationState {
        loadStates()[Self.normalizedBaseURLKey(baseURL)] ?? .probing()
    }

    private func recordFailureLocked(
        baseURL: URL,
        candidate: LLMThinkingTuningCandidate,
        reason: LLMThinkingTuningFailureReason
    ) {
        let key = Self.normalizedBaseURLKey(baseURL)
        var states = loadStates()
        let state = states[key] ?? .probing()
        var failures = state.failures.filter { $0.candidateID != candidate.id }
        failures.append(
            LLMThinkingTuningCandidateFailure(
                candidateID: candidate.id,
                reason: reason,
                observedAt: now()
            )
        )

        guard let currentIndex = LLMThinkingTuningCandidate.index(of: candidate.id) else {
            states[key] = .unsupported(markedAt: now(), failures: failures)
            saveStates(states)
            return
        }

        let failedIDs = Set(failures.map(\.candidateID))
        let nextIndex = LLMThinkingTuningCandidate.all[(currentIndex + 1)...]
            .firstIndex { !failedIDs.contains($0.id) }

        if let nextIndex {
            states[key] = .probing(nextCandidateIndex: nextIndex, failures: failures)
        } else {
            states[key] = .unsupported(markedAt: now(), failures: failures)
        }
        saveStates(states)
    }

    private func loadStates() -> [String: LLMThinkingTuningAdaptationState] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: LLMThinkingTuningAdaptationState].self, from: data)) ?? [:]
    }

    private func saveStates(_ states: [String: LLMThinkingTuningAdaptationState]) {
        guard !states.isEmpty else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
