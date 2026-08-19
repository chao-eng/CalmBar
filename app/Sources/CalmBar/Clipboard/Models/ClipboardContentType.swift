import Foundation

/// 剪贴板内容的主格式分类
public enum ClipboardContentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text = "text"
    case richText = "richText"
    case image = "image"
    case fileURL = "fileURL"
    case url = "url"
    case color = "color"

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .text: return "纯文本"
        case .richText: return "富文本"
        case .image: return "图片"
        case .fileURL: return "文件"
        case .url: return "链接"
        case .color: return "颜色"
        }
    }

    public var iconName: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "text.badge.star"
        case .image: return "photo.fill"
        case .fileURL: return "doc.fill"
        case .url: return "link"
        case .color: return "paintpalette.fill"
        }
    }
}
