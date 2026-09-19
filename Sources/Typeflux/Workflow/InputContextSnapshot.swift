import Foundation

struct InputContextSnapshot: Equatable {
    static let defaultPrefixLimit = 500
    static let defaultSuffixLimit = 200
    static let defaultSelectionLimit = 2000

    let appName: String?
    let bundleIdentifier: String?
    let role: String?
    let isEditable: Bool
    let isFocusedTarget: Bool
    let prefix: String
    let suffix: String
    let selectedText: String?

    var hasContent: Bool {
        !prefix.isEmpty || !suffix.isEmpty || !(selectedText?.isEmpty ?? true)
    }

    static func make(
        inputSnapshot: CurrentInputTextSnapshot,
        selectionSnapshot: TextSelectionSnapshot,
        prefixLimit: Int = defaultPrefixLimit,
        suffixLimit: Int = defaultSuffixLimit,
        selectionLimit: Int = defaultSelectionLimit
    ) -> InputContextSnapshot? {
        if let context = rangedInputContext(
            inputSnapshot: inputSnapshot,
            selectionSnapshot: selectionSnapshot,
            prefixLimit: prefixLimit,
            suffixLimit: suffixLimit,
            selectionLimit: selectionLimit
        ) {
            return context
        }

        guard inputSnapshot.isEditable else {
            if let context = documentContext(
                inputSnapshot: inputSnapshot,
                selectionSnapshot: selectionSnapshot,
                prefixLimit: prefixLimit,
                suffixLimit: suffixLimit,
                selectionLimit: selectionLimit
            ) {
                return context
            }
            return selectionOnlyContext(
                inputSnapshot: inputSnapshot,
                selectionSnapshot: selectionSnapshot,
                selectionLimit: selectionLimit
            )
        }

        if let context = documentContext(
            inputSnapshot: inputSnapshot,
            selectionSnapshot: selectionSnapshot,
            prefixLimit: prefixLimit,
            suffixLimit: suffixLimit,
            selectionLimit: selectionLimit
        ) {
            return context
        }
        return selectionOnlyContext(
            inputSnapshot: inputSnapshot,
            selectionSnapshot: selectionSnapshot,
            selectionLimit: selectionLimit
        )
    }

    private static func rangedInputContext(
        inputSnapshot: CurrentInputTextSnapshot,
        selectionSnapshot: TextSelectionSnapshot,
        prefixLimit: Int,
        suffixLimit: Int,
        selectionLimit: Int
    ) -> InputContextSnapshot? {
        guard inputSnapshot.isEditable || inputSnapshot.textSource == "application-state" else {
            return nil
        }
        guard
            let text = inputSnapshot.text,
            !text.isEmpty,
            let selectedRange = inputSnapshot.selectedRange,
            let range = stringRange(from: selectedRange, in: text)
        else {
            return nil
        }

        let selected = selectedRange.length > 0
            ? normalizedSelectedText(
                selectionSnapshot.selectedText,
                fallback: String(text[range]),
                limit: selectionLimit
            )
            : nil
        let prefix = String(text[..<range.lowerBound]).suffixCharacters(prefixLimit)
        let suffix = String(text[range.upperBound...]).prefixCharacters(suffixLimit)

        let snapshot = InputContextSnapshot(
            appName: inputSnapshot.processName ?? selectionSnapshot.processName,
            bundleIdentifier: inputSnapshot.bundleIdentifier ?? selectionSnapshot.bundleIdentifier,
            role: inputSnapshot.role ?? selectionSnapshot.role,
            isEditable: inputSnapshot.isEditable,
            isFocusedTarget: inputSnapshot.isFocusedTarget || selectionSnapshot.isFocusedTarget,
            prefix: prefix,
            suffix: suffix,
            selectedText: selected
        )
        return snapshot.hasContent ? snapshot : nil
    }

