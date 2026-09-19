@testable import Typeflux
import XCTest

final class InputContextSnapshotTests: XCTestCase {
    func testMakeReturnsNilWhenInputIsNotEditable() {
        let snapshot = CurrentInputTextSnapshot(
            processName: "Notes",
            text: "Hello world",
            selectedRange: CFRange(location: 5, length: 0),
            isEditable: false,
            isFocusedTarget: false
        )

        XCTAssertNil(InputContextSnapshot.make(inputSnapshot: snapshot, selectionSnapshot: TextSelectionSnapshot()))
    }

    func testMakeAllowsFocusedElementWhenFocusedAttributeIsFalse() {
        let snapshot = CurrentInputTextSnapshot(
            processName: "Notes",
            text: "Hello world",
            selectedRange: CFRange(location: 5, length: 0),
            isEditable: true,
            isFocusedTarget: false
        )

        let context = InputContextSnapshot.make(
            inputSnapshot: snapshot,
            selectionSnapshot: TextSelectionSnapshot()
        )

        XCTAssertEqual(context?.prefix, "Hello")
        XCTAssertEqual(context?.suffix, " world")
        XCTAssertFalse(context?.isFocusedTarget ?? true)
    }

    func testMakeFallsBackToSelectionWhenFocusedElementIsNotEditable() {
        let input = CurrentInputTextSnapshot(
            processName: "Zed",
            bundleIdentifier: "dev.zed.Zed",
            role: "AXWindow",
            text: nil,
            selectedRange: nil,
            isEditable: false,
            isFocusedTarget: true,
            failureReason: "focused-element-not-editable"
        )

        var selection = TextSelectionSnapshot()
        selection.processName = "Zed"
        selection.bundleIdentifier = "dev.zed.Zed"
        selection.selectedText = "Selected markdown paragraph"
        selection.source = "clipboard-copy"
        selection.isFocusedTarget = true

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: selection,
            selectionLimit: 8
        )

