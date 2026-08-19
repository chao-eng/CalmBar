import Foundation
import SwiftUI
import AppKit

@MainActor
public final class CleanerManager: ObservableObject {
    public static let shared = CleanerManager()

    // MARK: - App Cleaner State
    @Published public var apps: [CleanableApp] = []
    @Published public var selectedApp: CleanableApp?
    @Published public var isScanningApps: Bool = false
    @Published public var isScanningAssociated: Bool = false
    @Published public var appSearchQuery: String = ""
    @Published public var appSortOption: AppSortOption = .size
    @Published public var sensitivityLevel: SearchSensitivityLevel = .balanced
    @Published public var trashedAppNotice: CleanableApp?

    // MARK: - Developer Cleaner State
    @Published public var devCategories: [DevCategory] = []
    @Published public var devPathItems: [DevPathItem] = []
    @Published public var isScanningDev: Bool = false
    @Published public var devSearchQuery: String = ""

    // Orphaned Workspaces
    @Published public var orphanedWorkspaces: [OrphanedWorkspaceItem] = []
    @Published public var isScanningWorkspaces: Bool = false

    // Pip Packages
    @Published public var pipPackages: [PipPackageItem] = []
    @Published public var pythonPath: String = "/usr/bin/python3"
    @Published public var isScanningPip: Bool = false

    // Total counts / sizes
    public var totalDevCacheSizeBytes: Int64 {
        devPathItems.reduce(0) { $0 + $1.sizeBytes }
    }

    public var formattedTotalDevCacheSize: String {
        ByteCountFormatter.string(fromByteCount: totalDevCacheSizeBytes, countStyle: .file)
    }

    public var totalOrphanedSizeBytes: Int64 {
        orphanedWorkspaces.reduce(0) { $0 + $1.sizeBytes }
    }

    public var formattedTotalOrphanedSize: String {
        ByteCountFormatter.string(fromByteCount: totalOrphanedSizeBytes, countStyle: .file)
    }

    private init() {
        self.devCategories = DevPathLibrary.getCategories()
    }

    // MARK: - App Cleaner Actions

    public func refreshAllApps() {
        guard !isScanningApps else { return }
        isScanningApps = true

        Task {
            let scanned = await AppScanner.shared.scanInstalledApps()
            await MainActor.run {
                self.apps = scanned
                self.isScanningApps = false
                if let first = self.filteredApps.first, self.selectedApp == nil {
                    self.selectApp(first)
                }
            }
        }
    }

    public func selectApp(_ app: CleanableApp) {
        self.selectedApp = app
        scanAssociatedFiles(for: app)
    }

    public func scanAssociatedFiles(for app: CleanableApp) {
        isScanningAssociated = true
        Task {
            let items = await AssociatedPathsFinder.shared.findAssociatedItems(for: app, sensitivity: self.sensitivityLevel)
            await MainActor.run {
                if self.selectedApp?.id == app.id {
                    self.selectedApp?.associatedItems = items
                }
                if let idx = self.apps.firstIndex(where: { $0.id == app.id }) {
                    self.apps[idx].associatedItems = items
                }
                self.isScanningAssociated = false
            }
        }
    }

