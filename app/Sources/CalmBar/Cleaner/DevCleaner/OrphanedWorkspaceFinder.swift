import Foundation

public final class OrphanedWorkspaceFinder: @unchecked Sendable {
    public static let shared = OrphanedWorkspaceFinder()

    private let fileManager = FileManager.default

    public init() {}

    private let targetIDEs: [(name: String, storagePath: String)] = [
        ("VS Code", "~/Library/Application Support/Code/User/workspaceStorage"),
        ("Cursor", "~/Library/Application Support/Cursor/User/workspaceStorage"),
        ("VSCodium", "~/Library/Application Support/VSCodium/User/workspaceStorage")
    ]

    /// Scan all supported IDEs for orphaned workspace caches
    public func scanOrphanedWorkspaces() async -> [OrphanedWorkspaceItem] {
        var results: [OrphanedWorkspaceItem] = []

        for ide in targetIDEs {
            let expandedPath = NSString(string: ide.storagePath).expandingTildeInPath
            guard fileManager.fileExists(atPath: expandedPath),
                  let workspaceDirs = try? fileManager.contentsOfDirectory(atPath: expandedPath) else {
                continue
            }

            for dirName in workspaceDirs {
                if dirName == ".DS_Store" { continue }
                let workspacePath = (expandedPath as NSString).appendingPathComponent(dirName)
                let jsonPath = (workspacePath as NSString).appendingPathComponent("workspace.json")

                guard fileManager.fileExists(atPath: jsonPath),
                      let folderPath = extractProjectFolder(from: jsonPath) else {
                    continue
                }

                // If the project source directory no longer exists on disk, it's orphaned
                if !fileManager.fileExists(atPath: folderPath) {
                    let size = AppScanner.shared.calculateSize(at: URL(fileURLWithPath: workspacePath))
                    results.append(OrphanedWorkspaceItem(
                        ideName: ide.name,
                        workspaceName: dirName,
                        storagePath: workspacePath,
                        projectOriginalFolderPath: folderPath,
                        sizeBytes: size,
                        isSelected: true
                    ))
                }
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Extract project directory path from workspace.json
    private func extractProjectFolder(from jsonPath: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let folder = json["folder"] as? String else {
            return nil
        }

        var clean = folder.replacingOccurrences(of: "file://", with: "")
        clean = clean.removingPercentEncoding ?? clean
        clean = clean.replacingOccurrences(of: "+", with: " ")
        return clean
    }

    /// Delete specific orphaned workspace
    public func deleteWorkspace(_ workspace: OrphanedWorkspaceItem) -> Bool {
        let url = URL(fileURLWithPath: workspace.storagePath)
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            return false
        }
    }

    /// Delete multiple orphaned workspaces
    public func deleteWorkspaces(_ workspaces: [OrphanedWorkspaceItem]) -> Int {
        var count = 0
        for ws in workspaces {
            if deleteWorkspace(ws) {
                count += 1
            }
        }
        return count
    }
}
