import Carbon.HIToolbox

final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(onHotkey: @escaping @MainActor () -> Void) {
        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Store the callback as an opaque pointer
        let context = Unmanaged.passRetained(Callback(action: onHotkey)).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let cb = Unmanaged<Callback>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    cb.action()
                }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerRef
        )

        var hotkeyID = EventHotKeyID(
            signature: OSType(0x5141_4900), // "QAI\0"
            id: 1
        )

        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    deinit {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }
}

// Box for the callback so we can pass it through C void*
private final class Callback: @unchecked Sendable {
    let action: @MainActor () -> Void
    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }
}
