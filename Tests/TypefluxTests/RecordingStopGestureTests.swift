import XCTest
@testable import Typeflux

final class RecordingStopGestureTests: XCTestCase {
    private let control = HotkeyBinding.modifierFlag(for: 59)
    private let shift = HotkeyBinding.modifierFlag(for: 56)
    private let fn = HotkeyBinding.modifierFlag(for: 63)

    func testEveryCompleteShortcutCanStopRegardlessOfStartingShortcut() {
        let bindings = [
            HotkeyBinding(keyCode: 49, modifierFlags: control | shift),
            HotkeyBinding(keyCode: 0, modifierFlags: control),
            HotkeyBinding(keyCode: 38, modifierFlags: shift)
        ]
        for starting in bindings {
            for stopping in bindings {
                var gesture = RecordingStopGesture()
                XCTAssertFalse(gesture.handle(type: .keyDown, keyCode: starting.keyCode, flags: starting.modifierFlags,
                    isRepeat: false, bindings: bindings, enabled: false, timestamp: 1))
                XCTAssertFalse(gesture.handle(type: .keyUp, keyCode: starting.keyCode, flags: starting.modifierFlags,
                    isRepeat: false, bindings: bindings, enabled: true, timestamp: 1.1))
                XCTAssertTrue(gesture.handle(type: .keyDown, keyCode: stopping.keyCode, flags: stopping.modifierFlags,
                    isRepeat: false, bindings: bindings, enabled: true, timestamp: 2))
                XCTAssertFalse(gesture.handle(type: .keyDown, keyCode: stopping.keyCode, flags: stopping.modifierFlags,
                    isRepeat: true, bindings: bindings, enabled: true, timestamp: 2.1))
                XCTAssertFalse(gesture.handle(type: .keyUp, keyCode: stopping.keyCode, flags: stopping.modifierFlags,
                    isRepeat: false, bindings: bindings, enabled: true, timestamp: 2.2))
            }
        }
    }

    func testTypingAndPartialCombinationDoNotStop() {
        var gesture = RecordingStopGesture()
        let binding = HotkeyBinding(keyCode: 49, modifierFlags: control | shift)
        for flags in [UInt(0), control, shift] {
            XCTAssertFalse(gesture.handle(type: .keyDown, keyCode: 49, flags: flags,
                isRepeat: false, bindings: [binding], enabled: true, timestamp: 1))
            _ = gesture.handle(type: .keyUp, keyCode: 49, flags: flags,
                isRepeat: false, bindings: [binding], enabled: true, timestamp: 1.1)
        }
        XCTAssertFalse(gesture.handle(type: .keyDown, keyCode: 0, flags: control | shift,
            isRepeat: false, bindings: [binding], enabled: true, timestamp: 2))
        XCTAssertTrue(gesture.handle(type: .keyDown, keyCode: 49, flags: control | shift,
            isRepeat: false, bindings: [binding], enabled: true, timestamp: 3))
    }

    func testModifierChordRequiresCorrectPhysicalKeysInEitherOrder() {
        for keys in [[63, 56], [56, 63]] {
            var gesture = RecordingStopGesture()
            XCTAssertFalse(gesture.handle(type: .flagsChanged, keyCode: keys[0], flags: HotkeyBinding.modifierFlag(for: keys[0]),
                isRepeat: false, bindings: [.defaultAuxiliary], enabled: true, timestamp: 1))
            XCTAssertTrue(gesture.handle(type: .flagsChanged, keyCode: keys[1], flags: fn | shift,
                isRepeat: false, bindings: [.defaultAuxiliary], enabled: true, timestamp: 1.1))
        }
        var gesture = RecordingStopGesture()
        _ = gesture.handle(type: .flagsChanged, keyCode: 60, flags: shift,
            isRepeat: false, bindings: [.defaultAuxiliary], enabled: true, timestamp: 1)
        XCTAssertFalse(gesture.handle(type: .flagsChanged, keyCode: 63, flags: fn | shift,
            isRepeat: false, bindings: [.defaultAuxiliary], enabled: true, timestamp: 1.1))
    }

    func testStartupHeldKeyAndReleaseDoNotStopButNewPressDoes() {
        var gesture = RecordingStopGesture()
        XCTAssertFalse(gesture.handle(type: .flagsChanged, keyCode: 63, flags: fn,
            isRepeat: false, bindings: [.defaultActivation], enabled: false, timestamp: 1))
        XCTAssertFalse(gesture.handle(type: .flagsChanged, keyCode: 63, flags: 0,
            isRepeat: false, bindings: [.defaultActivation], enabled: true, timestamp: 2))
        XCTAssertTrue(gesture.handle(type: .flagsChanged, keyCode: 63, flags: fn,
            isRepeat: false, bindings: [.defaultActivation], enabled: true, timestamp: 3))
    }

