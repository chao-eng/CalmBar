import Foundation
import Combine

@MainActor
public final class TranslationHistoryManager: ObservableObject {
    public static let shared = TranslationHistoryManager()

    @Published public private(set) var history: [TranslationItem] = []

    private let maxHistoryCount = 200
    private let fileURL: URL

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let calmBarDir = appSupport.appendingPathComponent("CalmBar", isDirectory: true)

        if !fileManager.fileExists(atPath: calmBarDir.path) {
            try? fileManager.createDirectory(at: calmBarDir, withIntermediateDirectories: true)
        }

        self.fileURL = calmBarDir.appendingPathComponent("translations.json")
        load()
    }

    public func add(item: TranslationItem) {
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)

        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }

        save()
    }

    public func update(item: TranslationItem) {
        if let idx = history.firstIndex(where: { $0.id == item.id }) {
            history[idx] = item
            save()
        } else {
            add(item: item)
        }
    }

    public func delete(id: UUID) {
        history.removeAll { $0.id == id }
        save()
    }

    public func clearAll() {
        history.removeAll()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranslationItem].self, from: data) else {
            return
        }
        self.history = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
