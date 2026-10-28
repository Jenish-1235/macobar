import Carbon.HIToolbox

/// Option-Space registered system-wide, reporting when it goes down and comes up; needs no Accessibility access.
@MainActor
final class GlobalHotkey {
    /// Tags macobar's hot key ("mcbr") so events for other hot keys are ignored.
    private static let signature: OSType = 0x6D63_6272

    /// Runs when the key goes down.
    private let onPress: () -> Void
    /// Runs when the key comes up.
    private let onRelease: () -> Void
    /// The registered hot key, until `stop()`.
    private var hotKey: EventHotKeyRef?
    /// The installed event handler, until `stop()`.
    private var handler: EventHandlerRef?

    /// Registers Option-Space on the event dispatcher, so it also fires while a menu is open; throws `VoiceError.hotkeyUnavailable` if the system refuses it.
    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) throws {
        self.onPress = onPress
        self.onRelease = onRelease
        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let installed = InstallEventHandler(
            GetEventDispatcherTarget(), Self.handleEvent, eventTypes.count, eventTypes,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard installed == noErr else { throw VoiceError.hotkeyUnavailable(installed) }
        let registered = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(optionKey), EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(), 0, &hotKey
        )
        guard registered == noErr else {
            stop()
            throw VoiceError.hotkeyUnavailable(registered)
        }
    }

    /// Unregisters the key when the hot key goes away.
    isolated deinit {
        stop()
    }

    /// Unregisters the key and removes the handler; safe to call twice.
    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    /// Carbon's callback: finds the `GlobalHotkey` behind `userData` and passes the press or release on.
    private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let read = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
        )
        guard read == noErr, hotKeyID.signature == signature else { return OSStatus(eventNotHandledErr) }
        let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
        MainActor.assumeIsolated { isPress ? hotkey.onPress() : hotkey.onRelease() }
        return noErr
    }
}
