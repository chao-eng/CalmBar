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
            existing.center()
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
        panel.center()
        panel.contentViewController = hostingController

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = panel
    }

    public func hideWindow() {
        window?.orderOut(nil)
        window?.contentViewController = nil
    }
}
