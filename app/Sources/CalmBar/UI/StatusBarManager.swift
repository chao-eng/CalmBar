import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusBarManager: ObservableObject {
    public static let shared = StatusBarManager()

    @Published public var selectedSettingsTab: SettingsTab = .thermal

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupStatusItem()
        setupPopover()
        setupObservers()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "wind", accessibilityDescription: "CalmBar")
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "CalmBar 全能菜单栏增强 (左键打开面板，右键偏好设置)"
        }
        item.autosaveName = "calmbar_main"
        item.isVisible = true
        self.statusItem = item
        updateStatusItemTitle()
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 380)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(openSettingsAction: { [weak self] tab in
                self?.openSettingsWindow(tab: tab)
            })
        )
        self.popover = popover
    }

    private func setupObservers() {
        ThermalMonitor.shared.$primaryTemp
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)

        AppSettings.shared.$showTempInMenuBar
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        let showTemp = AppSettings.shared.showTempInMenuBar
        let temp = Int(ThermalMonitor.shared.primaryTemp)

        if showTemp && temp > 0 {
            button.title = " \(temp)°"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }

        let currentEvent = NSApp.currentEvent
        if currentEvent?.type == .rightMouseUp {
            openSettingsWindow()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    public func closePopover() {
        popover?.performClose(nil)
    }

    public func openSettingsWindow(tab: SettingsTab = .thermal) {
        self.selectedSettingsTab = tab
        closePopover()

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "CalmBar 偏好设置"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }
}
