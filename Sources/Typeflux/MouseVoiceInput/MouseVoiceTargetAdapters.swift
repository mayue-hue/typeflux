import ApplicationServices
import Foundation

struct KnownOpaqueMouseVoiceTargetAdapter: MouseVoiceTargetAdapting {
    func resolve(
        hitElement: AXUIElement?,
        focusedElement: AXUIElement?,
        bundleIdentifier: String?,
        injector: AXTextInjector
    ) -> AXUIElement? {
        guard MouseVoiceOpaqueTargetPolicy.supports(bundleIdentifier: bundleIdentifier) else {
            return nil
        }

        if let hitElement {
            if injector.isLikelyEditable(element: hitElement) {
                return hitElement
            }
            if MouseVoiceOpaqueTargetPolicy.allowsOpaqueHit(
                role: injector.copyStringAttribute(kAXRoleAttribute as String, from: hitElement),
                bundleIdentifier: bundleIdentifier
            ) {
                return hitElement
            }
            return nil
        }

        if let focusedElement, injector.isLikelyEditable(element: focusedElement) {
            return focusedElement
        }

        if let focusedElement,
           MouseVoiceOpaqueTargetPolicy.allowsOpaqueFocusedFallback(
               role: injector.copyStringAttribute(kAXRoleAttribute as String, from: focusedElement),
               bundleIdentifier: bundleIdentifier
           ) {
            return focusedElement
        }

        return nil
    }
}

enum MouseVoiceOpaqueTargetPolicy {
    private enum AppFamily {
        case documentEditor
        case messaging
    }

    private static let opaqueEditorRoles: Set<String> = [
        "AXGroup",
        "AXLayoutArea",
        "AXScrollArea",
        "AXUnknown",
        "AXWebArea"
    ]

    static func supports(bundleIdentifier: String?) -> Bool {
        appFamily(for: bundleIdentifier) != nil
    }

    static func allowsOpaqueHit(role: String?, bundleIdentifier: String?) -> Bool {
        guard let family = appFamily(for: bundleIdentifier), let role else { return false }
        switch family {
        case .documentEditor:
            return role == "AXWindow" || opaqueEditorRoles.contains(role)
        case .messaging:
            return opaqueEditorRoles.contains(role)
        }
    }

    static func allowsOpaqueFocusedFallback(role: String?, bundleIdentifier: String?) -> Bool {
        guard appFamily(for: bundleIdentifier) == .documentEditor, let role else { return false }
        return role == "AXWindow" || opaqueEditorRoles.contains(role)
    }

    private static func appFamily(for bundleIdentifier: String?) -> AppFamily? {
        guard let identifier = bundleIdentifier?.lowercased() else { return nil }
        if identifier.hasPrefix("com.sublimetext.")
            || identifier.hasPrefix("dev.zed.")
            || identifier == "com.apple.iwork.pages"
            || identifier == "com.apple.pages" {
            return .documentEditor
        }
        if identifier.hasPrefix("com.tencent.xinwechat") {
            return .messaging
        }
        return nil
    }
}
