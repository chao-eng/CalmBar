import Foundation

public final class DevCacheScanner: @unchecked Sendable {
    public static let shared = DevCacheScanner()

    private let fileManager = FileManager.default

    public init() {}

    /// Scan all categories and return list of DevPathItems
    public func scanCategories(_ categories: [DevCategory]) async -> [DevPathItem] {
        var items: [DevPathItem] = []

        await withTaskGroup(of: [DevPathItem].self) { group in
            for category in categories {
                group.addTask(priority: .userInitiated) {
                    var categoryItems: [DevPathItem] = []
                    for pattern in category.paths {
                        let matches = self.resolvePattern(pattern, envName: category.name)
                        categoryItems.append(contentsOf: matches)
                    }
                    return categoryItems
                }
            }

            for await result in group {
                items.append(contentsOf: result)
            }
        }

        return items.filter { $0.exists && !$0.isEmpty }
    }

    /// Resolve wildcard patterns like ~/Library/Application Support/Google/AndroidStudio*/
    public func resolvePattern(_ pattern: String, envName: String) -> [DevPathItem] {
        let expanded = NSString(string: pattern).expandingTildeInPath

        if pattern.contains("*") {
            let components = expanded.components(separatedBy: "*")
            guard let basePath = components.first else { return [] }
            let parentDir = (basePath as NSString).deletingLastPathComponent
            let prefix = (basePath as NSString).lastPathComponent

            guard fileManager.fileExists(atPath: parentDir),
                  let contents = try? fileManager.contentsOfDirectory(atPath: parentDir) else {
                return []
            }

            var results: [DevPathItem] = []
            for item in contents where item.hasPrefix(prefix) {
                let fullPath = (parentDir as NSString).appendingPathComponent(item)
                let itemObj = inspectPath(fullPath, originalPattern: pattern, envName: envName)
                if itemObj.exists {
                    results.append(itemObj)
                }
            }
            return results
        } else {
            let itemObj = inspectPath(expanded, originalPattern: pattern, envName: envName)
            return itemObj.exists ? [itemObj] : []
        }
    }

    /// Check existence, emptiness and size
    public func inspectPath(_ path: String, originalPattern: String, envName: String) -> DevPathItem {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
            return DevPathItem(envName: envName, originalPattern: originalPattern, expandedPath: path, exists: false, isEmpty: true, sizeBytes: 0)
        }

        var isEmpty = false
        if isDir.boolValue {
            if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
                let filtered = contents.filter { $0 != ".DS_Store" }
                isEmpty = filtered.isEmpty
            }
        }

        let url = URL(fileURLWithPath: path)
        let size = AppScanner.shared.calculateSize(at: url)

        return DevPathItem(
            envName: envName,
            originalPattern: originalPattern,
            expandedPath: path,
            exists: true,
            isEmpty: isEmpty,
            sizeBytes: size,
            isSelected: true
        )
    }

    /// Clear inner contents of a folder silently without asking password
    public func clearFolderContents(at path: String) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return false }
        var allSuccess = true

        for item in contents {
            let itemPath = (path as NSString).appendingPathComponent(item)
            let itemURL = URL(fileURLWithPath: itemPath)
            do {
                try fileManager.removeItem(at: itemURL)
            } catch {
                do {
                    try fileManager.trashItem(at: itemURL, resultingItemURL: nil)
                } catch {
                    allSuccess = false
                }
            }
        }
        return allSuccess
    }

    /// Trash or remove the entire path silently
    public func trashPath(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            do {
                try fileManager.removeItem(at: url)
                return true
            } catch {
                return false
            }
        }
    }
}