    public func cleanMissingApps() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.apps.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
            if let selected = self.selectedApp, !FileManager.default.fileExists(atPath: selected.path) {
                self.selectedApp = self.filteredApps.first
                if let next = self.selectedApp {
                    self.scanAssociatedFiles(for: next)
                }
            }
        }
    }

    public func handleDroppedApp(url: URL) {
        cleanMissingApps()
        guard let app = AppScanner.shared.parseApp(at: url) else { return }
        
        let isInTrash = url.path.contains("/.Trash")
        withAnimation(.easeInOut(duration: 0.2)) {
            // Only add to installed apps list if NOT located in Trash
            if !isInTrash {
                if let existingIdx = apps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                    self.apps[existingIdx] = app
                } else {
                    self.apps.insert(app, at: 0)
                }
            }
            self.selectApp(app)
        }
    }

    public func uninstallApp(_ app: CleanableApp, deleteAppBundle: Bool = true) async -> (success: Bool, message: String) {
        let (successCount, failed) = await AppUninstaller.shared.uninstallApp(app: app, deleteAppBundle: deleteAppBundle)
        
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.apps.removeAll { $0.id == app.id || $0.bundleIdentifier == app.bundleIdentifier || !FileManager.default.fileExists(atPath: $0.path) }
                if self.selectedApp?.id == app.id || self.selectedApp?.bundleIdentifier == app.bundleIdentifier {
                    self.selectedApp = self.filteredApps.first
                    if let next = self.selectedApp {
                        self.scanAssociatedFiles(for: next)
                    }
                }
            }
        }

        if failed.isEmpty {
            return (true, "已成功将 \(successCount) 项关联文件移入废纸篓")
        } else {
            return (false, "部分文件未能移入废纸篓 (\(failed.count) 项)")
        }
    }

    public var filteredApps: [CleanableApp] {
        var list = apps
        if !appSearchQuery.isEmpty {
            let query = appSearchQuery.lowercased()
            list = list.filter {
                $0.appName.lowercased().contains(query) ||
                $0.bundleIdentifier.lowercased().contains(query)
            }
        }

        switch appSortOption {
        case .name:
            return list.sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
        case .size:
            return list.sorted { $0.bundleSize > $1.bundleSize }
        case .dateModified:
            return list.sorted { ($0.lastModifiedDate ?? Date.distantPast) > ($1.lastModifiedDate ?? Date.distantPast) }
        case .arch:
            return list.sorted { $0.architecture.rawValue < $1.architecture.rawValue }
        }
    }

    // MARK: - Developer Cleaner Actions

    public func refreshDevCaches() {
        guard !isScanningDev else { return }
        isScanningDev = true

        Task {
            let items = await DevCacheScanner.shared.scanCategories(self.devCategories)
            await MainActor.run {
                self.devPathItems = items
                self.isScanningDev = false
            }
        }
    }

    public func clearDevPathContents(_ item: DevPathItem) {
        let success = DevCacheScanner.shared.clearFolderContents(at: item.expandedPath)
        if success {
            if let idx = devPathItems.firstIndex(where: { $0.id == item.id }) {
                devPathItems[idx].sizeBytes = 0
                devPathItems[idx].isEmpty = true
            }
        }
    }

    public func trashDevPath(_ item: DevPathItem) {
        let success = DevCacheScanner.shared.trashPath(at: item.expandedPath)
        if success {
            devPathItems.removeAll { $0.id == item.id }
        }
    }

    // MARK: - Orphaned Workspaces Actions

    public func refreshOrphanedWorkspaces() {
        guard !isScanningWorkspaces else { return }
        isScanningWorkspaces = true

        Task {
            let items = await OrphanedWorkspaceFinder.shared.scanOrphanedWorkspaces()
            await MainActor.run {
                self.orphanedWorkspaces = items
                self.isScanningWorkspaces = false
            }
        }
    }

    public func cleanOrphanedWorkspace(_ item: OrphanedWorkspaceItem) {
        if OrphanedWorkspaceFinder.shared.deleteWorkspace(item) {
            orphanedWorkspaces.removeAll { $0.id == item.id }
        }
    }

    public func cleanAllOrphanedWorkspaces() {
        _ = OrphanedWorkspaceFinder.shared.deleteWorkspaces(orphanedWorkspaces)
        orphanedWorkspaces.removeAll()
    }

    // MARK: - Pip Package Actions

    public func refreshPipPackages() {
        guard !isScanningPip else { return }
        isScanningPip = true

        Task {
            let detected = await PipPackageManager.shared.detectPythonPath()
            let packages = await PipPackageManager.shared.listPackages(pythonPath: detected)
            await MainActor.run {
                self.pythonPath = detected
                self.pipPackages = packages
                self.isScanningPip = false
            }
        }
    }

    public func uninstallPipPackage(_ pkg: PipPackageItem) async -> Bool {
        let success = await PipPackageManager.shared.uninstallPackage(name: pkg.name, pythonPath: self.pythonPath)
        if success {
            await MainActor.run {
                self.pipPackages.removeAll { $0.id == pkg.id }
            }
        }
        return success
    }
}
