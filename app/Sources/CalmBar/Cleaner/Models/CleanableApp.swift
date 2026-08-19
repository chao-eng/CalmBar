import Foundation
import AppKit

public struct CleanableApp: Identifiable, Hashable, @unchecked Sendable {
    public let id: UUID
    public let bundleURL: URL
    public let path: String
    public let appName: String
    public let bundleIdentifier: String
    public let version: String
    public let buildNumber: String?
    public let architecture: AppArchitecture
    public let teamIdentifier: String?
    public let icon: NSImage
    public let isSystemApp: Bool
    public var isRunning: Bool
    public var bundleSize: Int64
    public var associatedItems: [AssociatedFileItem]
    public var lastModifiedDate: Date?

    public init(
        id: UUID = UUID(),
        bundleURL: URL,
        appName: String,
        bundleIdentifier: String,
        version: String,
        buildNumber: String? = nil,
        architecture: AppArchitecture = .unknown,
        teamIdentifier: String? = nil,
        icon: NSImage = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"),
        isSystemApp: Bool = false,
        isRunning: Bool = false,
        bundleSize: Int64 = 0,
        associatedItems: [AssociatedFileItem] = [],
        lastModifiedDate: Date? = nil
    ) {
        self.id = id
        self.bundleURL = bundleURL
        self.path = bundleURL.path
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.buildNumber = buildNumber
        self.architecture = architecture
        self.teamIdentifier = teamIdentifier
        self.icon = icon
        self.isSystemApp = isSystemApp
        self.isRunning = isRunning
        self.bundleSize = bundleSize
        self.associatedItems = associatedItems
        self.lastModifiedDate = lastModifiedDate
    }

    public var totalSelectedSizeBytes: Int64 {
        var total = bundleSize
        for item in associatedItems where item.isSelected {
            total += item.sizeBytes
        }
        return total
    }

    public var formattedTotalSelectedSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSelectedSizeBytes, countStyle: .file)
    }

    public var formattedBundleSize: String {
        return ByteCountFormatter.string(fromByteCount: bundleSize, countStyle: .file)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    public static func == (lhs: CleanableApp, rhs: CleanableApp) -> Bool {
        return lhs.path == rhs.path
    }
}
