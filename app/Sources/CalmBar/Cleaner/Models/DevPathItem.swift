import Foundation

public struct DevCategory: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let iconName: String
    public var paths: [String]

    public init(name: String, iconName: String = "hammer.fill", paths: [String]) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.paths = paths
    }
}

public struct DevPathItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let envName: String
    public let originalPattern: String
    public let expandedPath: String
    public var exists: Bool
    public var isEmpty: Bool
    public var sizeBytes: Int64
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        envName: String,
        originalPattern: String,
        expandedPath: String,
        exists: Bool = false,
        isEmpty: Bool = true,
        sizeBytes: Int64 = 0,
        isSelected: Bool = true
    ) {
        self.id = id
        self.envName = envName
        self.originalPattern = originalPattern
        self.expandedPath = expandedPath
        self.exists = exists
        self.isEmpty = isEmpty
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
    }

    public var displayName: String {
        return (expandedPath as NSString).lastPathComponent
    }

    public var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
