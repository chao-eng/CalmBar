import Foundation

@MainActor
public final class LaunchBackupService {
    public static let shared = LaunchBackupService()
    public let backupDirectory: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.backupDirectory = appSupport.appendingPathComponent("CalmBar/Backups/Launch", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        pruneOldBackups(days: 30)
    }

    /// 在操作前执行快照备份
    public func createBackup(of plistURL: URL, label: String, scope: LaunchScope? = nil) throws -> URL {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw LaunchServiceError.fileNotFound(plistURL.path)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        // 文件名携带原始作用域，便于还原回正确目录；无作用域时保持旧命名格式
        let backupFileName: String
        if let scope {
            backupFileName = "\(timestamp)_\(scope.rawValue)_\(label).plist"
        } else {
            backupFileName = "\(timestamp)_\(label).plist"
        }
        let destURL = backupDirectory.appendingPathComponent(backupFileName)

        try FileManager.default.copyItem(at: plistURL, to: destURL)
        return destURL
    }

    /// 还原指定备份
    public func restoreBackup(_ backupURL: URL, to targetURL: URL, scope: LaunchScope) async throws {
        if scope.requiresPrivilegeForFile {
            let escapedSrc = LaunchPrivilegeService.escapeShellArg(backupURL.path)
            let escapedDst = LaunchPrivilegeService.escapeShellArg(targetURL.path)
            let cmd = "cp -f \(escapedSrc) \(escapedDst)"
            try await LaunchPrivilegeService.shared.runPrivileged(cmd)
        } else {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: backupURL, to: targetURL)
        }
    }

    /// 列出所有备份
    public func listBackups() -> [LaunchBackupItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files.filter { $0.pathExtension == "plist" }.compactMap { url in
            let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = resourceValues?.contentModificationDate ?? Date()
            let size = Int64(resourceValues?.fileSize ?? 0)

            let filename = url.deletingPathExtension().lastPathComponent
            // 新格式: yyyyMMdd_HHmmss_scope_label；旧格式: yyyyMMdd_HHmmss_label
            let parts = filename.components(separatedBy: "_")
            var originalScope: LaunchScope? = nil
            var label = filename
            if parts.count >= 4, let scope = LaunchScope(rawValue: parts[2]) {
                originalScope = scope
                label = parts.dropFirst(3).joined(separator: "_")
            } else if parts.count >= 3 {
                label = parts.dropFirst(2).joined(separator: "_")
            }

            return LaunchBackupItem(
                label: label,
                fileURL: url,
                creationDate: date,
                originalScope: originalScope,
                fileSize: size
            )
        }.sorted { $0.creationDate > $1.creationDate }
    }

    /// 删除特定备份
    public func deleteBackup(_ backupURL: URL) throws {
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
    }

    /// 自动清理 30 天前的旧备份
    public func pruneOldBackups(days: Int = 30) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoffDate = Date().addingTimeInterval(-Double(days) * 86400)
        for url in files {
            if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date < cutoffDate {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
