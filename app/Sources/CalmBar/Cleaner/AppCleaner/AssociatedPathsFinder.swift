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

                let match = Self.matchName(
                    itemLower: itemLower,
                    normalizedItem: normItem,
                    bundleId: bundleId,
                    normalizedBundleId: normBundleId,
                    normalizedLastTwo: normLastTwo,
                    normalizedAppName: normAppName,
                    normalizedStrippedName: normStrippedName,
                    normalizedPathName: normPathName,
                    sensitivity: sensitivity
                )

                if match.matches {
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
                        // 只有 bundle id / 精确名称命中的条目默认勾选；启发式匹配交给用户确认。
                        isSelected: match.isConfident,
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

    struct AssociatedNameMatch: Equatable {
        let matches: Bool
        let isConfident: Bool
    }

    /// 判断某个 Library 条目是否属于目标应用。`isConfident` 为 true 时才会默认勾选，
    /// 避免宽泛的前缀/后缀匹配把无关文件带进卸载列表。
    static func matchName(itemLower: String,
                          normalizedItem: String,
                          bundleId: String,
                          normalizedBundleId: String,
                          normalizedLastTwo: String,
                          normalizedAppName: String,
                          normalizedStrippedName: String,
                          normalizedPathName: String,
                          sensitivity: SearchSensitivityLevel) -> AssociatedNameMatch {
        // 1. bundle id 精确匹配，或完整 bundle id 出现在名称中
        if itemLower == bundleId || normalizedItem == normalizedBundleId || itemLower.contains(bundleId) {
            return AssociatedNameMatch(matches: true, isConfident: true)
        }

        // 2. 应用显示名 / 去掉版本号后的名称 / 应用文件名精确匹配
        if normalizedItem == normalizedAppName
            || normalizedItem == normalizedStrippedName
            || normalizedItem == normalizedPathName {
            return AssociatedNameMatch(matches: true, isConfident: true)
        }

        guard sensitivity != .strict else {
            return AssociatedNameMatch(matches: false, isConfident: false)
        }

        // 3. bundle id 最后两段精确匹配（例如 spotifyclient），仍需用户确认
        if !normalizedLastTwo.isEmpty, normalizedItem == normalizedLastTwo {
            return AssociatedNameMatch(matches: true, isConfident: false)
        }

        // 4. 只有深度模式才允许名称前缀/后缀匹配，且不默认勾选
        if sensitivity == .deep,
           normalizedAppName.count >= 4,
           normalizedItem.hasPrefix(normalizedAppName) || normalizedItem.hasSuffix(normalizedAppName) {
            return AssociatedNameMatch(matches: true, isConfident: false)
        }

        return AssociatedNameMatch(matches: false, isConfident: false)
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
