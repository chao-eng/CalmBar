import AppKit
import Foundation
import Testing
@testable import CalmBar

@Suite("Clipboard History and Security Tests")
struct ClipboardTests {

    @Test("Test ClipboardItem model JSON encoding and decoding")
    func testClipboardItemCodable() throws {
        let item = ClipboardItem(
            type: .text,
            title: "Swift 6 Concurrency Guide",
            textValue: "Swift 6 introduces complete data race safety.",
            sourceAppBundle: "com.apple.dt.Xcode",
            isPinned: true,
            copyCount: 3
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        #expect(decoded.id == item.id)
        #expect(decoded.type == .text)
        #expect(decoded.title == "Swift 6 Concurrency Guide")
        #expect(decoded.textValue == "Swift 6 introduces complete data race safety.")
        #expect(decoded.sourceAppBundle == "com.apple.dt.Xcode")
        #expect(decoded.sourceAppName == "Xcode")
        #expect(decoded.isPinned == true)
        #expect(decoded.copyCount == 3)
        #expect(decoded.characterCount > 0)
        #expect(decoded.lineCount == 1)
    }

    @Test("Test ClipboardItem content deduplication detection")
    func testClipboardItemDuplicateCheck() {
        let item1 = ClipboardItem(type: .text, title: "Title 1", textValue: "Hello CalmBar")
        let item2 = ClipboardItem(type: .text, title: "Title 2", textValue: "  Hello CalmBar\n ")
        let item3 = ClipboardItem(type: .text, title: "Title 3", textValue: "Different text")
        let item4 = ClipboardItem(type: .url, title: "Title 4", textValue: "Hello CalmBar")

        #expect(item1.isContentDuplicate(of: item2) == true)
        #expect(item1.isContentDuplicate(of: item3) == false)
        #expect(item1.isContentDuplicate(of: item4) == false) // Different type
    }

    @Test("Test ClipboardSecurityFilter against sensitive pasteboard types and blacklist apps")
    func testSecurityFilter() {
        // 1. Normal Item
        let normalItem = NSPasteboardItem()
        normalItem.setString("Normal safe code snippet", forType: .string)
        #expect(ClipboardSecurityFilter.shouldIgnore(item: normalItem, sourceAppBundle: "com.apple.Terminal") == false)

        // 2. Sensitive Type (Transient Type used by Password Managers)
        let sensitiveItem = NSPasteboardItem()
        sensitiveItem.setString("super_secret_password", forType: .string)
        sensitiveItem.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        #expect(ClipboardSecurityFilter.shouldIgnore(item: sensitiveItem) == true)

        // 3. From CalmBar self-writeback type
        let selfItem = NSPasteboardItem()
        selfItem.setString("Copied from CalmBar UI", forType: .string)
        selfItem.setString("calmbar", forType: ClipboardSecurityFilter.fromCalmBarType)
        #expect(ClipboardSecurityFilter.shouldIgnore(item: selfItem) == true)

        // 4. Blacklisted App Bundle
        let pwAppItem = NSPasteboardItem()
        pwAppItem.setString("1Password Entry", forType: .string)
        #expect(ClipboardSecurityFilter.shouldIgnore(item: pwAppItem, sourceAppBundle: "com.1password.1password") == true)
        #expect(ClipboardSecurityFilter.shouldIgnore(item: pwAppItem, sourceAppBundle: "com.bitwarden.desktop") == true)

        // 5. User Custom Ignored App
        #expect(ClipboardSecurityFilter.shouldIgnore(item: normalItem, sourceAppBundle: "com.custom.secretApp", userIgnoredApps: ["com.custom.secretApp"]) == true)

        // 6. Empty String Item
        let emptyItem = NSPasteboardItem()
        emptyItem.setString("   \n\t  ", forType: .string)
        #expect(ClipboardSecurityFilter.shouldIgnore(item: emptyItem) == true)
    }

    @Test("Test ClipboardHistoryManager add, deduplication, pin retention and eviction")
    @MainActor
    func testClipboardHistoryManager() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("calmbar_clipboard_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("test_clipboard_history.json")

        let manager = ClipboardHistoryManager(customStorageURL: tempFile)
        #expect(manager.items.isEmpty)

        // 1. Add 3 distinct items
        let item1 = ClipboardItem(type: .text, title: "Item 1", textValue: "Content 1")
        let item2 = ClipboardItem(type: .text, title: "Item 2", textValue: "Content 2")
        let item3 = ClipboardItem(type: .url, title: "Item 3", textValue: "https://apple.com")

        manager.add(item: item1, maxCount: 3)
        manager.add(item: item2, maxCount: 3)
        manager.add(item: item3, maxCount: 3)

        #expect(manager.items.count == 3)
        #expect(manager.items[0].title == "Item 3")

        // 2. Duplicate item insertion -> should move to front and increment copyCount
        let dupItem1 = ClipboardItem(type: .text, title: "Item 1 New", textValue: "Content 1")
        manager.add(item: dupItem1, maxCount: 3)

        #expect(manager.items.count == 3)
        #expect(manager.items[0].textValue == "Content 1")
        #expect(manager.items[0].copyCount == 2)

        // 3. Pin an item
        manager.togglePin(id: manager.items[2].id) // Pin item2 ("Content 2")
        #expect(manager.items[2].isPinned == true)

        // 4. Add exceeding maxCount -> unpinned oldest should be evicted, pinned should be preserved
        let item4 = ClipboardItem(type: .text, title: "Item 4", textValue: "Content 4")
        let item5 = ClipboardItem(type: .text, title: "Item 5", textValue: "Content 5")
        manager.add(item: item4, maxCount: 3)
        manager.add(item: item5, maxCount: 3)

        // Pinned item must still exist
        #expect(manager.items.contains(where: { $0.textValue == "Content 2" && $0.isPinned }))

        // 5. Remove single item
        let idToRemove = manager.items[0].id
        manager.remove(id: idToRemove)
        #expect(!manager.items.contains(where: { $0.id == idToRemove }))

        // 6. Clear all keeping pinned
        manager.clearAll(keepPinned: true)
        #expect(manager.items.count == 1)
        #expect(manager.items[0].isPinned == true)

        // 7. Clear all completely
        manager.clearAll(keepPinned: false)
        #expect(manager.items.isEmpty)
    }

    @Test("Test Image pasteboard items are recognized and not ignored by security filter")
    func testImageSecurityFilter() {
        // PNG image item
        let pngItem = NSPasteboardItem()
        pngItem.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        #expect(ClipboardSecurityFilter.shouldIgnore(item: pngItem) == false)

        // JPEG image item
        let jpegItem = NSPasteboardItem()
        jpegItem.setData(Data([0xFF, 0xD8, 0xFF]), forType: NSPasteboard.PasteboardType("public.jpeg"))
        #expect(ClipboardSecurityFilter.shouldIgnore(item: jpegItem) == false)

        // HEIC image item
        let heicItem = NSPasteboardItem()
        heicItem.setData(Data([0x00, 0x00, 0x00, 0x20]), forType: NSPasteboard.PasteboardType("public.heic"))
        #expect(ClipboardSecurityFilter.shouldIgnore(item: heicItem) == false)
    }

    @Test("Test AppSettings clipboard defaults and visibility")
    @MainActor
    func testAppSettingsClipboard() {
        let settings = AppSettings.shared
        #expect(settings.clipboardHistoryEnabled == true)
        #expect(settings.clipboardMaxCount >= 50)
        #expect(settings.clipboardSaveImages == true)
        #expect(settings.clipboardFilterSensitive == true)
        #expect(settings.popoverShowClipboard == true)
    }
}
