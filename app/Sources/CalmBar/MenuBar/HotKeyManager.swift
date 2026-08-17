import AppKit
import Carbon

@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    private init() {
        registerGlobalHotKey()
    }

    public func registerGlobalHotKey() {
        // Register Option + Command + H (or custom key)
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x43424152) // 'CBAR'
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamName(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr && hotKeyID.id == 1 {
                    Task { @MainActor in
                        MenuBarOrganizer.shared.toggleExpandCollapse()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // Key code for 'H' is 4, Option + Command modifiers = cmdKey | optionKey
        let modifiers = UInt32(cmdKey | optionKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_H), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
