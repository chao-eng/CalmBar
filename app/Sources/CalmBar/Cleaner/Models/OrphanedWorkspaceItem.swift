import Foundation

public struct OrphanedWorkspaceItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let ideName: String
    public let workspaceName: String
    public let storagePath: String
    public let projectOriginalFolderPath: String
    public var sizeBytes: Int64
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        ideName: String,
        workspaceName: String,
        storagePath: String,
        projectOriginalFolderPath: String,
        sizeBytes: Int64 = 0,
        isSelected: Bool = true
    ) {
        self.id = id
        self.ideName = ideName
        self.workspaceName = workspaceName
        self.storagePath = storagePath
        self.projectOriginalFolderPath = projectOriginalFolderPath
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
    }

    public var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public var projectFolderName: String {
        return (projectOriginalFolderPath as NSString).lastPathComponent
    }
}

public struct PipPackageItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let version: String
    public var sizeBytes: Int64
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        version: String,
        sizeBytes: Int64 = 0,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
    }

    public var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
