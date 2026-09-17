import Foundation

extension WorkflowController {
    struct DictationPersonaSnapshot {
        let persona: PersonaProfile?
        let prompt: String?
    }

    func promoteRecordingToAuxiliary(context: HotkeyEventContext) {
        guard isRecording, recordingIntent == .dictation,
              let decision = recordingGestureDecision else { return }
        recordingUsesAuxiliary = true
        recordingPersonaSnapshot = nil
        if settingsStore.auxiliaryHotkey?.pressCount == 2 {
            recordingMode = .locked
            hotkeyPressedAt = nil
        } else {
            hotkeyPressedAt = context.uptime
        }
        decision.resolve()
    }

    func snapshotRecordingPersona(appName: String?, bundleIdentifier: String?) {
        guard recordingPersonaSnapshot == nil else { return }
        let persona = recordingUsesAuxiliary ? settingsStore.auxiliaryPersona
            : settingsStore.effectivePersona(appName: appName, bundleIdentifier: bundleIdentifier)
        recordingPersonaSnapshot = DictationPersonaSnapshot(
            persona: persona,
            prompt: persona.map { settingsStore.resolvedPersonaPrompt(for: $0) }
        )
    }

    func recordingPersona(appName: String?, bundleIdentifier: String?) -> PersonaProfile? {
        if let recordingPersonaSnapshot { return recordingPersonaSnapshot.persona }
        return recordingUsesAuxiliary ? settingsStore.auxiliaryPersona
            : settingsStore.effectivePersona(appName: appName, bundleIdentifier: bundleIdentifier)
    }

}
