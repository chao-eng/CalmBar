import AppKit
import SwiftUI

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
    private var eventMonitor: Any?

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

        if let existing = window {
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            setupEventMonitor()
            return
        }

        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
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

        let view = CommandPaletteView(onDismiss: { [weak self] in
            self?.hideWindow()
        })
        panel.contentViewController = NSHostingController(rootView: view)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = panel
        setupEventMonitor()
    }

    public func hideWindow() {
        removeEventMonitor()
        window?.orderOut(nil)
    }

    private func setupEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = self.window, window.isVisible else {
                return event
            }

            // KeyCode 53 = ESC
            if event.keyCode == 53 {
                self.hideWindow()
                return nil
            }

            // KeyCode 125 = Arrow Down
            if event.keyCode == 125 {
                NotificationCenter.default.post(name: .commandPaletteNext, object: nil)
                return nil
            }

            // KeyCode 126 = Arrow Up
            if event.keyCode == 126 {
                NotificationCenter.default.post(name: .commandPalettePrevious, object: nil)
                return nil
            }

            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
