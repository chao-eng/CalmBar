import AppKit
import SwiftUI

@MainActor
public final class CleanerWindowController {
    public static let shared = CleanerWindowController()

    private var window: NSWindow?

    private init() {}

    public func show() {
        CleanerManager.shared.cleanMissingApps()
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "CalmBar 卸载与深度清理"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.minSize = NSSize(width: 740, height: 500)
        win.center()
        win.contentViewController = NSHostingController(rootView: CleanerMainContainerView())
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win

        // Trigger initial background scans
        CleanerManager.shared.refreshAllApps()
        CleanerManager.shared.refreshDevCaches()
        CleanerManager.shared.refreshOrphanedWorkspaces()
    }

    public func close() {
        window?.close()
        window = nil
    }
}
