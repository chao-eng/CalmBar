import Foundation
import AppKit

public struct AssociatedFileItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let path: String
    public let category: AssociatedFileType
    public var sizeBytes: Int64
    public var isSelected: Bool
    public let isPrivileged: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        category: AssociatedFileType,
        sizeBytes: Int64 = 0,
        isSelected: Bool = true,
        isPrivileged: Bool = false
    ) {
        self.id = id
        self.url = url
        self.path = url.path
        self.category = category
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
        self.isPrivileged = isPrivileged
    }

    public var displayName: String {
        return url.lastPathComponent
    }

    public var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    public static func == (lhs: AssociatedFileItem, rhs: AssociatedFileItem) -> Bool {
        return lhs.path == rhs.path
    }
}
