import AppKit
import Carbon

@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefFold: EventHotKeyRef?
    private var hotKeyRefPalette: EventHotKeyRef?

    private init() {
        registerGlobalHotKey()
    }

    public func registerGlobalHotKey() {
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
                if status == noErr {
                    if hotKeyID.id == 1 {
                        Task { @MainActor in
                            MenuBarOrganizer.shared.toggleExpandCollapse()
                        }
                    } else if hotKeyID.id == 2 {
                        Task { @MainActor in
                            CommandPaletteWindowController.shared.toggle()
                        }
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        let modifiers = UInt32(cmdKey | optionKey)

        // 1. Option + Command + H -> MenuBar toggle
        let hotKeyID1 = EventHotKeyID(signature: OSType(0x43424152), id: 1) // 'CBAR'
        RegisterEventHotKey(UInt32(kVK_ANSI_H), modifiers, hotKeyID1, GetApplicationEventTarget(), 0, &hotKeyRefFold)

        // 2. Option + Command + K -> Command Palette
        let hotKeyID2 = EventHotKeyID(signature: OSType(0x43424152), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_K), modifiers, hotKeyID2, GetApplicationEventTarget(), 0, &hotKeyRefPalette)
    }

    public func unregister() {
        if let ref = hotKeyRefFold {
            UnregisterEventHotKey(ref)
            hotKeyRefFold = nil
        }
        if let ref = hotKeyRefPalette {
            UnregisterEventHotKey(ref)
            hotKeyRefPalette = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