        XCTAssertEqual(context?.appName, "Zed")
        XCTAssertEqual(context?.bundleIdentifier, "dev.zed.Zed")
        XCTAssertEqual(context?.role, "AXWindow")
        XCTAssertFalse(context?.isEditable ?? true)
        XCTAssertTrue(context?.isFocusedTarget ?? false)
        XCTAssertEqual(context?.prefix, "")
        XCTAssertEqual(context?.selectedText, "Selected")
        XCTAssertEqual(context?.suffix, "")
    }

    func testMakeBuildsPrefixAndSuffixFromDocumentTextWhenAXFocusIsWindow() {
        let input = CurrentInputTextSnapshot(
            processName: "Zed",
            bundleIdentifier: "dev.zed.Zed",
            role: "AXWindow",
            text: "before paragraph\nSelected markdown paragraph\nafter paragraph",
            selectedRange: nil,
            isEditable: false,
            isFocusedTarget: true,
            failureReason: "focused-element-not-editable-document-context",
            documentURL: URL(fileURLWithPath: "/tmp/v2ex.md")
        )

        var selection = TextSelectionSnapshot()
        selection.processName = "Zed"
        selection.bundleIdentifier = "dev.zed.Zed"
        selection.selectedText = "Selected markdown paragraph"
        selection.source = "clipboard-copy"
        selection.isFocusedTarget = true

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: selection,
            prefixLimit: 7,
            suffixLimit: 6
        )

        XCTAssertEqual(context?.appName, "Zed")
        XCTAssertEqual(context?.role, "AXWindow")
        XCTAssertEqual(context?.prefix, "agraph\n")
        XCTAssertEqual(context?.selectedText, "Selected markdown paragraph")
        XCTAssertEqual(context?.suffix, "\nafter")
    }

    func testMakeBuildsDocumentContextWithNormalizedSelectionMatch() {
        let input = CurrentInputTextSnapshot(
            processName: "Sublime Text",
            bundleIdentifier: "com.sublimetext.4",
            role: "AXWindow",
            text: "before paragraph\n做一个“能用的原型”和做一个“可以给别人用的产品”之间\nafter paragraph",
            selectedRange: nil,
            isEditable: false,
            isFocusedTarget: true,
            failureReason: "focused-element-not-editable-context",
            textSource: "visible-text"
        )

        var selection = TextSelectionSnapshot()
        selection.processName = "Sublime Text"
        selection.bundleIdentifier = "com.sublimetext.4"
        selection.selectedText = "做一个\"能用的原型\"和做一个\"可以给别人用的产品\"之间"
        selection.source = "clipboard-copy"
        selection.isFocusedTarget = true

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: selection,
            prefixLimit: 7,
            suffixLimit: 6
        )

        XCTAssertEqual(context?.prefix, "agraph\n")
        XCTAssertEqual(context?.suffix, "\nafter")
    }

    func testMakeBuildsDocumentContextFromPartialSelectionWhenBufferChanged() {
        let input = CurrentInputTextSnapshot(
            processName: "Sublime Text",
            bundleIdentifier: "com.sublimetext.4",
            role: "AXWindow",
            text: "before\n最初我以为花一两天就能跑通。结果发现，做一个\"能用的原型\"和做一个\"可以给别人用的产品\"之间，差的是一个月的废寝忘食寝食难安。\nafter",
            selectedRange: nil,
            isEditable: false,
            isFocusedTarget: true,
            failureReason: "focused-element-not-editable-context",
            textSource: "application-state"
        )

        var selection = TextSelectionSnapshot()
        selection.processName = "Sublime Text"
        selection.bundleIdentifier = "com.sublimetext.4"
        selection.selectedText = "最初我以为花一两天就能跑通。结果发现，做一个\"能用的原型\"和做一个\"可以给别人用的产品\"之间，差的是一个月的废寝忘食。"
        selection.source = "clipboard-copy"
        selection.isFocusedTarget = true

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: selection,
            prefixLimit: 20,
            suffixLimit: 20
        )

        XCTAssertEqual(context?.prefix, "before\n")
        XCTAssertEqual(context?.selectedText, selection.selectedText)
        XCTAssertNotNil(context?.suffix)
    }

    func testMakeUsesCursorRangeAndIgnoresCopiedLineSelectionFallback() {
        let input = CurrentInputTextSnapshot(
            processName: "Sublime Text",
            bundleIdentifier: "com.sublimetext.4",
            role: "AXWindow",
            text: "最初我以为花一两天就能跑通。结果发现，做一个\"能用的原型\"和做一个\"可以给别人用的产品\"之间，差的是一个月的废寝忘食。\n\n到今天，我终于把它发布出来了。",
            selectedRange: CFRange(location: 58, length: 0),
            isEditable: false,
            isFocusedTarget: true,
            failureReason: "focused-element-not-editable-context",
            textSource: "application-state"
        )

        var selection = TextSelectionSnapshot()
        selection.processName = "Sublime Text"
        selection.bundleIdentifier = "com.sublimetext.4"
        selection.selectedText = "最初我以为花一两天就能跑通。结果发现，做一个\"能用的原型\"和做一个\"可以给别人用的产品\"之间，差的是一个月的废寝忘食。"
        selection.source = "clipboard-copy"
        selection.isFocusedTarget = true

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: selection,
            prefixLimit: 200,
            suffixLimit: 200
        )

        XCTAssertEqual(
            context?.prefix,
            "最初我以为花一两天就能跑通。结果发现，做一个\"能用的原型\"和做一个\"可以给别人用的产品\"之间，差的是一个月的废寝忘食"
        )
        XCTAssertNil(context?.selectedText)
        XCTAssertEqual(context?.suffix, "。\n\n到今天，我终于把它发布出来了。")
    }

    func testMakeSplitsTextAroundCursorAndAppliesLimits() {
        let input = CurrentInputTextSnapshot(
            processName: "Notes",
            role: "AXTextArea",
            text: "0123456789abcdefghij",
            selectedRange: CFRange(location: 10, length: 0),
            isEditable: true,
            isFocusedTarget: true
        )

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: TextSelectionSnapshot(),
            prefixLimit: 4,
            suffixLimit: 3
        )

        XCTAssertEqual(context?.appName, "Notes")
        XCTAssertEqual(context?.role, "AXTextArea")
        XCTAssertEqual(context?.prefix, "6789")
        XCTAssertEqual(context?.suffix, "abc")
        XCTAssertNil(context?.selectedText)
    }

    func testMakeInterpretsSelectedRangeAsUTF16Offset() {
        let input = CurrentInputTextSnapshot(
            processName: "Notes",
            role: "AXTextArea",
            text: "A😀B",
            selectedRange: CFRange(location: 3, length: 0),
            isEditable: true,
            isFocusedTarget: true
        )

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: TextSelectionSnapshot(),
            prefixLimit: 10,
            suffixLimit: 10
        )

        XCTAssertEqual(context?.prefix, "A😀")
        XCTAssertEqual(context?.suffix, "B")
        XCTAssertNil(context?.selectedText)
    }

    func testMakeRejectsSelectedRangeInsideUTF16SurrogatePair() {
        let input = CurrentInputTextSnapshot(
            processName: "Notes",
            role: "AXTextArea",
            text: "A😀B",
            selectedRange: CFRange(location: 2, length: 0),
            isEditable: true,
            isFocusedTarget: true
        )

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: TextSelectionSnapshot()
        )

        XCTAssertNil(context)
    }

    func testMakeIncludesBoundedSelectedText() {
        let input = CurrentInputTextSnapshot(
            processName: "Notes",
            text: "before selected after",
            selectedRange: CFRange(location: 7, length: 8),
            isEditable: true,
            isFocusedTarget: true
        )

        var selection = TextSelectionSnapshot()
        selection.selectedText = "selected"

        let context = InputContextSnapshot.make(
            inputSnapshot: input,
            selectionSnapshot: selection,
            selectionLimit: 4
        )

        XCTAssertEqual(context?.prefix, "before ")
        XCTAssertEqual(context?.selectedText, "sele")
        XCTAssertEqual(context?.suffix, " after")
    }

    func testMakeReturnsNilWhenRangeIsUnreliable() {
        let input = CurrentInputTextSnapshot(
            processName: "Notes",
            text: "short",
            selectedRange: CFRange(location: 99, length: 0),
            isEditable: true,
            isFocusedTarget: true
        )

        XCTAssertNil(InputContextSnapshot.make(inputSnapshot: input, selectionSnapshot: TextSelectionSnapshot()))
    }
}
