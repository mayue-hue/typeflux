@testable import Typeflux
import XCTest

final class TypefluxAudioProcessCommandTests: XCTestCase {
    func testHelpReturnsSuccess() async {
        let exitCode = await TypefluxAudioProcessCommand.run(arguments: ["--help"])

        XCTAssertEqual(exitCode, 0)
    }

    func testMissingAudioReturnsUsageError() async {
        let exitCode = await TypefluxAudioProcessCommand.run(arguments: ["--no-persona"])

        XCTAssertEqual(exitCode, 2)
    }

    func testRejectsMultiplePersonaSelectors() async throws {
        let promptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("typeflux-process-audio-persona-\(UUID().uuidString).txt")
        try "Rewrite tersely.".write(to: promptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: promptURL) }

        let exitCode = await TypefluxAudioProcessCommand.run(arguments: [
            "--audio",
            "/tmp/input.wav",
            "--persona-name",
            "Default",
            "--persona-prompt-file",
            promptURL.path
        ])

        XCTAssertEqual(exitCode, 2)
    }

    func testRejectsUnsupportedProvider() async {
        let exitCode = await TypefluxAudioProcessCommand.run(arguments: [
            "--audio",
            "/tmp/input.wav",
            "--stt-provider",
            "missingProvider",
            "--no-persona"
        ])

        XCTAssertEqual(exitCode, 2)
    }
}
