import AppKit
import Carbon.HIToolbox

// MARK: - Global hotkeys (Carbon RegisterEventHotKey; no accessibility permission needed)

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {}

    /// Registers a global hotkey. Returns false (and logs) on failure so a
    /// conflicting registration never crashes the app.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, description: String, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x50494B41), id: id) // "PIKA"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, ref != nil else {
            logWarn("Hotkey registration failed for \(description) (status \(status))")
            return false
        }
        handlers[id] = handler
        hotKeyRefs.append(ref)
        logInfo("Hotkey registered: \(description)")
        return true
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    DispatchQueue.main.async {
                        HotkeyManager.shared.handlers[hotKeyID.id]?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }
}

// ANSI key codes for the default bindings.
enum KeyCode {
    static let p: UInt32 = 35
    static let j: UInt32 = 38
    static let r: UInt32 = 15
    static let s: UInt32 = 1
    static let e: UInt32 = 14
    static let h: UInt32 = 4
    static let l: UInt32 = 37
    static let g: UInt32 = 5
}

let ctrlShift = UInt32(controlKey | shiftKey)
