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

    func testPointedTargetChoosesSmallestContainingEditableFrame() {
        let frames = [
            CGRect(x: 0, y: 0, width: 600, height: 400),
            CGRect(x: 100, y: 80, width: 300, height: 100),
            CGRect(x: 120, y: 90, width: 120, height: 40)
        ]

        XCTAssertEqual(
            MouseVoicePointedTargetPolicy.bestCandidateIndex(
                point: CGPoint(x: 150, y: 100),
                frames: frames
            ),
            2
        )
    }

    func testPointedTargetRejectsBlankCanvasArea() {
        XCTAssertNil(
            MouseVoicePointedTargetPolicy.bestCandidateIndex(
                point: CGPoint(x: 500, y: 300),
                frames: [CGRect(x: 100, y: 80, width: 300, height: 100)]
            )
        )
    }

    func testHandleAppearsCenteredBelowLongPressPoint() {
        let origin = MouseVoiceHandlePlacement.origin(
            near: CGPoint(x: 400, y: 300),
            handleSize: CGSize(width: 38, height: 38),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        XCTAssertEqual(origin, CGPoint(x: 381, y: 258))
    }

    func testHandleStaysInsideScreenNearBottomEdge() {
        let origin = MouseVoiceHandlePlacement.origin(
            near: CGPoint(x: 990, y: 20),
            handleSize: CGSize(width: 38, height: 38),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        XCTAssertEqual(origin, CGPoint(x: 955, y: 7))
    }

    func testHandleHitTargetIncludesSmallTolerance() {
        let frame = CGRect(x: 100, y: 100, width: 38, height: 38)
        XCTAssertTrue(MouseVoiceHandlePlacement.contains(CGPoint(x: 96, y: 119), handleFrame: frame))
        XCTAssertFalse(MouseVoiceHandlePlacement.contains(CGPoint(x: 90, y: 119), handleFrame: frame))
    }

    func testHandleCanvasContainsLargestAnimatedRing() {
        let animatedRingDiameter = (
            MouseVoiceHandleGeometry.ringDiameter
                + MouseVoiceHandleGeometry.maximumRingLineWidth
        ) * MouseVoiceHandleGeometry.maximumVisualScale
            + MouseVoiceHandleGeometry.maximumMagneticOffset * 2

        XCTAssertLessThanOrEqual(
            animatedRingDiameter,
            MouseVoiceHandleGeometry.canvasSize.width
        )
        XCTAssertLessThanOrEqual(
            animatedRingDiameter,
            MouseVoiceHandleGeometry.canvasSize.height
        )
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

    func testKnownDocumentEditorsAllowOpaqueFocusedWindow() {
        for bundleIdentifier in [
            "com.sublimetext.4",
            "dev.zed.Zed",
            "com.apple.iWork.Pages",
            "com.apple.Pages"
        ] {
            XCTAssertTrue(
                MouseVoiceOpaqueTargetPolicy.allowsOpaqueFocusedFallback(
                    role: "AXWindow",
                    bundleIdentifier: bundleIdentifier
                ),
                bundleIdentifier
            )
        }
    }

    func testKnownDocumentEditorsAllowOpaqueWindowAtPointer() {
        XCTAssertTrue(
            MouseVoiceOpaqueTargetPolicy.allowsOpaqueHit(
                role: "AXWindow",
                bundleIdentifier: "com.sublimetext.4"
            )
        )
    }

    func testWeChatRequiresPointerHitOnOpaqueEditorContainer() {
        let bundleIdentifier = "com.tencent.xinWeChat"
        XCTAssertTrue(
            MouseVoiceOpaqueTargetPolicy.allowsOpaqueHit(
                role: "AXGroup",
                bundleIdentifier: bundleIdentifier
            )
        )
        XCTAssertFalse(
            MouseVoiceOpaqueTargetPolicy.allowsOpaqueFocusedFallback(
                role: "AXWindow",
                bundleIdentifier: bundleIdentifier
            )
        )
        XCTAssertFalse(
            MouseVoiceOpaqueTargetPolicy.allowsOpaqueHit(
                role: "AXWindow",
                bundleIdentifier: bundleIdentifier
            )
        )
    }

    func testOpaqueCompatibilityRejectsButtonsAndUnknownApps() {
        XCTAssertFalse(
            MouseVoiceOpaqueTargetPolicy.allowsOpaqueHit(
                role: "AXButton",
                bundleIdentifier: "dev.zed.Zed"
            )
        )
        XCTAssertFalse(
            MouseVoiceOpaqueTargetPolicy.allowsOpaqueFocusedFallback(
                role: "AXWindow",
                bundleIdentifier: "com.example.UnknownEditor"
            )
        )
    }

    func testMouseVoiceSettingsDefaultsAndPersistence() throws {
        let suiteName = "MouseVoiceInputTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        XCTAssertTrue(store.mouseVoiceInputEnabled)
        XCTAssertEqual(store.mouseVoiceActivationStyle, .dragRelease)

        store.mouseVoiceInputEnabled = false
        store.mouseVoiceActivationStyle = .hoverDwell

        XCTAssertFalse(store.mouseVoiceInputEnabled)
        XCTAssertEqual(store.mouseVoiceActivationStyle, .hoverDwell)

        store.mouseVoiceActivationStyle = .click
        XCTAssertEqual(store.mouseVoiceActivationStyle, .click)
    }
}
