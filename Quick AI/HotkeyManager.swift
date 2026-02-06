import Carbon.HIToolbox

final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callbackContext: UnsafeMutableRawPointer?

    init(onHotkey: @escaping @MainActor () -> Void) {
        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Store the callback as an opaque pointer
        callbackContext = Unmanaged.passRetained(Callback(action: onHotkey)).toOpaque()
        guard let callbackContext else { return }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let cb = Unmanaged<Callback>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    cb.action()
                }
                return noErr
            },
            1,
            &eventType,
            callbackContext,
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            releaseCallbackContext()
            return
        }

        let hotkeyID = EventHotKeyID(
            signature: OSType(0x5141_4900), // "QAI\0"
            id: 1
        )

        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        guard registerStatus == noErr else {
            if let ref = eventHandlerRef {
                RemoveEventHandler(ref)
                eventHandlerRef = nil
            }
            releaseCallbackContext()
            return
        }
    }

    deinit {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
        releaseCallbackContext()
    }

    private func releaseCallbackContext() {
        guard let callbackContext else { return }
        Unmanaged<Callback>.fromOpaque(callbackContext).release()
        self.callbackContext = nil
    }
}

// Box for the callback so we can pass it through C void*
private final class Callback: @unchecked Sendable {
    let action: @MainActor () -> Void
    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }
}
