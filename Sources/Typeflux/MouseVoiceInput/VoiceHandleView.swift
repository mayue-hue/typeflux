import AppKit

final class VoiceHandleView: NSView {
    private enum Metrics {
        static let interactionInset = MouseVoiceHandleGeometry.interactionInset
        static let buttonInset = (
            MouseVoiceHandleGeometry.canvasSize.width - MouseVoiceHandleGeometry.buttonSize
        ) / 2
        static let ringInset = (
            MouseVoiceHandleGeometry.canvasSize.width - MouseVoiceHandleGeometry.ringDiameter
        ) / 2
        static let iconInset = (
            MouseVoiceHandleGeometry.canvasSize.width - MouseVoiceHandleGeometry.iconSize
        ) / 2
    }

    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?

    private let visualContainer = NSView()
    private let materialView = NSVisualEffectView()
    private let imageView = NSImageView()
    private let glowLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let completedRingLayer = CAShapeLayer()
    private let rippleLayer = CAShapeLayer()
    private var trackingAreaReference: NSTrackingArea?
    private var activationStyle: MouseVoiceActivationStyle = .dragRelease
    private var proximity: CGFloat = 0
    private var pointerDirection: CGVector = .zero
    private var progress: CGFloat = 0
    private var isArmed = false
    private var isPressed = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureVisualContainer()
        configureGlow()
        configureButton()
        configureIcon()
        configureProgressRing()
        configureCompletedRing()
        configureRipple()
        updateLayerPaths()
        updateVisuals(animateTransform: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateLayerPaths()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        interactiveBounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: interactiveBounds,
            options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
        setProximity(1, direction: pointerDirection)
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
        proximity = 0
        pointerDirection = .zero
        progress = 0
        isArmed = false
        isPressed = false
        resetProgress(animated: false)
        updateBackground(committed: false)
        updateEnergy()
        toolTip = activationStyle.displayName
        alphaValue = 0
        visualContainer.layer?.setAffineTransform(
            reduceMotion ? .identity : CGAffineTransform(scaleX: 0.88, y: 0.88)
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            visualContainer.animator().layer?.setAffineTransform(.identity)
        }
    }

    func setProximity(_ proximity: CGFloat, direction: CGVector) {
        self.proximity = min(max(proximity, 0), 1)
        pointerDirection = direction
        updateBackground(committed: false)
        updateEnergy()
        updateVisuals(animateTransform: false)
    }

    func setArmed(_ armed: Bool) {
        guard isArmed != armed else { return }
        isArmed = armed
        if activationStyle != .hoverDwell {
            setProgress(armed ? 1 : 0)
        }
        updateBackground(committed: false)
        updateVisuals(animateTransform: true)
    }

