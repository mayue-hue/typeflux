import Foundation

extension WorkflowController {
    private static let historyPickerLimit = 20

    func handleHistoryPickerRequested() {
        if isHistoryPickerPresented {
            dismissHistoryPicker(immediate: true)
            return
        }

        if isPersonaPickerPresented {
            dismissPersonaPicker()
        }

        guard !isRecording, processingTask == nil else { return }

        let entries = historyPickerEntries()
        guard !entries.isEmpty else {
            overlayController.showNotice(message: L("overlay.historyPicker.empty"))
            overlayController.dismiss(after: 2.0)
            return
        }

        historyPickerItems = entries
        historyPickerSelectedIndex = 0
        isHistoryPickerPresented = true
        overlayController.showPersonaPicker(
            items: entries.map {
                OverlayController.PersonaPickerItem(
                    id: $0.id.uuidString,
                    title: $0.title,
                    subtitle: $0.subtitle
                )
            },
            selectedIndex: 0,
            title: L("overlay.historyPicker.title"),
            instructions: L("overlay.historyPicker.instructions"),
            icon: .none,
            style: .history
        )
    }

    func historyPickerEntries() -> [HistoryPickerEntry] {
        StatusBarMenuSupport.recentTranscriptionRecords(
            from: historyStore.list(limit: Self.historyPickerLimit * 3, offset: 0, searchQuery: nil),
            limit: Self.historyPickerLimit
        )
        .compactMap { record in
            guard let text = record.finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }

            return HistoryPickerEntry(
                id: record.id,
                title: StatusBarMenuSupport.recentHistoryTitle(for: record),
                subtitle: Self.historyPickerSubtitle(for: record.date),
                text: text,
                record: record
            )
        }
    }

    func moveHistorySelection(delta: Int) {
        guard isHistoryPickerPresented, !historyPickerItems.isEmpty else { return }
        let maxIndex = historyPickerItems.count - 1
        historyPickerSelectedIndex = max(0, min(maxIndex, historyPickerSelectedIndex + delta))
        Task { @MainActor in
            self.overlayController.updatePersonaPickerSelection(self.historyPickerSelectedIndex)
        }
    }

    func confirmHistorySelection() {
        guard isHistoryPickerPresented,
              historyPickerItems.indices.contains(historyPickerSelectedIndex)
        else { return }

        insertHistorySelection(at: historyPickerSelectedIndex)
    }

    func copyHistorySelection(at index: Int) {
        guard isHistoryPickerPresented,
              historyPickerItems.indices.contains(index)
        else { return }

        let selected = historyPickerItems[index]
        clipboard.write(text: selected.text)
        soundEffectPlayer.playAsync(.tip)
        dismissHistoryPicker(immediate: true)
    }

    func insertHistorySelection(at index: Int) {
        guard isHistoryPickerPresented,
              historyPickerItems.indices.contains(index)
        else { return }

        let selected = historyPickerItems[index]
        soundEffectPlayer.playAsync(.tip)
        dismissHistoryPicker(immediate: true)
        clipboard.write(text: selected.text)
        Task {
            _ = await applyText(
                selected.text,
                replace: false,
                fallbackTitle: L("overlay.historyPicker.pasteFallbackTitle")
            )
        }
    }

    func retryHistorySelection(at index: Int) {
        guard isHistoryPickerPresented,
              historyPickerItems.indices.contains(index)
        else { return }

        let selected = historyPickerItems[index]
        soundEffectPlayer.playAsync(.tip)
        dismissHistoryPicker(immediate: true)
        retry(record: selected.record)
    }

    func selectHistorySelection(at index: Int) {
        guard isHistoryPickerPresented, historyPickerItems.indices.contains(index) else { return }
        historyPickerSelectedIndex = index
        confirmHistorySelection()
    }

    func dismissHistoryPicker(closeOverlay: Bool = true, immediate: Bool = false) {
        guard isHistoryPickerPresented else { return }
        isHistoryPickerPresented = false
        historyPickerItems = []
        historyPickerSelectedIndex = 0
        guard closeOverlay else { return }
        if immediate {
            overlayController.dismissImmediately()
            return
        }
        Task { @MainActor in
            self.overlayController.dismiss(after: 0.05)
        }
    }

    private static func historyPickerSubtitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
