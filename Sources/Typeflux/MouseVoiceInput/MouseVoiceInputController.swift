import AppKit
import Foundation

@MainActor
final class MouseVoiceInputController {
    var onRecordingRequested: (() -> Void)?

    private let settingsStore: SettingsStore
    private let targetResolver: MouseVoiceTargetResolver
    private let handleController: VoiceHandleWindowController

    private var globalMonitor: Any?
    private var settingsObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var pendingLongPress: DispatchWorkItem?
    private var pendingDismissal: DispatchWorkItem?
    private var mouseDownLocation: CGPoint?
    private var candidateTarget: MouseVoiceTarget?
    private var handleTarget: MouseVoiceTarget?
    private var selectionToRestoreOnMouseUp: MouseVoiceTarget?

    init(
        settingsStore: SettingsStore,
        targetResolver: MouseVoiceTargetResolver
    ) {
        self.settingsStore = settingsStore
        self.targetResolver = targetResolver
        handleController = VoiceHandleWindowController()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func start() {
        stopMonitoring()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved]
        ) { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event) }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .mouseVoiceInputDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.settingsDidChange() }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resetInteraction() }
        }
    }

    func stop() {
        stopMonitoring()
        resetInteraction()
    }

    private func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        globalMonitor = nil
        settingsObserver = nil
        workspaceObserver = nil
        cancelPendingLongPress()
        cancelPendingDismissal()
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            handleMouseDown(at: location)
        case .leftMouseDragged:
            handleMouseDragged(to: location)
        case .leftMouseUp:
            handleMouseUp(at: location)
        case .mouseMoved:
            activateHandleIfNeeded(at: location)
        default:
            break
        }
    }

    private func handleMouseDown(at location: CGPoint) {
        if handleController.contains(location) {
            activateHandleIfNeeded(at: location)
            return
        }
        resetInteraction()
        guard settingsStore.mouseVoiceInputEnabled,
              let target = targetResolver.target(at: location),
              !target.hasSelectedText else {
            return
        }

        mouseDownLocation = location
        candidateTarget = target
        let workItem = DispatchWorkItem { [weak self] in
            self?.revealHandleIfStillEligible()
        }
        pendingLongPress = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MouseVoiceLongPressPolicy.activationDelay,
            execute: workItem
        )
    }

    private func handleMouseDragged(to location: CGPoint) {
        if handleController.isPresented {
            activateHandleIfNeeded(at: location)
            return
        }
        guard let mouseDownLocation,
              MouseVoiceLongPressPolicy.exceedsMovementTolerance(
                  from: mouseDownLocation,
                  to: location
              ) else {
            return
        }
        // Movement before the long-press threshold is treated as text selection.
        cancelPendingLongPress()
        candidateTarget = nil
    }

    private func handleMouseUp(at location: CGPoint) {
        cancelPendingLongPress()
        candidateTarget = nil
        mouseDownLocation = nil

        if let target = selectionToRestoreOnMouseUp {
            selectionToRestoreOnMouseUp = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.targetResolver.restoreSelection(for: target)
            }
        }

        if handleController.isPresented {
            if handleController.contains(location) {
                activateHandleIfNeeded(at: location)
            } else {
                scheduleHandleDismissal()
            }
        }
    }

    private func revealHandleIfStillEligible() {
        guard settingsStore.mouseVoiceInputEnabled,
              let location = mouseDownLocation,
              let originalTarget = candidateTarget,
              pendingLongPress?.isCancelled == false,
              let currentTarget = targetResolver.target(at: location),
              currentTarget.processID == originalTarget.processID,
              !currentTarget.hasSelectedText else {
            resetInteraction()
            return
        }

        cancelPendingLongPress()
        candidateTarget = nil
        handleTarget = originalTarget
        handleController.show(near: location)
    }

    private func activateHandleIfNeeded(at location: CGPoint) {
        guard handleController.contains(location), let target = handleTarget else { return }
        cancelPendingDismissal()
        handleController.hide()
        handleTarget = nil

        // Dragging from an editor can temporarily create a selection. Restore the insertion
        // point before the workflow snapshots context, and once more after mouse-up.
        targetResolver.restoreSelection(for: target)
        if mouseDownLocation != nil {
            selectionToRestoreOnMouseUp = target
        }
        onRecordingRequested?()
    }

    private func scheduleHandleDismissal() {
        cancelPendingDismissal()
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleController.hide()
            self?.handleTarget = nil
        }
        pendingDismissal = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MouseVoiceLongPressPolicy.hoverTimeout,
            execute: workItem
        )
    }

    private func cancelPendingLongPress() {
        pendingLongPress?.cancel()
        pendingLongPress = nil
    }

    private func cancelPendingDismissal() {
        pendingDismissal?.cancel()
        pendingDismissal = nil
    }

    private func resetInteraction() {
        cancelPendingLongPress()
        cancelPendingDismissal()
        mouseDownLocation = nil
        candidateTarget = nil
        handleTarget = nil
        selectionToRestoreOnMouseUp = nil
        handleController.hide()
    }

    private func settingsDidChange() {
        if !settingsStore.mouseVoiceInputEnabled {
            resetInteraction()
        }
    }
}
