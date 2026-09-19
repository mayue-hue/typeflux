import AppKit
import SwiftUI
@testable import Typeflux
import XCTest

final class StudioHistoryRowLayoutTests: XCTestCase {
    @MainActor
    func testLongPreviewKeepsRoomForTextWhenAllActionsAreAvailable() {
        let record = HistoryPresentationRecord(
            id: UUID(),
            date: Date(timeIntervalSince1970: 0),
            timestampText: "19:32",
            sourceName: "Test",
            previewText: Array(
                repeating: "A stable transcription preview",
                count: 6
            ).joined(separator: " "),
            audioFilePath: "/tmp/test.wav",
            transcriptText: "A stable transcription preview",
            personaPrompt: nil,
            personaResultText: nil,
            openCCResultText: nil,
            openCCConfig: nil,
            postProcessedText: nil,
            selectionOriginalText: nil,
            selectionEditedText: nil,
            pipelineTimeline: nil,
            errorMessage: nil,
            applyMessage: nil,
            hasTranscriptToCopy: true,
            canRetry: true,
            hasFailure: false,
            failureMessage: nil,
            accentName: "Test",
            accentColorName: "blue"
        )
        let row = StudioHistoryRow(
            record: record,
            onCopyResult: {},
            onCopyTranscript: {},
            onDownloadAudio: {},
            onPlayAudio: {},
            isAudioPlaying: false,
            onDelete: {},
            onRetry: {}
        )
        .frame(width: 1_000)

        let host = NSHostingView(rootView: row)
        let size = host.fittingSize

        XCTAssertEqual(size.width, 1_000, accuracy: 1)
        XCTAssertLessThanOrEqual(
            size.height,
            90,
            "History actions must not expand and force the preview into a narrow text column"
        )
    }
}
