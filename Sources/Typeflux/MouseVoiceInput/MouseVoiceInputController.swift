import AppKit
import Foundation

enum MouseVoiceRecordingStartMode {
    case holdToTalk
    case locked
}

@MainActor
final class MouseVoiceInputController {
    var onRecordingRequested: ((MouseVoiceRecordingStartMode) -> Void)?
    var onRecordingReleaseRequested: (() -> Void)?
    var onRecordingStopRequested: (() -> Void)?
    var recordingStateProvider: (() -> Bool)?

    private let settingsStore: SettingsStore
    private let targetResolver: MouseVoiceTargetResolver
    private let handleController: VoiceHandleWindowController

    private var globalMonitor: Any?
    private var settingsObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var pendingLongPress: DispatchWorkItem?
    private var pendingDismissal: DispatchWorkItem?
    private var hoverTimer: Timer?
    private var recordingStateTimer: Timer?
    private var hoverStartedAt: TimeInterval?
    private var mouseDownLocation: CGPoint?
    private var candidateTarget: MouseVoiceTarget?
    private var handleTarget: MouseVoiceTarget?
    private var clickPending = false
    private var clickRecordingActive = false
    private var clickPressStopsActiveRecording = false
    private var pointerInsideHandle = false

    init(
        settingsStore: SettingsStore,
        targetResolver: MouseVoiceTargetResolver
    ) {
        self.settingsStore = settingsStore
        self.targetResolver = targetResolver
        handleController = VoiceHandleWindowController()
        handleController.onPointerEntered = { [weak self] in self?.handlePointerEntered() }
        handleController.onPointerExited = { [weak self] in self?.handlePointerExited() }
        handleController.onPressBegan = { [weak self] in self?.handleHandlePressBegan() }
        handleController.onPressEnded = { [weak self] in self?.handleHandlePressEnded() }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        hoverTimer?.invalidate()
        recordingStateTimer?.invalidate()
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
            Task { @MainActor [weak self] in self?.resetInteraction() }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.clickRecordingActive == false else { return }
                self?.resetInteraction()
            }
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
        cancelHoverProgress()
        cancelRecordingStateMonitoring()
    }
}

