import AppKit

/// Pure physical-key capture state, shared by the recorder and its tests.
struct AuxiliaryHotkeyCapture {
    private var modifiers = Set<Int>()
    private var keysDown = Set<Int>()
    private var lastReleased: (key: Int, flags: UInt, time: TimeInterval)?
    private var current: HotkeyBinding?

    mutating func handle(
        type: NSEvent.EventType, keyCode: Int, flags: UInt,
        isRepeat: Bool, timestamp: TimeInterval
    ) -> HotkeyBinding? {
        guard !isRepeat else { return nil }
        if type == .keyUp {
            keysDown.remove(keyCode)
            if let current { lastReleased = (current.keyCode, current.modifierFlags, timestamp) }
            return nil
        }
        if type == .flagsChanged {
            let mask = HotkeyBinding.modifierFlag(for: keyCode)
            guard mask != 0 else { return nil }
            if flags & mask == 0 || modifiers.contains(keyCode) {
                modifiers.remove(keyCode)
                if let current { lastReleased = (current.keyCode, current.modifierFlags, timestamp) }
                return nil
            }
            modifiers.insert(keyCode)
            modifiers = modifiers.filter { flags & HotkeyBinding.modifierFlag(for: $0) != 0 }
            if modifiers.count > 1 {
                let keys = modifiers.sorted()
                let binding = HotkeyBinding(
                    keyCode: keys.contains(56) ? 56 : keys[0], modifierFlags: flags, modifierKeyCodes: keys
                )
                current = binding
                return binding
            }
        } else {
            guard type == .keyDown, !keysDown.contains(keyCode) else { return nil }
            keysDown.insert(keyCode)
        }
        let doubleTap = lastReleased.map {
            $0.key == keyCode && $0.flags == flags && timestamp - $0.time <= HotkeyGestureArbiter.doubleTapMaximumInterval
        } ?? false
        let binding = HotkeyBinding(keyCode: keyCode, modifierFlags: flags, pressCount: doubleTap ? 2 : nil)
        current = binding
        return binding
    }
}
