import AppKit
import Foundation

@MainActor
final class MouseVoiceInputController {
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?
    var onLockRequested: (() -> Void)?
    var onCancelRequested: (() -> Void)?

    private let settingsStore: SettingsStore
    private let targetResolver: MouseVoiceTargetResolver
    private let handleController: VoiceHandleWindowController

    private var globalMonitor: Any?
    private var settingsObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var pendingLongPress: DispatchWorkItem?
    private var mouseDownLocation: CGPoint?
    private var longPressRecordingActive = false

    init(
        settingsStore: SettingsStore,
        appState: AppStateStore,
        targetResolver: MouseVoiceTargetResolver
    ) {
        self.settingsStore = settingsStore
        self.targetResolver = targetResolver
        handleController = VoiceHandleWindowController(appState: appState)
        handleController.onPressBegan = { [weak self] in self?.onPressBegan?() }
        handleController.onPressEnded = { [weak self] in self?.onPressEnded?() }
        handleController.onLockRequested = { [weak self] in self?.onLockRequested?() }
        handleController.onCancelRequested = { [weak self] in self?.onCancelRequested?() }
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
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
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
            Task { @MainActor [weak self] in
                self?.cancelPendingLongPress()
                self?.handleController.hide()
            }
        }
    }

    func stop() {
        stopMonitoring()
        handleController.hide()
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
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            handleMouseDown(at: NSEvent.mouseLocation)
        case .leftMouseDragged:
            handleMouseDragged(to: NSEvent.mouseLocation)
        case .leftMouseUp:
            handleMouseUp(at: NSEvent.mouseLocation)
        default:
            break
        }
    }

    private func handleMouseDown(at location: CGPoint) {
        mouseDownLocation = location
        if handleController.isPresented {
            handleController.hide()
        }
        guard settingsStore.mouseLongPressVoiceInputEnabled else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let mouseDownLocation else { return }
            guard pendingLongPress?.isCancelled == false else { return }
            guard targetResolver.target(at: mouseDownLocation) != nil else { return }
            longPressRecordingActive = true
            onPressBegan?()
        }
        pendingLongPress = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MouseVoiceLongPressPolicy.activationDelay,
            execute: workItem
        )
    }

    private func handleMouseDragged(to location: CGPoint) {
        guard let mouseDownLocation else { return }
        if MouseVoiceLongPressPolicy.exceedsMovementTolerance(from: mouseDownLocation, to: location),
           !longPressRecordingActive {
            cancelPendingLongPress()
        }
    }

    private func handleMouseUp(at location: CGPoint) {
        cancelPendingLongPress()
        mouseDownLocation = nil
        if longPressRecordingActive {
            longPressRecordingActive = false
            onPressEnded?()
            return
        }

        guard settingsStore.smartVoiceHandleEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.refreshHandle(near: location)
        }
    }

    private func refreshHandle(near location: CGPoint) {
        guard settingsStore.smartVoiceHandleEnabled,
              let target = targetResolver.target(at: location) else {
            handleController.hide()
            return
        }
        handleController.show(targetFrame: target.frame, near: location)
    }

    private func cancelPendingLongPress() {
        pendingLongPress?.cancel()
        pendingLongPress = nil
    }

    private func settingsDidChange() {
        if !settingsStore.smartVoiceHandleEnabled {
            handleController.hide()
        }
        if !settingsStore.mouseLongPressVoiceInputEnabled {
            cancelPendingLongPress()
        }
    }
}
