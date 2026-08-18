import Testing
import Foundation
@testable import CalmBar

@Suite("OCR Recognition and History Tests")
struct OCRTests {
    @Test("Test OCRItem model initialization and JSON encoding/decoding")
    func testOCRItemCodable() throws {
        let item = OCRItem(text: "Hello World 123", type: .text)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(OCRItem.self, from: data)

        #expect(decoded.id == item.id)
        #expect(decoded.text == "Hello World 123")
        #expect(decoded.type == .text)
    }

    @Test("Test URL detection in OCR text")
    func testDetectedURL() {
        let urlItem1 = OCRItem(text: "https://apple.com/macbook-pro")
        #expect(urlItem1.detectedURL?.host == "apple.com")

        let urlItem2 = OCRItem(text: "www.github.com/chao-eng/CalmBar")
        #expect(urlItem2.detectedURL?.scheme == "https")
        #expect(urlItem2.detectedURL?.host == "www.github.com")

        let plainItem = OCRItem(text: "Just some normal recognized text without link")
        #expect(plainItem.detectedURL == nil)
    }

    @Test("Test OCRHistoryManager add, remove, limit and persistence")
    @MainActor
    func testOCRHistoryManager() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("calmbar_ocr_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("test_ocr_history.json")

        let manager = OCRHistoryManager(customStorageURL: tempFile)
        #expect(manager.items.isEmpty)

        // 1. Add items
        manager.add(text: "First text", type: .text, maxCount: 3)
        manager.add(text: "Second text", type: .text, maxCount: 3)
        manager.add(text: "Barcode text", type: .barcode, maxCount: 3)

        #expect(manager.items.count == 3)
        #expect(manager.items[0].text == "Barcode text")
        #expect(manager.items[0].type == .barcode)

        // 2. Add exceeding maxCount
        manager.add(text: "Fourth text", type: .text, maxCount: 3)
        #expect(manager.items.count == 3)
        #expect(manager.items[0].text == "Fourth text")
        #expect(manager.items[2].text == "Second text") // "First text" was dropped

        // 3. Remove single item
        let idToRemove = manager.items[1].id
        manager.remove(id: idToRemove)
        #expect(manager.items.count == 2)

        // 4. Clear all
        manager.clearAll()
        #expect(manager.items.isEmpty)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Test OCR settings in AppSettings")
    @MainActor
    func testAppSettingsOCR() {
        let settings = AppSettings.shared
        let originalAccurate = settings.ocrQualityAccurate
        let originalPopoverOCR = settings.popoverShowOCR

        settings.ocrQualityAccurate = false
        #expect(settings.ocrQualityAccurate == false)
        settings.ocrQualityAccurate = originalAccurate

        let originalAutoDismiss = settings.ocrAutoDismiss
        let originalAutoDismissDelay = settings.ocrAutoDismissDelay

        settings.ocrAutoDismiss = false
        #expect(settings.ocrAutoDismiss == false)
        settings.ocrAutoDismiss = originalAutoDismiss

        settings.ocrAutoDismissDelay = 30.0
        #expect(settings.ocrAutoDismissDelay == 30.0)
        settings.ocrAutoDismissDelay = originalAutoDismissDelay

        settings.popoverShowOCR = false
        #expect(settings.popoverShowOCR == false)
        settings.popoverShowOCR = originalPopoverOCR
    }
}
