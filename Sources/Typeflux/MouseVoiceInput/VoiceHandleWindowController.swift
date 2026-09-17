import AppKit
import Combine
import Foundation

@MainActor
final class VoiceHandleWindowController {
    private static let handleSize = CGSize(width: 38, height: 38)

    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?
    var onLockRequested: (() -> Void)?
    var onCancelRequested: (() -> Void)?

    private let appState: AppStateStore
    private let panel: NSPanel
    private let handleView: VoiceHandleView
    private var statusCancellable: AnyCancellable?
    private(set) var isPresented = false

    init(appState: AppStateStore) {
        self.appState = appState
        handleView = VoiceHandleView(frame: CGRect(origin: .zero, size: Self.handleSize))
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.handleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = handleView

        handleView.onPressBegan = { [weak self] in self?.onPressBegan?() }
        handleView.onPressEnded = { [weak self] in self?.onPressEnded?() }
        handleView.onLockRequested = { [weak self] in self?.onLockRequested?() }
        handleView.onCancelRequested = { [weak self] in self?.onCancelRequested?() }

        statusCancellable = appState.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handleView.status = status
            }
    }

    func show(targetFrame: CGRect?, near point: CGPoint) {
        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = MouseVoiceHandlePlacement.origin(
            targetFrame: targetFrame,
            fallbackPoint: point,
            handleSize: Self.handleSize,
            visibleFrame: visibleFrame
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        isPresented = true
    }

    func hide() {
        panel.orderOut(nil)
        isPresented = false
    }
}

private final class VoiceHandleView: NSView {
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?
    var onLockRequested: (() -> Void)?
    var onCancelRequested: (() -> Void)?

    var status: AppStatus = .idle {
        didSet { updateAppearance() }
    }

    private let materialView = NSVisualEffectView()
    private let imageView = NSImageView()
    private var pressOrigin: CGPoint?
    private var gestureCommitted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = frameRect.height / 2
        layer?.cornerCurve = .continuous

        materialView.frame = bounds
        materialView.autoresizingMask = [.width, .height]
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = frameRect.height / 2
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        addSubview(materialView)

        imageView.frame = bounds.insetBy(dx: 10, dy: 10)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .white
        addSubview(imageView)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = convert(event.locationInWindow, from: nil)
        gestureCommitted = false
        animatePressed(true)
        onPressBegan?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !gestureCommitted, let pressOrigin else { return }
        let current = convert(event.locationInWindow, from: nil)
        let deltaX = current.x - pressOrigin.x
        let deltaY = current.y - pressOrigin.y
        if deltaY >= 44, abs(deltaY) > abs(deltaX) {
            gestureCommitted = true
            onLockRequested?()
            animatePressed(false)
        } else if deltaX <= -44, abs(deltaX) > abs(deltaY) {
            gestureCommitted = true
            onCancelRequested?()
            animatePressed(false)
        }
    }

    override func mouseUp(with _: NSEvent) {
        animatePressed(false)
        if !gestureCommitted {
            onPressEnded?()
        }
        pressOrigin = nil
        gestureCommitted = false
    }

    private func updateAppearance() {
        let isRecording = status == .recording
        imageView.image = NSImage(
            systemSymbolName: isRecording ? "stop.fill" : "mic.fill",
            accessibilityDescription: isRecording
                ? L("mouseVoice.handle.stop")
                : L("mouseVoice.handle.start")
        )
        materialView.layer?.backgroundColor = (
            isRecording ? NSColor.systemRed : NSColor.controlAccentColor
        ).withAlphaComponent(0.9).cgColor
        toolTip = isRecording ? L("mouseVoice.handle.stop") : L("mouseVoice.handle.start")
    }

    private func animatePressed(_ pressed: Bool) {
        let scale: CGFloat = pressed ? 0.92 : 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
}
