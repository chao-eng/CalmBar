import AppKit
import Carbon

@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefFold: EventHotKeyRef?
    private var hotKeyRefPalette: EventHotKeyRef?
    private var hotKeyRefOCR: EventHotKeyRef?
    private var hotKeyRefClipboard: EventHotKeyRef?
    private var hotKeyRefTranslation: EventHotKeyRef?

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
                            if AppSettings.shared.menuBarOrganizerEnabled {
                                MenuBarOrganizer.shared.toggleExpandCollapse()
                            }
                        }
                    } else if hotKeyID.id == 2 {
                        Task { @MainActor in
                            CommandPaletteWindowController.shared.toggle()
                        }
                    } else if hotKeyID.id == 3 {
                        Task { @MainActor in
                            if AppSettings.shared.ocrEnabled {
                                OCRManager.shared.startCaptureAndRecognize()
                            }
                        }
                    } else if hotKeyID.id == 4 {
                        Task { @MainActor in
                            if AppSettings.shared.clipboardHistoryEnabled {
                                ClipboardHistoryWindowController.shared.toggle()
                            }
                        }
                    } else if hotKeyID.id == 5 {
                        Task { @MainActor in
                            if AppSettings.shared.translationEnabled {
                                TranslationManager.shared.translateFromClipboard()
                            }
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

        // 3. Option + Command + O -> Screen OCR Selection Capture
        let hotKeyID3 = EventHotKeyID(signature: OSType(0x43424152), id: 3)
        RegisterEventHotKey(UInt32(kVK_ANSI_O), modifiers, hotKeyID3, GetApplicationEventTarget(), 0, &hotKeyRefOCR)

        // 4. Option + Command + V -> Clipboard History Toggle
        let hotKeyID4 = EventHotKeyID(signature: OSType(0x43424152), id: 4)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), modifiers, hotKeyID4, GetApplicationEventTarget(), 0, &hotKeyRefClipboard)

        // 5. Option + Command + T -> Quick AI Translate Clipboard
        let hotKeyID5 = EventHotKeyID(signature: OSType(0x43424152), id: 5)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), modifiers, hotKeyID5, GetApplicationEventTarget(), 0, &hotKeyRefTranslation)
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
        if let ref = hotKeyRefOCR {
            UnregisterEventHotKey(ref)
            hotKeyRefOCR = nil
        }
        if let ref = hotKeyRefClipboard {
            UnregisterEventHotKey(ref)
            hotKeyRefClipboard = nil
        }
        if let ref = hotKeyRefTranslation {
            UnregisterEventHotKey(ref)
            hotKeyRefTranslation = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
