import AppKit
import ApplicationServices
import Foundation

struct MouseVoiceTarget {
    let element: AXUIElement
    let processID: pid_t
    let bundleIdentifier: String?
    let frame: CGRect?
}

protocol MouseVoiceTargetAdapting {
    func resolve(
        hitElement: AXUIElement?,
        focusedElement: AXUIElement?,
        bundleIdentifier: String?,
        injector: AXTextInjector
    ) -> AXUIElement?
}

/// Resolves writable controls through macOS Accessibility. App-specific adapters can be
/// inserted ahead of the generic fallback without coupling them to the mouse gesture code.
final class MouseVoiceTargetResolver {
    private let injector: AXTextInjector
    private let adapters: [MouseVoiceTargetAdapting]

    init(injector: AXTextInjector, adapters: [MouseVoiceTargetAdapting] = []) {
        self.injector = injector
        self.adapters = adapters
    }

    func target(at cocoaPoint: CGPoint? = nil) -> MouseVoiceTarget? {
        let hitCandidates = cocoaPoint.map(elementsAtCocoaPoint) ?? []
        let hitElement = hitCandidates.first(where: injector.isLikelyEditable(element:))
            ?? hitCandidates.first
        let hitProcessID = hitElement.flatMap(injector.processID(of:))
        let systemFocusedElement = hitProcessID == nil ? lightweightSystemFocusedElement() : nil
        let processID = hitProcessID
            ?? systemFocusedElement.flatMap(injector.processID(of:))
            ?? frontmostProcessID()
        guard let processID else { return nil }

        let focusedElement = systemFocusedElement ?? injector.focusedElement(for: processID)
        let bundleIdentifier = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier
        if bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }

        let adapted = adapters.lazy.compactMap { adapter in
            adapter.resolve(
                hitElement: hitElement,
                focusedElement: focusedElement,
                bundleIdentifier: bundleIdentifier,
                injector: self.injector
            )
        }.first

        guard let element = adapted ?? genericWritableElement(
            hitElement: hitElement,
            focusedElement: focusedElement
        ) else {
            return nil
        }

        return MouseVoiceTarget(
            element: element,
            processID: processID,
            bundleIdentifier: bundleIdentifier,
            frame: cocoaFrame(of: element)
        )
    }

    private func genericWritableElement(
        hitElement: AXUIElement?,
        focusedElement: AXUIElement?
    ) -> AXUIElement? {
        if let hitElement, injector.isLikelyEditable(element: hitElement) {
            return hitElement
        }
        if let focusedElement, injector.isLikelyEditable(element: focusedElement) {
            return focusedElement
        }
        for root in [focusedElement, hitElement].compactMap(\.self) {
            if let descendant = uniqueWritableDescendant(in: root) {
                return descendant
            }
        }
        return nil
    }

    /// Some native and custom editors expose only their focused window. Falling back to a
    /// descendant is safe only when the accessibility subtree contains exactly one writable
    /// control; ambiguous windows are left for an app-specific adapter.
    private func uniqueWritableDescendant(in root: AXUIElement) -> AXUIElement? {
        var pending = Array(injector.copyElementArrayAttribute(kAXChildrenAttribute as String, from: root).prefix(24))
        var index = 0
        var visited = 0
        var writable: AXUIElement?

        while index < pending.count, visited < 64 {
            let element = pending[index]
            index += 1
            visited += 1
            if injector.isLikelyEditable(element: element) {
                if let writable, !CFEqual(writable, element) {
                    return nil
                }
                writable = element
                continue
            }
            pending.append(
                contentsOf: injector.copyElementArrayAttribute(
                    kAXChildrenAttribute as String,
                    from: element
                ).prefix(24)
            )
        }
        return writable
    }

    private func elementsAtCocoaPoint(_ point: CGPoint) -> [AXUIElement] {
        let axPoint = MouseVoiceCoordinateConverter.accessibilityPoint(fromCocoaPoint: point)
        let points = axPoint == point ? [axPoint] : [axPoint, point]
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        return points.compactMap { candidate in
            var value: AXUIElement?
            guard AXUIElementCopyElementAtPosition(
                system,
                Float(candidate.x),
                Float(candidate.y),
                &value
            ) == .success else {
                return nil
            }
            return value
        }
    }

    private func lightweightSystemFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        guard let root = injector.copyElementAttribute(kAXFocusedUIElementAttribute as String, from: system)
        else {
            return nil
        }
        return injector.resolveFocusedElement(root)
    }

    private func cocoaFrame(of element: AXUIElement) -> CGRect? {
        guard let position = injector.copyCGPointAttribute(kAXPositionAttribute as String, from: element),
              let size = injector.copyCGSizeAttribute(kAXSizeAttribute as String, from: element),
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return MouseVoiceCoordinateConverter.cocoaFrame(
            fromAccessibilityPosition: position,
            size: size
        )
    }

    private func frontmostProcessID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

enum MouseVoiceCoordinateConverter {
    static func accessibilityPoint(
        fromCocoaPoint point: CGPoint,
        mainScreenMaxY: CGFloat = NSScreen.screens.first?.frame.maxY ?? 0
    ) -> CGPoint {
        CGPoint(x: point.x, y: mainScreenMaxY - point.y)
    }

    static func cocoaFrame(
        fromAccessibilityPosition position: CGPoint,
        size: CGSize,
        mainScreenMaxY: CGFloat = NSScreen.screens.first?.frame.maxY ?? 0
    ) -> CGRect {
        CGRect(
            x: position.x,
            y: mainScreenMaxY - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }
}

enum MouseVoiceHandlePlacement {
    static func origin(
        targetFrame: CGRect?,
        fallbackPoint: CGPoint,
        handleSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let spacing: CGFloat = 7
        var origin: CGPoint
        if let targetFrame {
            let outsideX = targetFrame.maxX + spacing
            let insideX = targetFrame.maxX - handleSize.width - spacing
            origin = CGPoint(
                x: outsideX + handleSize.width <= visibleFrame.maxX ? outsideX : insideX,
                y: targetFrame.minY + spacing
            )
        } else {
            origin = CGPoint(x: fallbackPoint.x + 12, y: fallbackPoint.y - handleSize.height - 12)
        }

        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX + spacing), visibleFrame.maxX - handleSize.width - spacing),
            y: min(max(origin.y, visibleFrame.minY + spacing), visibleFrame.maxY - handleSize.height - spacing)
        )
    }
}

enum MouseVoiceLongPressPolicy {
    static let activationDelay: TimeInterval = 0.8
    static let movementTolerance: CGFloat = 6

    static func exceedsMovementTolerance(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) > movementTolerance
    }
}
