import AppKit
import Foundation

@MainActor
final class VoiceHandleWindowController {
    private static let proximityRadius: CGFloat = 36

    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?

    private let panel: NSPanel
    private let handleView: VoiceHandleView
    private var presentationGeneration = 0
    private(set) var isPresented = false

    init() {
        handleView = VoiceHandleView(
            frame: CGRect(origin: .zero, size: MouseVoiceHandleGeometry.canvasSize)
        )
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: MouseVoiceHandleGeometry.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
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
            handleSize: MouseVoiceHandleGeometry.canvasSize,
            visibleFrame: visibleFrame
        )
        panel.setFrameOrigin(origin)
        handleView.prepareForPresentation(activationStyle: activationStyle)
        panel.orderFrontRegardless()
        isPresented = true
    }

    func contains(_ point: CGPoint) -> Bool {
        guard isPresented else { return false }
        return interactiveFrame.insetBy(dx: -2, dy: -2).contains(point)
    }

    func updatePointer(at point: CGPoint) {
        guard isPresented else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let delta = CGVector(dx: point.x - center.x, dy: point.y - center.y)
        let distance = hypot(delta.dx, delta.dy)
        let fullStrengthDistance = interactiveFrame.width / 2
        let proximity = min(
            max((Self.proximityRadius - distance) / (Self.proximityRadius - fullStrengthDistance), 0),
            1
        )
        let direction: CGVector = if distance > 0 {
            CGVector(dx: delta.dx / distance, dy: delta.dy / distance)
        } else {
            .zero
        }
        handleView.setProximity(proximity, direction: direction)
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

    func resetProgress(animated: Bool) {
        handleView.resetProgress(animated: animated)
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

    private var interactiveFrame: CGRect {
        panel.frame.insetBy(
            dx: MouseVoiceHandleGeometry.interactionInset,
            dy: MouseVoiceHandleGeometry.interactionInset
        )
    }
}
