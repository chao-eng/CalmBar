import Foundation
import AppKit

public final class AppScanner: @unchecked Sendable {
    public static let shared = AppScanner()

    private let fileManager = FileManager.default

    public init() {}

    /// Scan installed applications from all standard roots
    public func scanInstalledApps() async -> [CleanableApp] {
        let roots = AppCleanerLocations.shared.appScanRoots
        var appURLs: [URL] = []

        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard fileManager.fileExists(atPath: root) else { continue }

            if let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "app" {
                        appURLs.append(fileURL)
                    }
                }
            }
        }

        // Deduplicate URLs
        let uniqueURLs = Array(Set(appURLs))

        // Parallel processing of AppInfo
        var apps: [CleanableApp] = []
        await withTaskGroup(of: CleanableApp?.self) { group in
            for url in uniqueURLs {
                group.addTask(priority: .userInitiated) {
                    return self.parseApp(at: url)
                }
            }

            for await result in group {
                if let app = result {
                    apps.append(app)
                }
            }
        }

        // Default sort by name
        return apps.sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }

    /// Parse single app bundle at URL
    public func parseApp(at url: URL) -> CleanableApp? {
        guard let bundle = Bundle(url: url) else { return nil }

        let info = bundle.infoDictionary ?? (NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]) ?? [:]
        
        let bundleIdentifier = bundle.bundleIdentifier ?? (info["CFBundleIdentifier"] as? String) ?? ""
        guard !bundleIdentifier.isEmpty else { return nil }

        // Ignore CalmBar itself
        if bundleIdentifier == "com.chaoeng.CalmBar" || bundleIdentifier == "com.chao.CalmBar" {
            return nil
        }

        let displayName = (info["CFBundleDisplayName"] as? String) ??
                          (info["CFBundleName"] as? String) ??
                          url.deletingPathExtension().lastPathComponent

        let version = (info["CFBundleShortVersionString"] as? String) ??
                      (info["CFBundleVersion"] as? String) ?? "1.0"
        let buildNumber = info["CFBundleVersion"] as? String

        let isSystemApp = url.path.hasPrefix("/System/") || url.path.hasPrefix("/System/Applications")
        let architecture = detectArchitecture(bundle: bundle, appURL: url)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let size = calculateSize(at: url)

        // Running status
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier || $0.bundleURL?.path == url.path
        }

        let lastModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return CleanableApp(
            bundleURL: url,
            appName: displayName,
            bundleIdentifier: bundleIdentifier,
            version: version,
            buildNumber: buildNumber,
            architecture: architecture,
            teamIdentifier: nil,
            icon: icon,
            isSystemApp: isSystemApp,
            isRunning: isRunning,
            bundleSize: size,
            associatedItems: [],
            lastModifiedDate: lastModified
        )
    }

    /// Detect architecture from Mach-O headers or NSBundle executableArchitectures
    public func detectArchitecture(bundle: Bundle, appURL: URL) -> AppArchitecture {
        guard let archs = bundle.executableArchitectures?.map({ $0.intValue }) else {
            return .unknown
        }

        let CPU_TYPE_X86_64 = 0x01000007 // 16777223
        let CPU_TYPE_ARM64 = 0x0100000C  // 16777228

        let hasARM = archs.contains(CPU_TYPE_ARM64)
        let hasX86 = archs.contains(CPU_TYPE_X86_64)

        if hasARM && hasX86 {
            return .universal
        } else if hasARM {
            return .appleSilicon
        } else if hasX86 {
            return .intel
        }
        return .unknown
    }

    /// Fast directory size calculation
    public func calculateSize(at url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey],
            options: []
        ) else { return 0 }

        var totalSize: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory, !isDirectory else {
                continue
            }
            totalSize += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? resourceValues.fileSize ?? 0)
        }
        return totalSize
    }
}
