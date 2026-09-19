import Foundation

/// Recognizes complete input shortcuts independently of the shortcut that started recording.
/// Physical key state is tracked even while idle so a held startup key cannot stop itself.
struct RecordingStopGesture {
    private var pressedKeys = Set<Int>()
    private var downBindings = Set<String>()
    private var releaseEligibleBindings = Set<String>()
    private var lastReleases: [String: TimeInterval] = [:]
    private var wasEnabled = false
    private var submitted = false
    private var suppressActivationUntil: TimeInterval?
    private(set) var suppressesActivation = false
    private(set) var isPress = false

    mutating func handle(
        type: HotkeyPhysicalEventType,
        keyCode: Int,
        flags: UInt,
        isRepeat: Bool,
        bindings: [HotkeyBinding],
        enabled: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        if enabled != wasEnabled {
            lastReleases.removeAll()
            releaseEligibleBindings.removeAll()
            submitted = false
            wasEnabled = enabled
        }
        let wasDown = pressedKeys.contains(keyCode)
        switch type {
        case .keyDown:
            pressedKeys.insert(keyCode)
        case .keyUp:
            pressedKeys.remove(keyCode)
        case .flagsChanged:
            let mask = HotkeyBinding.modifierFlag(for: keyCode)
            if mask != 0, flags & mask != 0, !wasDown {
                pressedKeys.insert(keyCode)
            } else {
                pressedKeys.remove(keyCode)
            }
        }
        isPress = !wasDown && pressedKeys.contains(keyCode) && !isRepeat
        suppressesActivation = false
        var matched = false
        for binding in bindings {
            let signature = binding.signature
            let modifierKeys = Set(binding.physicalModifierKeys)
            let down = modifierKeys.isEmpty
                ? pressedKeys.contains(binding.keyCode) && flags == binding.modifierFlags
                : modifierKeys.isSubset(of: pressedKeys) && flags == binding.modifierFlags
            let previouslyDown = downBindings.contains(signature)
            if !down {
                downBindings.remove(signature)
                if releaseEligibleBindings.remove(signature) != nil, enabled {
                    lastReleases[signature] = timestamp
                }
                continue
            }
            downBindings.insert(signature)
            guard isPress, !previouslyDown else { continue }
            guard modifierKeys.isEmpty ? keyCode == binding.keyCode : modifierKeys.contains(keyCode) else { continue }
            if let suppressActivationUntil, timestamp <= suppressActivationUntil {
                suppressesActivation = true
                continue
            }
            guard enabled, !submitted else { continue }
            releaseEligibleBindings.insert(signature)
            if binding.pressCount == 2 {
                guard let release = lastReleases.removeValue(forKey: signature),
                      timestamp - release <= HotkeyGestureArbiter.doubleTapMaximumInterval else { continue }
            }
            matched = true
        }
        if matched {
            submitted = true
            // A shared single/double-tap shortcut may have another tap in flight.
            suppressActivationUntil = timestamp + HotkeyGestureArbiter.doubleTapMaximumInterval
        }
        return matched
    }
}
