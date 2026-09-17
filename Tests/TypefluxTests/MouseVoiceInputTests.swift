import AppKit
@testable import Typeflux
import XCTest

final class MouseVoiceInputTests: XCTestCase {
    func testAccessibilityAndCocoaCoordinatesRoundTrip() {
        let cocoaPoint = CGPoint(x: 320, y: 180)
        let accessibilityPoint = MouseVoiceCoordinateConverter.accessibilityPoint(
            fromCocoaPoint: cocoaPoint,
            mainScreenMaxY: 900
        )

        XCTAssertEqual(accessibilityPoint, CGPoint(x: 320, y: 720))
        XCTAssertEqual(
            MouseVoiceCoordinateConverter.cocoaFrame(
                fromAccessibilityPosition: accessibilityPoint,
                size: CGSize(width: 240, height: 40),
                mainScreenMaxY: 900
            ),
            CGRect(x: 320, y: 140, width: 240, height: 40)
        )
    }

    func testHandleUsesOutsideRightEdgeWhenSpaceIsAvailable() {
        let origin = MouseVoiceHandlePlacement.origin(
            targetFrame: CGRect(x: 100, y: 200, width: 300, height: 80),
            fallbackPoint: .zero,
            handleSize: CGSize(width: 38, height: 38),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        XCTAssertEqual(origin, CGPoint(x: 407, y: 207))
    }

    func testHandleMovesInsideTargetNearRightScreenEdge() {
        let origin = MouseVoiceHandlePlacement.origin(
            targetFrame: CGRect(x: 850, y: 200, width: 140, height: 80),
            fallbackPoint: .zero,
            handleSize: CGSize(width: 38, height: 38),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        XCTAssertEqual(origin, CGPoint(x: 945, y: 207))
    }

    func testLongPressMovementToleranceRejectsDrag() {
        XCTAssertFalse(
            MouseVoiceLongPressPolicy.exceedsMovementTolerance(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 14, y: 13)
            )
        )
        XCTAssertTrue(
            MouseVoiceLongPressPolicy.exceedsMovementTolerance(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 17, y: 10)
            )
        )
    }

    func testMouseVoiceSettingsDefaultsAndPersistence() throws {
        let suiteName = "MouseVoiceInputTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        XCTAssertTrue(store.smartVoiceHandleEnabled)
        XCTAssertFalse(store.mouseLongPressVoiceInputEnabled)

        store.smartVoiceHandleEnabled = false
        store.mouseLongPressVoiceInputEnabled = true

        XCTAssertFalse(store.smartVoiceHandleEnabled)
        XCTAssertTrue(store.mouseLongPressVoiceInputEnabled)
    }
}