private extension MouseVoiceInputController {
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
            updatePointerPosition(location)
        default:
            break
        }
    }

    private func handleMouseDown(at location: CGPoint) {
        guard !clickRecordingActive else { return }
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
            updatePointerPosition(location)
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
        if clickRecordingActive, !clickPending {
            return
        }
        cancelPendingLongPress()
        candidateTarget = nil
        guard handleController.isPresented else {
            mouseDownLocation = nil
            return
        }

        let style = settingsStore.mouseVoiceActivationStyle
        let isInsideHandle = handleController.contains(location)
        if let target = handleTarget {
            targetResolver.restoreSelection(for: target)
        }
        mouseDownLocation = nil

        switch style {
        case .dragRelease:
            if isInsideHandle {
                triggerRecording()
            } else {
                resetInteraction()
            }
        case .hoverDwell:
            scheduleHandleDismissal()
            if isInsideHandle {
                pointerInsideHandle = false
                handlePointerEntered()
            }
        case .click:
            handleController.setArmed(isInsideHandle)
            scheduleHandleDismissal()
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
        handleController.show(
            near: location,
            activationStyle: settingsStore.mouseVoiceActivationStyle
        )
    }

    private func handlePointerEntered() {
        guard handleController.isPresented, !pointerInsideHandle else { return }
        pointerInsideHandle = true
        switch settingsStore.mouseVoiceActivationStyle {
        case .dragRelease:
            guard mouseDownLocation != nil else { return }
            handleController.setArmed(true)
        case .hoverDwell:
            guard mouseDownLocation == nil else { return }
            cancelPendingDismissal()
            handleController.setArmed(true)
            startHoverProgress()
        case .click:
            guard mouseDownLocation == nil else { return }
            cancelPendingDismissal()
            handleController.setArmed(true)
        }
    }

    private func handlePointerExited() {
        guard handleController.isPresented, pointerInsideHandle else { return }
        pointerInsideHandle = false
        if settingsStore.mouseVoiceActivationStyle == .click,
           clickRecordingActive || clickPending {
            return
        }
        clickPending = false
        cancelHoverProgress()
        handleController.setArmed(false)
        if mouseDownLocation == nil,
           settingsStore.mouseVoiceActivationStyle != .dragRelease {
            scheduleHandleDismissal()
        }
    }

    private func handleHandlePressBegan() {
        guard handleController.isPresented,
              mouseDownLocation == nil,
              settingsStore.mouseVoiceActivationStyle == .click else {
            return
        }
        cancelPendingDismissal()
        clickPending = true
        clickPressStopsActiveRecording = clickRecordingActive
        handleController.setPressed(true)
        if !clickRecordingActive {
            beginClickRecording()
        }
    }

    private func handleHandlePressEnded() {
        handleController.setPressed(false)
        guard clickPending,
              settingsStore.mouseVoiceActivationStyle == .click else {
            return
        }
        let shouldStop = clickPressStopsActiveRecording
        clickPending = false
        clickPressStopsActiveRecording = false
        if shouldStop {
            finishClickRecording()
        } else {
            onRecordingReleaseRequested?()
            handleController.setArmed(true)
        }
    }

    private func updatePointerPosition(_ location: CGPoint) {
        guard handleController.isPresented else { return }
        handleController.updatePointer(at: location)
        if handleController.contains(location) {
            handlePointerEntered()
        } else {
            handlePointerExited()
        }
    }

    private func startHoverProgress() {
        cancelHoverProgress(resetVisuals: false)
        hoverStartedAt = ProcessInfo.processInfo.systemUptime
        handleController.setProgress(0)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceHoverProgress() }
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceHoverProgress() {
        guard settingsStore.mouseVoiceActivationStyle == .hoverDwell,
              handleController.isPresented,
              mouseDownLocation == nil,
              let hoverStartedAt else {
            cancelHoverProgress()
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - hoverStartedAt
        let progress = min(elapsed / MouseVoiceLongPressPolicy.hoverActivationDelay, 1)
        handleController.setProgress(progress)
        if progress >= 1 {
            triggerRecording()
        }
    }

    private func triggerRecording() {
        guard let target = handleTarget else { return }
        cancelPendingLongPress()
        cancelPendingDismissal()
        cancelHoverProgress(resetVisuals: false)
        targetResolver.restoreSelection(for: target)
        handleTarget = nil
        mouseDownLocation = nil
        candidateTarget = nil
        clickPending = false
        handleController.showCommitted()
        onRecordingRequested?(.locked)
        handleController.hide(after: MouseVoiceLongPressPolicy.commitFeedbackDuration)
    }

    private func beginClickRecording() {
        guard let target = handleTarget else { return }
        cancelPendingLongPress()
        cancelPendingDismissal()
        cancelHoverProgress(resetVisuals: false)
        targetResolver.restoreSelection(for: target)
        handleTarget = nil
        mouseDownLocation = nil
        candidateTarget = nil
        clickRecordingActive = true
        handleController.showCommitted()
        onRecordingRequested?(.holdToTalk)
        startRecordingStateMonitoring()
    }

    private func finishClickRecording() {
        guard clickRecordingActive else { return }
        clickRecordingActive = false
        cancelRecordingStateMonitoring()
        onRecordingStopRequested?()
        handleController.showCommitted()
        handleController.hide(after: MouseVoiceLongPressPolicy.commitFeedbackDuration)
    }

    private func startRecordingStateMonitoring() {
        cancelRecordingStateMonitoring()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshClickRecordingState() }
        }
        recordingStateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshClickRecordingState() {
        guard clickRecordingActive else {
            cancelRecordingStateMonitoring()
            return
        }
        guard recordingStateProvider?() != false else {
            resetInteraction()
            return
        }
    }

    private func cancelRecordingStateMonitoring() {
        recordingStateTimer?.invalidate()
        recordingStateTimer = nil
    }

    private func scheduleHandleDismissal() {
        cancelPendingDismissal()
        let workItem = DispatchWorkItem { [weak self] in
            self?.resetInteraction()
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

    private func cancelHoverProgress(resetVisuals: Bool = true) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverStartedAt = nil
        if resetVisuals {
            handleController.resetProgress(animated: true)
        }
    }

    private func resetInteraction() {
        cancelPendingLongPress()
        cancelPendingDismissal()
        cancelHoverProgress(resetVisuals: false)
        mouseDownLocation = nil
        candidateTarget = nil
        handleTarget = nil
        clickPending = false
        clickRecordingActive = false
        clickPressStopsActiveRecording = false
        pointerInsideHandle = false
        cancelRecordingStateMonitoring()
        handleController.hide()
    }
}
