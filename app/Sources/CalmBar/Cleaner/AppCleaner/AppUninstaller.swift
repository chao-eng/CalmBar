import Foundation
import AppKit

public final class AppUninstaller: @unchecked Sendable {
    public static let shared = AppUninstaller()

    private let fileManager = FileManager.default

    public init() {}

    /// Quit or kill application if it is currently running
    public func terminateApp(bundleIdentifier: String, force: Bool = false) async -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier
        }

        guard !runningApps.isEmpty else { return true }

        for app in runningApps {
            if force {
                app.forceTerminate()
            } else {
                app.terminate()
            }
        }

        // Wait up to 2 seconds for app to exit
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let stillRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == bundleIdentifier
            }
            if !stillRunning { return true }
        }

        if !force {
            return await terminateApp(bundleIdentifier: bundleIdentifier, force: true)
        }
        return false
    }

    /// Safely move items to trash silently without password prompts
    public func uninstallApp(app: CleanableApp, deleteAppBundle: Bool = true) async -> (successCount: Int, failedPaths: [String]) {
        // 1. Terminate running instance first
        _ = await terminateApp(bundleIdentifier: app.bundleIdentifier)

        var successCount = 0
        var failedPaths: [String] = []

        var targets: [URL] = []
        if deleteAppBundle {
            targets.append(app.bundleURL)
        }
        for item in app.associatedItems where item.isSelected {
            targets.append(item.url)
        }

        // 2. Perform silent trash/deletion
        for url in targets {
            guard fileManager.fileExists(atPath: url.path) else {
                successCount += 1
                continue
            }

            if trashSingleItem(url: url) {
                successCount += 1
            } else {
                // Double check if file was actually removed
                if !fileManager.fileExists(atPath: url.path) {
                    successCount += 1
                } else {
                    failedPaths.append(url.path)
                }
            }
        }

        return (successCount, failedPaths)
    }

    /// Multi-tiered completely silent trash/removal
    private func trashSingleItem(url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return true }

        // Tier 1: Try standard macOS trashItem
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            if !fileManager.fileExists(atPath: url.path) {
                return true
            }
        } catch {
            // Ignore error and continue to Tier 2
        }

        // Check again
        guard fileManager.fileExists(atPath: url.path) else { return true }

        // Tier 2: Direct move to ~/.Trash
        let trashDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        var destinationURL = trashDir.appendingPathComponent(url.lastPathComponent)

        var counter = 1
        while fileManager.fileExists(atPath: destinationURL.path) {
            let nameWithoutExt = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let newName = ext.isEmpty ? "\(nameWithoutExt)_\(counter)" : "\(nameWithoutExt)_\(counter).\(ext)"
            destinationURL = trashDir.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try fileManager.moveItem(at: url, to: destinationURL)
            if !fileManager.fileExists(atPath: url.path) {
                return true
            }
        } catch {
            // Ignore error and continue to Tier 3
        }

        // Check again
        guard fileManager.fileExists(atPath: url.path) else { return true }

        // Tier 3: Shell mv to ~/.Trash
        let mvProcess = Process()
        mvProcess.executableURL = URL(fileURLWithPath: "/bin/mv")
        mvProcess.arguments = [url.path, destinationURL.path]
        if let _ = try? mvProcess.run() {
            mvProcess.waitUntilExit()
            if !fileManager.fileExists(atPath: url.path) {
                return true
            }
        }

        // Tier 4: Direct removeItem
        do {
            try fileManager.removeItem(at: url)
            return !fileManager.fileExists(atPath: url.path)
        } catch {
            return !fileManager.fileExists(atPath: url.path)
        }
    }
}
