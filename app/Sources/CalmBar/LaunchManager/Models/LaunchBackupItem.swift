import Foundation

public struct LaunchBackupItem: Identifiable, Hashable, Sendable {
    public var id: String { fileURL.path }
    public let label: String
    public let fileURL: URL
    public let creationDate: Date
    public let originalScope: LaunchScope?
    public let fileSize: Int64

    public init(
        label: String,
        fileURL: URL,
        creationDate: Date,
        originalScope: LaunchScope? = nil,
        fileSize: Int64 = 0
    ) {
        self.label = label
        self.fileURL = fileURL
        self.creationDate = creationDate
        self.originalScope = originalScope
        self.fileSize = fileSize
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
