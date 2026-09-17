import AppKit
import Foundation

@MainActor
final class VoiceHandleWindowController {
    private static let handleSize = CGSize(width: 38, height: 38)

    private let panel: NSPanel
    private let handleView: VoiceHandleView
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
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = handleView
    }

    func show(near point: CGPoint) {
        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = MouseVoiceHandlePlacement.origin(
            near: point,
            handleSize: Self.handleSize,
            visibleFrame: visibleFrame
        )
        panel.setFrameOrigin(origin)
        handleView.prepareForPresentation()
        panel.orderFrontRegardless()
        isPresented = true
    }

    func contains(_ point: CGPoint) -> Bool {
        isPresented && MouseVoiceHandlePlacement.contains(point, handleFrame: panel.frame)
    }

    func hide() {
        panel.orderOut(nil)
        isPresented = false
    }
}

private final class VoiceHandleView: NSView {
    private let materialView = NSVisualEffectView()
    private let imageView = NSImageView()

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
        imageView.image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: L("mouseVoice.handle.start")
        )
        materialView.layer?.backgroundColor = NSColor.controlAccentColor
            .withAlphaComponent(0.92).cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForPresentation() {
        alphaValue = 0
        layer?.setAffineTransform(CGAffineTransform(scaleX: 0.86, y: 0.86))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().layer?.setAffineTransform(.identity)
        }
    }
}
