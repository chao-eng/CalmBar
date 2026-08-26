import AppKit
import SwiftUI

@MainActor
public final class ClipboardHistoryWindowController: NSObject, NSWindowDelegate {
    public static let shared = ClipboardHistoryWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "CalmBar 剪贴板历史记录"
        win.minSize = NSSize(width: 480, height: 420)
        win.center()
        win.contentViewController = NSHostingController(rootView: ClipboardHistoryView())
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    public func toggle() {
        if let existing = window, existing.isVisible {
            close()
        } else {
            show()
        }
    }

    public func close() {
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate

    public func windowDidResignKey(_ notification: Notification) {
        guard AppSettings.shared.clipboardHideOnBlur else { return }
        guard let win = window, (notification.object as? NSWindow) === win else { return }
        if win.attachedSheet != nil { return }
        close()
    }

    public func windowWillClose(_ notification: Notification) {
        if let win = window, (notification.object as? NSWindow) === win {
            self.window = nil
        }
    }
}
