import AppKit
import Foundation

@MainActor
final class VoiceHandleWindowController {
    private static let handleSize = CGSize(width: 42, height: 42)

    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?

    private let panel: NSPanel
    private let handleView: VoiceHandleView
    private var presentationGeneration = 0
    private(set) var isPresented = false

    init() {
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
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = handleView

        handleView.onPointerEntered = { [weak self] in self?.onPointerEntered?() }
        handleView.onPointerExited = { [weak self] in self?.onPointerExited?() }
        handleView.onPressBegan = { [weak self] in self?.onPressBegan?() }
        handleView.onPressEnded = { [weak self] in self?.onPressEnded?() }
    }

    func show(near point: CGPoint, activationStyle: MouseVoiceActivationStyle) {
        presentationGeneration += 1
        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = MouseVoiceHandlePlacement.origin(
            near: point,
            handleSize: Self.handleSize,
            visibleFrame: visibleFrame
        )
        panel.setFrameOrigin(origin)
        handleView.prepareForPresentation(activationStyle: activationStyle)
        panel.orderFrontRegardless()
        isPresented = true
    }

    func contains(_ point: CGPoint) -> Bool {
        isPresented && MouseVoiceHandlePlacement.contains(point, handleFrame: panel.frame)
    }

    func setArmed(_ armed: Bool) {
        handleView.setArmed(armed)
    }

    func setPressed(_ pressed: Bool) {
        handleView.setPressed(pressed)
    }

    func setProgress(_ progress: CGFloat) {
        handleView.setProgress(progress)
    }

    func showCommitted() {
        handleView.showCommitted()
    }

    func hide(after delay: TimeInterval) {
        let generation = presentationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, presentationGeneration == generation else { return }
            hide()
        }
    }

    func hide() {
        presentationGeneration += 1
        panel.orderOut(nil)
        isPresented = false
    }
}

private final class VoiceHandleView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?

    private let materialView = NSVisualEffectView()
    private let imageView = NSImageView()
    private let progressLayer = CAShapeLayer()
    private var trackingAreaReference: NSTrackingArea?
    private var activationStyle: MouseVoiceActivationStyle = .dragRelease
    private var isArmed = false
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        materialView.frame = bounds.insetBy(dx: 2, dy: 2)
        materialView.autoresizingMask = [.width, .height]
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = materialView.frame.height / 2
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        addSubview(materialView)

        imageView.frame = bounds.insetBy(dx: 12, dy: 12)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .white
        imageView.image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: L("mouseVoice.handle.start")
        )
        addSubview(imageView)

        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        progressLayer.lineWidth = 2.5
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0
        progressLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        layer?.addSublayer(progressLayer)
        updateProgressPath()
        updateBackground(committed: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateProgressPath()
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with _: NSEvent) {
        onPointerExited?()
    }

    override func mouseDown(with _: NSEvent) {
        onPressBegan?()
    }

    override func mouseUp(with _: NSEvent) {
        onPressEnded?()
    }

    func prepareForPresentation(activationStyle: MouseVoiceActivationStyle) {
        self.activationStyle = activationStyle
        isArmed = false
        isPressed = false
        setProgress(0)
        updateBackground(committed: false)
        toolTip = activationStyle.displayName
        alphaValue = 0
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.86, y: 0.86))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().layer?.setAffineTransform(.identity)
        }
    }

    func setArmed(_ armed: Bool) {
        guard isArmed != armed else { return }
        isArmed = armed
        if activationStyle != .hoverDwell {
            setProgress(armed ? 1 : 0)
        }
        updateBackground(committed: false)
        animateScale()
    }

    func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed
        animateScale()
    }

    func setProgress(_ progress: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = min(max(progress, 0), 1)
        CATransaction.commit()
    }

    func showCommitted() {
        isPressed = false
        isArmed = true
        setProgress(1)
        updateBackground(committed: true)
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.92, y: 0.92))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().layer?.setAffineTransform(CGAffineTransform(scaleX: 1.12, y: 1.12))
        }
    }

    private func updateProgressPath() {
        progressLayer.frame = bounds
        progressLayer.path = CGPath(
            ellipseIn: bounds.insetBy(dx: 2.25, dy: 2.25),
            transform: nil
        )
    }

    private func updateBackground(committed: Bool) {
        let color: NSColor = if committed {
            .systemRed.withAlphaComponent(0.96)
        } else if isArmed {
            .controlAccentColor.withAlphaComponent(0.96)
        } else {
            .controlAccentColor.withAlphaComponent(0.78)
        }
        materialView.layer?.backgroundColor = color.cgColor
    }

    private func animateScale() {
        let scale: CGFloat = if isPressed {
            0.94
        } else if isArmed {
            1.08
        } else {
            1
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
}
