import AppKit
import Carbon.HIToolbox

/// Thin wrapper around Carbon `RegisterEventHotKey` for a single global shortcut.
final class HotKeyManager {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onPress?() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }
        let id = EventHotKeyID(signature: OSType(0x5357_5443), id: 1) // "SWTC"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { NSLog("SwatchSnatcher: hotkey registration failed (\(status))") }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// Converts AppKit modifier flags to Carbon modifier bits.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return m
    }

    static func symbols(for carbon: Int) -> String {
        var s = ""
        if carbon & controlKey != 0 { s += "⌃" }
        if carbon & optionKey != 0 { s += "⌥" }
        if carbon & shiftKey != 0 { s += "⇧" }
        if carbon & cmdKey != 0 { s += "⌘" }
        return s
    }
}
