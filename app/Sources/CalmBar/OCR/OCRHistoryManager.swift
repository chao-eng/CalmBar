import Foundation
import Combine

@MainActor
public final class OCRHistoryManager: ObservableObject {
    public static let shared = OCRHistoryManager()

    @Published public var items: [OCRItem] = [] {
        didSet {
            saveToDisk()
        }
    }

    private let fileName = "ocr_history.json"
    private var customStorageURL: URL?

    public init(customStorageURL: URL? = nil) {
        self.customStorageURL = customStorageURL
        loadFromDisk()
    }

    private var storageFileURL: URL {
        if let custom = customStorageURL {
            return custom
        }
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CalmBar", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())

        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport.appendingPathComponent(fileName)
    }

    public func loadFromDisk() {
        let url = storageFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([OCRItem].self, from: data) else {
            return
        }
        self.items = decoded
    }

    public func saveToDisk() {
        let url = storageFileURL
        let itemsToSave = self.items
        DispatchQueue.global(qos: .background).async {
            if let data = try? JSONEncoder().encode(itemsToSave) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    public func add(text: String, type: OCRType = .text, maxCount: Int = 100) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newItem = OCRItem(text: trimmed, type: type)
        // 插入到最前面
        var updated = items
        updated.insert(newItem, at: 0)

        // 限制最大历史条数
        if updated.count > maxCount {
            updated = Array(updated.prefix(maxCount))
        }

        self.items = updated
    }

    public func remove(id: UUID) {
        self.items.removeAll { $0.id == id }
    }

    public func clearAll() {
        self.items.removeAll()
    }
}
