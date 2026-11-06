import Carbon
import AppKit
import Foundation

extension Notification.Name {
    static let launchpadGlobalHotKeyPressed = Notification.Name("LaunchpadOS.GlobalHotKeyPressed")
}

final class GlobalHotKeyController: @unchecked Sendable {
    static let shared = GlobalHotKeyController()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: 0x4C504F53, id: 1)

    private init() {}

    @discardableResult
    func start() -> Bool {
        let defaults = UserDefaults.standard
        let keyCode = defaults.object(forKey: SettingsKeys.globalHotKeyKeyCode) == nil
            ? UInt32(kVK_Space)
            : UInt32(defaults.integer(forKey: SettingsKeys.globalHotKeyKeyCode))
        let modifiers = defaults.object(forKey: SettingsKeys.globalHotKeyModifiers) == nil
            ? UInt32(optionKey)
            : UInt32(defaults.integer(forKey: SettingsKeys.globalHotKeyModifiers))
        return register(keyCode: keyCode, modifiers: modifiers)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        stop()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.notifyPressed()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else { return false }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            stop()
            return false
        }
        return true
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func displayName(for event: NSEvent) -> String {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }

        let keyName: String
        switch event.keyCode {
        case 49: keyName = "Space"
        case 36: keyName = "Return"
        case 48: keyName = "Tab"
        case 51: keyName = "Delete"
        case 53: keyName = "Esc"
        case 123: keyName = "←"
        case 124: keyName = "→"
        case 125: keyName = "↓"
        case 126: keyName = "↑"
        default: keyName = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
        return "\(result) \(keyName)"
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func notifyPressed() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .launchpadGlobalHotKeyPressed, object: nil)
        }
    }
}
