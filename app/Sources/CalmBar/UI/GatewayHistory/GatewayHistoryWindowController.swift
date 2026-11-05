import AppKit
import SwiftUI

// MARK: - 请求历史独立窗口（FR-08）

@MainActor
public final class GatewayHistoryWindowController: NSObject, NSWindowDelegate {
    public static let shared = GatewayHistoryWindowController()

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

        let contentSize = NSSize(width: 1120, height: 680)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "CalmBar AI 网关 · 请求历史"
        win.minSize = NSSize(width: 900, height: 520)
        win.center()
        let host = NSHostingController(rootView: GatewayHistoryView())
        // 交给窗口决定尺寸：否则 hosting 控制器会按 SwiftUI 首帧的拟合高度回写窗口，导致上下内容被裁切
        host.sizingOptions = []
        win.contentViewController = host
        win.setContentSize(contentSize)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
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
