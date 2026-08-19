import Foundation

public final class AssociatedPathsFinder: @unchecked Sendable {
    public static let shared = AssociatedPathsFinder()

    private let fileManager = FileManager.default
    private let locations = AppCleanerLocations.shared

    public init() {}

    /// Normalize strings for comparison (remove non-alphanumerics, lowercased)
    public func normalize(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
        let lower = result.lowercased()
        return lower.isEmpty ? string.lowercased() : lower
    }

    /// Strip trailing version digits (e.g. "Bartender 5" -> "Bartender")
    public func stripTrailingDigits(_ string: String) -> String {
        return string.replacingOccurrences(
            of: #"\s+\d+(\.\d+)*\s*$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Find all associated leftover items for an app
    public func findAssociatedItems(for app: CleanableApp, sensitivity: SearchSensitivityLevel = .balanced) async -> [AssociatedFileItem] {
        var items: [AssociatedFileItem] = []

        // Bundle ID components
        let bundleId = app.bundleIdentifier.lowercased()
        let normBundleId = normalize(bundleId)
        let bundleComponents = bundleId.components(separatedBy: ".").filter { !$0.isEmpty }
        let lastTwoComponents = bundleComponents.suffix(2).joined()
        let normLastTwo = normalize(lastTwoComponents)

        // App name components
        let rawAppName = app.appName
        let normAppName = normalize(rawAppName)
        let strippedName = stripTrailingDigits(rawAppName)
        let normStrippedName = normalize(strippedName)

        // App file name without extension
        let pathName = app.bundleURL.deletingPathExtension().lastPathComponent
        let normPathName = normalize(pathName)

        // Search directory list
        let searchDirs = locations.librarySearchDirectories

        for (catType, dirPath) in searchDirs {
            guard fileManager.fileExists(atPath: dirPath) else { continue }

            guard let contents = try? fileManager.contentsOfDirectory(atPath: dirPath) else {
                continue
            }

            for item in contents {
                // Ignore .DS_Store
                if item == ".DS_Store" { continue }

                let itemLower = item.lowercased()
                let normItem = normalize(item)
                let itemPath = (dirPath as NSString).appendingPathComponent(item)
                let itemURL = URL(fileURLWithPath: itemPath)

                // Safety exclusion check
                if isExcluded(itemLower: itemLower, normItem: normItem, targetBundleId: bundleId) {
                    continue
                }

                var isMatch = false

                // 1. Exact bundle identifier match (e.g. com.apple.xxx or com.spotify.client)
                if itemLower == bundleId || normItem == normBundleId || normItem.hasPrefix(normBundleId) {
                    isMatch = true
                }
                // 2. Contains full bundle identifier in name
                else if itemLower.contains(bundleId) {
                    isMatch = true
                }
                // 3. Match app display name (normalized)
                else if normItem == normAppName || normItem == normStrippedName || normItem == normPathName {
                    isMatch = true
                }
                // 4. Sensitivity balanced / deep matches
                else if sensitivity != .strict {
                    // Match last two bundle components (e.g. spotifyclient)
                    if !normLastTwo.isEmpty && (normItem == normLastTwo || normItem.hasPrefix(normLastTwo)) {
                        isMatch = true
                    }
                    // Match app name prefix if name length >= 4
                    else if normAppName.count >= 4 && (normItem.hasPrefix(normAppName) || normItem.hasSuffix(normAppName)) {
                        isMatch = true
                    }
                }

                if isMatch {
                    // Avoid adding the main .app bundle as an associated item in this step
                    if itemPath == app.path {
                        continue
                    }

                    let size = AppScanner.shared.calculateSize(at: itemURL)
                    let isPrivileged = itemPath.hasPrefix("/Library/LaunchDaemons") ||
                                       itemPath.hasPrefix("/Library/PrivilegedHelperTools") ||
                                       !fileManager.isWritableFile(atPath: itemPath)

                    items.append(AssociatedFileItem(
                        url: itemURL,
                        category: catType,
                        sizeBytes: size,
                        isSelected: true,
                        isPrivileged: isPrivileged
                    ))
                }
            }
        }

        // Deduplicate items by path
        var uniqueDict: [String: AssociatedFileItem] = [:]
        for item in items {
            uniqueDict[item.path] = item
        }

        return Array(uniqueDict.values).sorted { $0.category.id < $1.category.id }
    }

    /// Check if item is in safety exclusion list
    private func isExcluded(itemLower: String, normItem: String, targetBundleId: String) -> Bool {
        if targetBundleId.hasPrefix("com.apple.") {
            // Do not clean Apple internal protected components
            return true
        }

        for excl in locations.systemExclusions {
            if normItem == excl || itemLower == excl {
                return true
            }
        }
        return false
    }
}