    func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed
        updateVisuals(animateTransform: true)
    }

    func setProgress(_ progress: CGFloat) {
        self.progress = min(max(progress, 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = self.progress
        progressLayer.opacity = self.progress < 1 ? 1 : 0
        completedRingLayer.opacity = self.progress < 1 ? 0 : 1
        CATransaction.commit()
        updateBackground(committed: false)
        updateEnergy()
        updateVisuals(animateTransform: false)
    }

    func resetProgress(animated: Bool) {
        let visibleProgress = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
        progress = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = 0
        progressLayer.opacity = 1
        completedRingLayer.opacity = 0
        CATransaction.commit()
        if animated, visibleProgress > 0 {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = visibleProgress
            animation.toValue = 0
            animation.duration = 0.12
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressLayer.add(animation, forKey: "progressReturn")
        }
        updateBackground(committed: false)
        updateEnergy(animated: animated)
        updateVisuals(animateTransform: animated)
    }

    func showCommitted() {
        isPressed = false
        isArmed = true
        proximity = 1
        setProgress(1)
        updateBackground(committed: true)
        performCommitAnimation()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

private extension VoiceHandleView {
    var interactiveBounds: CGRect {
        bounds.insetBy(dx: Metrics.interactionInset, dy: Metrics.interactionInset)
    }

    func configureVisualContainer() {
        visualContainer.frame = bounds
        visualContainer.autoresizingMask = [.width, .height]
        visualContainer.wantsLayer = true
        addSubview(visualContainer)
    }

    func configureGlow() {
        glowLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        glowLayer.shadowColor = NSColor.controlAccentColor.cgColor
        glowLayer.shadowRadius = 7.5
        glowLayer.shadowOpacity = 0.2
        glowLayer.shadowOffset = .zero
        visualContainer.layer?.addSublayer(glowLayer)
    }

    func configureButton() {
        materialView.frame = bounds.insetBy(dx: Metrics.buttonInset, dy: Metrics.buttonInset)
        materialView.autoresizingMask = [.width, .height]
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = materialView.frame.height / 2
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        visualContainer.addSubview(materialView)
    }

    func configureIcon() {
        imageView.frame = bounds.insetBy(dx: Metrics.iconInset, dy: Metrics.iconInset)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .white
        imageView.image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: L("mouseVoice.handle.start")
        )
        visualContainer.addSubview(imageView)
    }

    func configureProgressRing() {
        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.strokeColor = NSColor.white.withAlphaComponent(0.96).cgColor
        progressLayer.lineWidth = 2.25
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0
        progressLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        visualContainer.layer?.addSublayer(progressLayer)
    }

    func configureCompletedRing() {
        completedRingLayer.fillColor = NSColor.clear.cgColor
        completedRingLayer.strokeColor = NSColor.white.withAlphaComponent(0.96).cgColor
        completedRingLayer.lineWidth = 2.25
        completedRingLayer.opacity = 0
        visualContainer.layer?.addSublayer(completedRingLayer)
    }

    func configureRipple() {
        rippleLayer.fillColor = NSColor.clear.cgColor
        rippleLayer.strokeColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
        rippleLayer.lineWidth = 1.5
        rippleLayer.opacity = 0
        layer?.addSublayer(rippleLayer)
    }

    func updateLayerPaths() {
        let ringBounds = bounds.insetBy(dx: Metrics.ringInset, dy: Metrics.ringInset)
        progressLayer.frame = bounds
        progressLayer.path = CGPath(ellipseIn: ringBounds, transform: nil)
        completedRingLayer.frame = bounds
        completedRingLayer.path = CGPath(ellipseIn: ringBounds, transform: nil)
        glowLayer.frame = bounds
        glowLayer.path = CGPath(
            ellipseIn: bounds.insetBy(dx: Metrics.buttonInset, dy: Metrics.buttonInset),
            transform: nil
        )
        rippleLayer.frame = bounds
        rippleLayer.path = CGPath(
            ellipseIn: bounds.insetBy(dx: Metrics.buttonInset, dy: Metrics.buttonInset),
            transform: nil
        )
    }

    func updateVisuals(animateTransform: Bool) {
        let targetTransform = currentTransform()
        guard animateTransform, !reduceMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            visualContainer.layer?.transform = targetTransform
            CATransaction.commit()
            return
        }

        let layer = visualContainer.layer
        let currentTransform = layer?.presentation()?.transform ?? layer?.transform ?? CATransform3DIdentity
        layer?.transform = targetTransform
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: currentTransform)
        spring.toValue = NSValue(caTransform3D: targetTransform)
        spring.mass = 1
        spring.stiffness = 420
        spring.damping = activationStyle == .dragRelease ? 25 : 30
        spring.initialVelocity = 0
        spring.duration = min(spring.settlingDuration, 0.28)
        layer?.add(spring, forKey: "interactionTransform")
    }

    func currentTransform() -> CATransform3D {
        guard !reduceMotion else { return CATransform3DIdentity }
        let magneticScale = 0.045 * proximity
        let progressScale = activationStyle == .hoverDwell ? 0.025 * progress : 0
        let stateScale: CGFloat = if isPressed {
            -0.06
        } else if isArmed {
            0.035
        } else {
            0
        }
        let scale = 1 + magneticScale + progressScale + stateScale
        let offset = MouseVoiceHandleGeometry.maximumMagneticOffset * proximity
        var transform = CATransform3DMakeTranslation(
            pointerDirection.dx * offset,
            pointerDirection.dy * offset,
            0
        )
        transform = CATransform3DScale(transform, scale, scale, 1)
        return transform
    }

    func updateEnergy(animated: Bool = false) {
        let changes = {
            let energy = max(self.proximity * 0.45, self.progress)
            self.glowLayer.opacity = Float(0.18 + energy * 0.5)
            self.glowLayer.shadowOpacity = Float(0.18 + energy * 0.42)
            self.glowLayer.shadowRadius = 6 + energy * 6
            self.progressLayer.lineWidth = 2.25 + self.progress * 0.9
            self.completedRingLayer.lineWidth = 2.25 + self.progress * 0.9
            self.imageView.layer?.setAffineTransform(
                CGAffineTransform(scaleX: 1 + self.progress * 0.08, y: 1 + self.progress * 0.08)
            )
        }
        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            changes()
            CATransaction.commit()
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        changes()
        CATransaction.commit()
    }

    func updateBackground(committed: Bool) {
        let color: NSColor = if committed {
            .systemRed.withAlphaComponent(0.96)
        } else if isArmed {
            .controlAccentColor.withAlphaComponent(0.97)
        } else {
            .controlAccentColor.withAlphaComponent(0.78 + max(proximity, progress) * 0.14)
        }
        materialView.layer?.backgroundColor = color.cgColor
    }

    func performCommitAnimation() {
        guard !reduceMotion else { return }
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 0.94, 1.12, 1]
        pulse.keyTimes = [0, 0.18, 0.62, 1]
        pulse.duration = MouseVoiceLongPressPolicy.commitFeedbackDuration
        pulse.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
        visualContainer.layer?.add(pulse, forKey: "commitPulse")

        rippleLayer.opacity = 0
        let rippleScale = CABasicAnimation(keyPath: "transform.scale")
        rippleScale.fromValue = 1
        rippleScale.toValue = 1.35
        rippleScale.duration = MouseVoiceLongPressPolicy.commitFeedbackDuration
        rippleScale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let rippleOpacity = CABasicAnimation(keyPath: "opacity")
        rippleOpacity.fromValue = 0.8
        rippleOpacity.toValue = 0
        rippleOpacity.duration = MouseVoiceLongPressPolicy.commitFeedbackDuration
        let rippleGroup = CAAnimationGroup()
        rippleGroup.animations = [rippleScale, rippleOpacity]
        rippleGroup.duration = MouseVoiceLongPressPolicy.commitFeedbackDuration
        rippleLayer.add(rippleGroup, forKey: "commitRipple")
    }
}
