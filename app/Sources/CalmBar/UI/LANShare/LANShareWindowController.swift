import AppKit
import SwiftUI

// MARK: - 局域网互传独立窗口

@MainActor
public final class LANShareWindowController: NSObject, NSWindowDelegate {
    public static let shared = LANShareWindowController()

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

        let contentSize = NSSize(width: 780, height: 660)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "CalmBar 局域网互传"
        win.minSize = NSSize(width: 700, height: 560)
        win.center()
        let host = NSHostingController(rootView: LANShareWindowView())
        // 交给窗口决定尺寸，避免首帧拟合高度回写导致内容裁切
        host.sizingOptions = []
        win.contentViewController = host
        win.setContentSize(contentSize)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
        LANShareService.shared.revalidateItems()
    }

    public func close() {
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        if let win = window, (notification.object as? NSWindow) === win {
            self.window = nil
        }
    }
}
