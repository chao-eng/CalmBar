import Foundation
import AppKit

/// 单条剪贴板历史记录项
public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var type: ClipboardContentType
    public var title: String
    public var textValue: String?
    public var rtfData: Data?
    public var htmlData: Data?
    public var imageFileName: String?
    public var fileURLs: [String]?
    public var sourceAppBundle: String?
    public var copiedAt: Date
    public var isPinned: Bool
    public var copyCount: Int

    public init(
        id: UUID = UUID(),
        type: ClipboardContentType,
        title: String,
        textValue: String? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imageFileName: String? = nil,
        fileURLs: [String]? = nil,
        sourceAppBundle: String? = nil,
        copiedAt: Date = Date(),
        isPinned: Bool = false,
        copyCount: Int = 1
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.textValue = textValue
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageFileName = imageFileName
        self.fileURLs = fileURLs
        self.sourceAppBundle = sourceAppBundle
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.copyCount = copyCount
    }

    /// 字符计数统计（针对文本类）
    public var characterCount: Int {
        return textValue?.count ?? 0
    }

    /// 行数统计（针对文本类）
    public var lineCount: Int {
        guard let text = textValue else { return 0 }
        return text.components(separatedBy: .newlines).count
    }

    /// 来源 App 名称简写
    public var sourceAppName: String? {
        guard let bundle = sourceAppBundle else { return nil }
        if let appName = bundle.components(separatedBy: ".").last, !appName.isEmpty {
            return appName.capitalized
        }
        return bundle
    }

    /// 检查与另一条记录是否内容实质相同（用于去重合并）
    public func isContentDuplicate(of other: ClipboardItem) -> Bool {
        if type != other.type { return false }
        switch type {
        case .text, .richText, .url, .color:
            return (textValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines) ==
                   (other.textValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .fileURL:
            return fileURLs == other.fileURLs
        case .image:
            if let f = fileURLs, let of = other.fileURLs, !f.isEmpty, !of.isEmpty {
                return f == of
            }
            if let t = textValue, let ot = other.textValue, !t.isEmpty, !ot.isEmpty {
                return t == ot
            }
            return imageFileName != nil && imageFileName == other.imageFileName
        }
    }
}
