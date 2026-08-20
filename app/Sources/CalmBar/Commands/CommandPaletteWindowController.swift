import AppKit
import SwiftUI
import CommandPaletteKit

private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        CommandPaletteWindowController.shared.hideWindow()
    }
}

@MainActor
public final class CommandPaletteWindowController {
    public static let shared = CommandPaletteWindowController()

    private var window: NSPanel?

    private init() {}

    public func toggle() {
        if let window = window, window.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    public func showWindow() {
        StatusBarManager.shared.closePopover()

        let view = CommandPaletteView(onDismiss: { [weak self] in
            self?.hideWindow()
        })
        .id(UUID())

        let hostingController = NSHostingController(rootView: view)

        if let existing = window {
            existing.contentViewController = hostingController
            positionWindowInUpperCenter(existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = hostingController

        positionWindowInUpperCenter(panel)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = panel
    }

    public func hideWindow() {
        window?.orderOut(nil)
        window?.contentViewController = nil
    }

    /// 将命令面板定位在屏幕水平严格居中、垂直靠近上半部分（Spotlight / Raycast 黄金视觉高度）
    private func positionWindowInUpperCenter(_ window: NSWindow) {
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen = targetScreen else {
            window.center()
            return
        }

        let panelWidth: CGFloat = 580
        let panelHeight: CGFloat = 420
        let screenFrame = screen.visibleFrame

        // 1. 水平严格居中 (相对于当前屏幕可见区域)
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2.0

        // 2. 垂直靠上半部分：在 macOS 坐标系中（原点在屏幕左下角），
        // 顶部距离屏幕可见区域顶边缘约 18% 屏幕高度
        let targetTopY = screenFrame.origin.y + screenFrame.height - (screenFrame.height * 0.18)
        let y = targetTopY - panelHeight

        let targetRect = NSRect(
            x: round(x),
            y: round(max(screenFrame.origin.y, y)),
            width: panelWidth,
            height: panelHeight
        )

        window.setFrame(targetRect, display: true, animate: false)
    }
}