    static func logCapture(
        inputSnapshot: CurrentInputTextSnapshot,
        selectionSnapshot: TextSelectionSnapshot,
        context: InputContextSnapshot?
    ) {
        let selectedRangeDescription = inputSnapshot.selectedRange.map {
            "location=\($0.location), length=\($0.length)"
        } ?? "<nil>"
        let selectionRangeDescription = selectionSnapshot.selectedRange.map {
            "location=\($0.location), length=\($0.length)"
        } ?? "<nil>"
        let status = context == nil ? "skipped" : "captured"
        let skipReason = context == nil
            ? inputContextSkipReason(inputSnapshot: inputSnapshot, selectionSnapshot: selectionSnapshot)
            : "<none>"

        NetworkDebugLogger.logMessage(
            """
            [InputContext]
            status: \(status)
            skipReason: \(skipReason)
            inputFailureReason: \(inputSnapshot.failureReason ?? "<nil>")
            appName: \(inputSnapshot.processName ?? selectionSnapshot.processName ?? "<nil>")
            bundleIdentifier: \(inputSnapshot.bundleIdentifier ?? selectionSnapshot.bundleIdentifier ?? "<nil>")
            role: \(inputSnapshot.role ?? selectionSnapshot.role ?? "<nil>")
            documentURL: \(inputSnapshot.documentURL?.path ?? "<nil>")
            inputTextSource: \(inputSnapshot.textSource ?? "<nil>")
            inputIsEditable: \(inputSnapshot.isEditable)
            inputIsFocusedTarget: \(inputSnapshot.isFocusedTarget)
            selectionSource: \(selectionSnapshot.source)
            selectionIsEditable: \(selectionSnapshot.isEditable)
            selectionIsFocusedTarget: \(selectionSnapshot.isFocusedTarget)
            selectedRange: \(selectedRangeDescription)
            selectionSelectedRange: \(selectionRangeDescription)
            inputTextLength: \(inputSnapshot.text?.count ?? 0)
            inputTextPreview:
            \(inputSnapshot.text.map { String($0.prefix(200)) } ?? "")
            selectedTextLength: \(context?.selectedText?.count ?? 0)
            prefix(\(context?.prefix.count ?? 0)):
            \(context?.prefix ?? "")
            selectedText(\(context?.selectedText?.count ?? 0)):
            \(context?.selectedText ?? "")
            suffix(\(context?.suffix.count ?? 0)):
            \(context?.suffix ?? "")
            """
        )
    }

    private static func selectionOnlyContext(
        inputSnapshot: CurrentInputTextSnapshot,
        selectionSnapshot: TextSelectionSnapshot,
        selectionLimit: Int
    ) -> InputContextSnapshot? {
        guard let selected = normalizedSelectedText(
            selectionSnapshot.selectedText,
            fallback: "",
            limit: selectionLimit
        ) else {
            return nil
        }

        return InputContextSnapshot(
            appName: inputSnapshot.processName ?? selectionSnapshot.processName,
            bundleIdentifier: inputSnapshot.bundleIdentifier ?? selectionSnapshot.bundleIdentifier,
            role: selectionSnapshot.role ?? inputSnapshot.role,
            isEditable: inputSnapshot.isEditable || selectionSnapshot.isEditable,
            isFocusedTarget: inputSnapshot.isFocusedTarget || selectionSnapshot.isFocusedTarget,
            prefix: "",
            suffix: "",
            selectedText: selected
        )
    }

    private static func documentContext(
        inputSnapshot: CurrentInputTextSnapshot,
        selectionSnapshot: TextSelectionSnapshot,
        prefixLimit: Int,
        suffixLimit: Int,
        selectionLimit: Int
    ) -> InputContextSnapshot? {
        guard
            let documentText = inputSnapshot.text,
            !documentText.isEmpty,
            let selectedText = selectionSnapshot.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
            !selectedText.isEmpty,
            let range = selectedTextRange(in: documentText, selectedText: selectedText)
        else {
            return nil
        }

        let prefix = String(documentText[..<range.lowerBound]).suffixCharacters(prefixLimit)
        let suffix = String(documentText[range.upperBound...]).prefixCharacters(suffixLimit)
        let boundedSelectedText = String(selectedText.prefix(selectionLimit))
        let snapshot = InputContextSnapshot(
            appName: inputSnapshot.processName ?? selectionSnapshot.processName,
            bundleIdentifier: inputSnapshot.bundleIdentifier ?? selectionSnapshot.bundleIdentifier,
            role: inputSnapshot.role ?? selectionSnapshot.role,
            isEditable: inputSnapshot.isEditable || selectionSnapshot.isEditable,
            isFocusedTarget: inputSnapshot.isFocusedTarget || selectionSnapshot.isFocusedTarget,
            prefix: prefix,
            suffix: suffix,
            selectedText: boundedSelectedText
        )
        return snapshot.hasContent ? snapshot : nil
    }

    private static func inputContextSkipReason(
        inputSnapshot: CurrentInputTextSnapshot,
        selectionSnapshot: TextSelectionSnapshot
    ) -> String {
        guard selectionSnapshot.hasSelection else {
            return inputSnapshot.failureReason ?? "missing-input-and-selection-context"
        }
        if !inputSnapshot.isEditable {
            return inputSnapshot.failureReason ?? "focused-element-not-editable"
        }
        guard let text = inputSnapshot.text, !text.isEmpty else {
            return inputSnapshot.failureReason ?? "missing-input-text"
        }
        guard inputSnapshot.selectedRange != nil else {
            return "missing-selected-range"
        }
        return "invalid-selected-range-or-empty-context"
    }

