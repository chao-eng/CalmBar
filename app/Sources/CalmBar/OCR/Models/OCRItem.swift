import Foundation

public enum OCRType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case barcode

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .text: return "文本"
        case .barcode: return "二维码/条码"
        }
    }
}

public struct OCRItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public var text: String
    public var type: OCRType

    public init(id: UUID = UUID(), timestamp: Date = Date(), text: String, type: OCRType = .text) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.type = type
    }

    /// 提取识别内容中的第一个有效 URL
    public var detectedURL: URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(https?:\/\/)?(www\.)?[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)+.*$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }
}
