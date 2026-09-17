import Foundation

enum HotkeyAction {
    case auxiliary
    case activation
    case ask
    case personaPicker
    case history
}

struct HotkeyEventContext: Sendable, Equatable {
    let detectedAt: Date
    /// Physical event time in seconds since system startup.
    let uptime: TimeInterval

    init(detectedAt: Date? = nil, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.detectedAt = detectedAt ?? Date().addingTimeInterval(uptime - ProcessInfo.processInfo.systemUptime)
        self.uptime = uptime
    }
}

protocol HotkeyService: AnyObject {
    var onAuxiliaryPressBegan: ((HotkeyEventContext) -> Void)? { get set }
    var onAuxiliaryPressEnded: ((HotkeyEventContext) -> Void)? { get set }
    var onAuxiliaryPromoted: ((HotkeyEventContext) -> Void)? { get set }
    var onActivationTap: ((HotkeyEventContext) -> Void)? { get set }
    var onActivationPressBegan: ((HotkeyEventContext) -> Void)? { get set }
    var onActivationPressEnded: ((HotkeyEventContext) -> Void)? { get set }
    var onActivationCancelled: (() -> Void)? { get set }
    var onAskPressBegan: ((HotkeyEventContext) -> Void)? { get set }
    var onAskPressEnded: (() -> Void)? { get set }
    var onPersonaPickerRequested: (() -> Void)? { get set }
    var onHistoryRequested: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }

    func start()
    func stop()
    func settleActivationGesture()
}

extension HotkeyService {
    var onAuxiliaryPressBegan: ((HotkeyEventContext) -> Void)? { get { nil } set {} }
    var onAuxiliaryPressEnded: ((HotkeyEventContext) -> Void)? { get { nil } set {} }
    var onAuxiliaryPromoted: ((HotkeyEventContext) -> Void)? { get { nil } set {} }
    func settleActivationGesture() {}
}
