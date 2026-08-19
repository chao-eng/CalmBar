import AppKit
import Combine
import Foundation

@MainActor
public final class ClipboardHistoryManager: ObservableObject {
    public static let shared = ClipboardHistoryManager()

    @Published public var items: [ClipboardItem] = [] {
        didSet {
            saveToDisk()
        }
    }

    private let fileName = "clipboard_history.json"
    private let imagesDirName = "clipboard_images"
    private var customStorageURL: URL?

    public init(customStorageURL: URL? = nil) {
        self.customStorageURL = customStorageURL
        loadFromDisk()
    }

    // MARK: - Directory & File URLs

    public var baseDirectoryURL: URL {
        if let custom = customStorageURL {
            return custom.deletingLastPathComponent()
        }
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CalmBar", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())

        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }

    private var storageFileURL: URL {
        if let custom = customStorageURL {
            return custom
        }
        return baseDirectoryURL.appendingPathComponent(fileName)
    }

    public var imagesDirectoryURL: URL {
        let dir = baseDirectoryURL.appendingPathComponent(imagesDirName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Disk Persistence

    public func loadFromDisk() {
        let url = storageFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
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

    // MARK: - Item Mutation & Dedup

    /// 添加一条历史记录（自动去重、推至顶部、超限清理）
    @discardableResult
    public func add(item: ClipboardItem, maxCount: Int = 200) -> UUID {
        var currentItems = self.items

        // 检查是否存在重复内容
        let targetId: UUID
        if let existingIndex = currentItems.firstIndex(where: { $0.isContentDuplicate(of: item) }) {
            var existing = currentItems.remove(at: existingIndex)
            existing.copiedAt = Date()
            existing.copyCount += 1
            existing.sourceAppBundle = item.sourceAppBundle ?? existing.sourceAppBundle
            // 如果新提取出了标题或富文本，进行补充
            if existing.title.isEmpty && !item.title.isEmpty {
                existing.title = item.title
            }
            targetId = existing.id
            currentItems.insert(existing, at: 0)
        } else {
            targetId = item.id
            currentItems.insert(item, at: 0)
        }

        // 容量截断（保留所有已固定 Pin 的项，对未固定项从尾部清理）
        if maxCount > 0 && currentItems.count > maxCount {
            var unpinnedCount = 0
            var filtered: [ClipboardItem] = []
            var itemsToRemove: [ClipboardItem] = []

            for it in currentItems {
                if it.isPinned {
                    filtered.append(it)
                } else {
                    if unpinnedCount < maxCount {
                        filtered.append(it)
                        unpinnedCount += 1
                    } else {
                        itemsToRemove.append(it)
                    }
                }
            }

            // 清理被丢弃记录的关联图片缓存
            for discarded in itemsToRemove {
                if let imgName = discarded.imageFileName {
                    let imgURL = imagesDirectoryURL.appendingPathComponent(imgName)
                    try? FileManager.default.removeItem(at: imgURL)
                }
            }

            currentItems = filtered
        }

        self.items = currentItems
        return targetId
    }

    /// 切换条目的固定 (Pin) 状态
    public func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
    }

    /// 更新图片条目的 OCR 识别文字与二维码索引
    public func updateOCRText(id: UUID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items
        updated[index].textValue = text
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            let snippet = clean.count > 60 ? String(clean.prefix(60)) + "..." : clean
            if updated[index].title.starts(with: "图片") {
                updated[index].title = "图片: \(snippet)"
            }
        }
        self.items = updated
    }

    /// 删除指定条目
    public func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        if let imgName = removed.imageFileName {
            let imgURL = imagesDirectoryURL.appendingPathComponent(imgName)
            try? FileManager.default.removeItem(at: imgURL)
        }
    }

    /// 清空历史记录（可选是否保留固定项）
    public func clearAll(keepPinned: Bool = true) {
        if keepPinned {
            let removedItems = items.filter { !$0.isPinned }
            for it in removedItems {
                if let imgName = it.imageFileName {
                    let imgURL = imagesDirectoryURL.appendingPathComponent(imgName)
                    try? FileManager.default.removeItem(at: imgURL)
                }
            }
            self.items = items.filter { $0.isPinned }
        } else {
            for it in items {
                if let imgName = it.imageFileName {
                    let imgURL = imagesDirectoryURL.appendingPathComponent(imgName)
                    try? FileManager.default.removeItem(at: imgURL)
                }
            }
            self.items.removeAll()
        }
    }

    // MARK: - Pasteboard Writeback

    /// 将历史记录写回系统剪贴板
    public func copyToPasteboard(item: ClipboardItem, plainTextOnly: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var itemsToWrite: [NSPasteboardItem] = []
        let pbItem = NSPasteboardItem()

        // 写入防自环标记
        pbItem.setString("calmbar", forType: ClipboardSecurityFilter.fromCalmBarType)

        if plainTextOnly {
            if let text = item.textValue {
                pbItem.setString(text, forType: .string)
            }
        } else {
            switch item.type {
            case .text, .url, .color:
                if let text = item.textValue {
                    pbItem.setString(text, forType: .string)
                }
            case .richText:
                if let rtf = item.rtfData {
                    pbItem.setData(rtf, forType: .rtf)
                }
                if let html = item.htmlData {
                    pbItem.setData(html, forType: .html)
                }
                if let text = item.textValue {
                    pbItem.setString(text, forType: .string)
                }
            case .image:
                if let imgName = item.imageFileName {
                    let imgURL = imagesDirectoryURL.appendingPathComponent(imgName)
                    if let imgData = try? Data(contentsOf: imgURL) {
                        pbItem.setData(imgData, forType: .png)
                        pbItem.setData(imgData, forType: .tiff)
                    }
                }
                if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
                    let urlObjects = fileURLs.compactMap { URL(fileURLWithPath: $0) as NSURL }
                    itemsToWrite.append(pbItem)
                    pasteboard.writeObjects(itemsToWrite)
                    pasteboard.writeObjects(urlObjects)
                    return
                }
            case .fileURL:
                if let fileURLs = item.fileURLs {
                    let urlObjects = fileURLs.compactMap { URL(fileURLWithPath: $0) as NSURL }
                    itemsToWrite.append(pbItem)
                    pasteboard.writeObjects(itemsToWrite)
                    pasteboard.writeObjects(urlObjects)
                    return
                }
            }
        }

        itemsToWrite.append(pbItem)
        pasteboard.writeObjects(itemsToWrite)
    }

    // MARK: - Helpers

    /// 获取存储占用格式化字符串
    public var storageSizeFormatted: String {
        var totalBytes: Int64 = 0
        if let jsonAttrs = try? FileManager.default.attributesOfItem(atPath: storageFileURL.path),
           let jsonSize = jsonAttrs[.size] as? Int64 {
            totalBytes += jsonSize
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: imagesDirectoryURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalBytes += Int64(size)
                }
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }
}