    private static func stringRange(from cfRange: CFRange, in text: String) -> Range<String.Index>? {
        guard cfRange.location >= 0, cfRange.length >= 0 else { return nil }
        guard cfRange.location <= Int.max - cfRange.length else { return nil }

        return utf16StringRange(from: cfRange, in: text)
    }

    private static func utf16StringRange(from cfRange: CFRange, in text: String) -> Range<String.Index>? {
        let utf16 = text.utf16
        guard cfRange.location <= utf16.count else { return nil }
        guard cfRange.location + cfRange.length <= utf16.count else { return nil }

        let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: cfRange.location)
        let upperUTF16 = utf16.index(lowerUTF16, offsetBy: cfRange.length)
        guard
            let lowerBound = lowerUTF16.samePosition(in: text),
            let upperBound = upperUTF16.samePosition(in: text)
        else {
            return nil
        }
        return lowerBound ..< upperBound
    }

    private static func normalizedSelectedText(
        _ selectedText: String?,
        fallback: String,
        limit: Int
    ) -> String? {
        let candidate = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? selectedText ?? ""
            : fallback
        guard !candidate.isEmpty else { return nil }
        return String(candidate.prefix(limit))
    }

    static func selectedTextRange(in text: String, selectedText: String) -> Range<String.Index>? {
        if let exact = text.range(of: selectedText) {
            return exact
        }

        let normalizedText = normalizedSearchTextWithMap(text)
        let normalizedSelection = normalizedSearchText(selectedText)
        guard !normalizedText.text.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let normalizedRange = normalizedText.text.range(of: normalizedSelection)
            ?? bestPartialSelectedTextRange(in: normalizedText.text, normalizedSelection: normalizedSelection)
        else {
            return nil
        }

        let lowerOffset = normalizedText.text.distance(
            from: normalizedText.text.startIndex,
            to: normalizedRange.lowerBound
        )
        let upperOffset = normalizedText.text.distance(
            from: normalizedText.text.startIndex,
            to: normalizedRange.upperBound
        ) - 1
        guard
            lowerOffset >= 0,
            upperOffset >= lowerOffset,
            lowerOffset < normalizedText.map.count,
            upperOffset < normalizedText.map.count
        else {
            return nil
        }

        return normalizedText.map[lowerOffset].lowerBound ..< normalizedText.map[upperOffset].upperBound
    }

    private static func bestPartialSelectedTextRange(
        in normalizedText: String,
        normalizedSelection: String
    ) -> Range<String.Index>? {
        let minimumLength = 18
        guard normalizedSelection.count >= minimumLength else { return nil }

        let maximumLength = min(80, normalizedSelection.count)
        let minimumIndex = normalizedSelection.index(
            normalizedSelection.startIndex,
            offsetBy: minimumLength
        )
        let maximumIndex = normalizedSelection.index(
            normalizedSelection.startIndex,
            offsetBy: maximumLength
        )

        var index = maximumIndex
        while index >= minimumIndex {
            let candidate = String(normalizedSelection[..<index])
            if let range = normalizedText.range(of: candidate) {
                return range
            }
            if index == minimumIndex { break }
            index = normalizedSelection.index(before: index)
        }

        return nil
    }

    static func normalizedSearchText(_ text: String) -> String {
        normalizedSearchTextWithMap(text).text
    }

    private static func normalizedSearchTextWithMap(_ text: String) -> (text: String, map: [Range<String.Index>]) {
        var normalized = ""
        var map: [Range<String.Index>] = []
        var index = text.startIndex

        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]
            if let normalizedCharacter = normalizedSearchCharacter(character) {
                normalized.append(normalizedCharacter)
                map.append(index ..< next)
            }
            index = next
        }

        return (normalized, map)
    }

    private static func normalizedSearchCharacter(_ character: Character) -> Character? {
        if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return nil
        }

        switch character {
        case "“", "”", "„", "‟", "＂":
            return "\""
        case "‘", "’", "‚", "‛", "＇":
            return "'"
        default:
            return Character(String(character).lowercased())
        }
    }
}

private extension String {
    func prefixCharacters(_ limit: Int) -> String {
        guard limit > 0 else { return "" }
        return String(prefix(limit))
    }

    func suffixCharacters(_ limit: Int) -> String {
        guard limit > 0 else { return "" }
        return String(suffix(limit))
    }
}
