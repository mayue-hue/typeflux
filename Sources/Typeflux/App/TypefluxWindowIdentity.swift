import AppKit

enum TypefluxWindowIdentity {
    static let askAnswerWindowIdentifier = NSUserInterfaceItemIdentifier(
        "ai.gulu.app.typeflux.window.ask-answer"
    )

    static func isAskAnswerWindow(_ window: NSWindow?) -> Bool {
        window?.identifier == askAnswerWindowIdentifier
    }
}