    func testDoubleTapRequiresTwoFreshTapsWithinWindow() {
        for binding in [HotkeyBinding.rightOptionAsk, HotkeyBinding(keyCode: 49, modifierFlags: 0, pressCount: 2)] {
            var gesture = RecordingStopGesture()
            let down: HotkeyPhysicalEventType = binding.physicalModifierKeys.isEmpty ? .keyDown : .flagsChanged
            let up: HotkeyPhysicalEventType = binding.physicalModifierKeys.isEmpty ? .keyUp : .flagsChanged
            for time in [1.0, 2.0] {
                XCTAssertFalse(gesture.handle(type: down, keyCode: binding.keyCode, flags: binding.modifierFlags,
                    isRepeat: false, bindings: [binding], enabled: true, timestamp: time))
                XCTAssertFalse(gesture.handle(type: up, keyCode: binding.keyCode, flags: 0,
                    isRepeat: false, bindings: [binding], enabled: true, timestamp: time + 0.1))
            }
            XCTAssertTrue(gesture.handle(type: down, keyCode: binding.keyCode, flags: binding.modifierFlags,
                isRepeat: false, bindings: [binding], enabled: true, timestamp: 2.2))
        }
    }

    func testStartupReleaseCannotCountAsFirstTapOfStopDoubleTap() {
        var gesture = RecordingStopGesture()
        let binding = HotkeyBinding.rightOptionAsk
        _ = gesture.handle(type: .flagsChanged, keyCode: 61, flags: binding.modifierFlags,
            isRepeat: false, bindings: [binding], enabled: false, timestamp: 1)
        _ = gesture.handle(type: .flagsChanged, keyCode: 61, flags: 0,
            isRepeat: false, bindings: [binding], enabled: true, timestamp: 1.1)
        XCTAssertFalse(gesture.handle(type: .flagsChanged, keyCode: 61, flags: binding.modifierFlags,
            isRepeat: false, bindings: [binding], enabled: true, timestamp: 1.2))
        _ = gesture.handle(type: .flagsChanged, keyCode: 61, flags: 0,
            isRepeat: false, bindings: [binding], enabled: true, timestamp: 1.3)
        XCTAssertTrue(gesture.handle(type: .flagsChanged, keyCode: 61, flags: binding.modifierFlags,
            isRepeat: false, bindings: [binding], enabled: true, timestamp: 1.4))
    }

    func testSecondTapAfterStoppingDoesNotStartAnotherRecording() {
        var gesture = RecordingStopGesture()
        XCTAssertTrue(gesture.handle(type: .flagsChanged, keyCode: 63, flags: fn,
            isRepeat: false, bindings: [.defaultActivation, .defaultAsk], enabled: true, timestamp: 1))
        _ = gesture.handle(type: .flagsChanged, keyCode: 63, flags: 0,
            isRepeat: false, bindings: [.defaultActivation, .defaultAsk], enabled: false, timestamp: 1.1)
        XCTAssertFalse(gesture.handle(type: .flagsChanged, keyCode: 63, flags: fn,
            isRepeat: false, bindings: [.defaultActivation, .defaultAsk], enabled: false, timestamp: 1.2))
        XCTAssertTrue(gesture.suppressesActivation)
        _ = gesture.handle(type: .flagsChanged, keyCode: 63, flags: 0,
            isRepeat: false, bindings: [.defaultActivation, .defaultAsk], enabled: false, timestamp: 1.3)
        _ = gesture.handle(type: .flagsChanged, keyCode: 63, flags: fn,
            isRepeat: false, bindings: [.defaultActivation, .defaultAsk], enabled: false, timestamp: 2)
        XCTAssertFalse(gesture.suppressesActivation)
    }

    func testStopSubmitsOnlyOnceAndNextRecordingCanStopAgain() {
        var gesture = RecordingStopGesture()
        for session in 0..<2 {
            XCTAssertFalse(gesture.handle(type: .keyUp, keyCode: 49, flags: 0,
                isRepeat: false, bindings: [HotkeyBinding(keyCode: 49, modifierFlags: 0)], enabled: false, timestamp: Double(session)))
            XCTAssertTrue(gesture.handle(type: .keyDown, keyCode: 49, flags: 0,
                isRepeat: false, bindings: [HotkeyBinding(keyCode: 49, modifierFlags: 0)], enabled: true, timestamp: Double(session) + 0.1))
            _ = gesture.handle(type: .keyUp, keyCode: 49, flags: 0,
                isRepeat: false, bindings: [HotkeyBinding(keyCode: 49, modifierFlags: 0)], enabled: true, timestamp: Double(session) + 0.2)
            XCTAssertFalse(gesture.handle(type: .keyDown, keyCode: 49, flags: 0,
                isRepeat: false, bindings: [HotkeyBinding(keyCode: 49, modifierFlags: 0)], enabled: true, timestamp: Double(session) + 0.3))
        }
    }
}
