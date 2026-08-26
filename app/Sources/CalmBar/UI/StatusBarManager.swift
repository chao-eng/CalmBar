import AppKit
import SwiftUI
import Combine

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        StatusBarManager.shared.closePopover()
    }
}

@MainActor
public final class StatusBarManager: ObservableObject {
    public static let shared = StatusBarManager()

    @Published public var selectedSettingsTab: SettingsTab = .thermal

    private var statusItem: NSStatusItem?
    private var panel: StatusPanel?
    private var settingsWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupStatusItem()
        setupPanel()
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

    private func setupPanel() {
        let panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        panel.contentViewController = NSHostingController(
            rootView: PopoverContentView(openSettingsAction: { [weak self] tab in
                self?.openSettingsWindow(tab: tab)
            })
        )
        self.panel = panel
    }

    private func setupObservers() {
        ThermalMonitor.shared.$primaryTemp
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)

        AppSettings.shared.$thermalEnabled
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
        let showTemp = AppSettings.shared.thermalEnabled && AppSettings.shared.showTempInMenuBar
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
        let currentEvent = NSApp.currentEvent
        if currentEvent?.type == .rightMouseUp {
            openSettingsWindow()
            return
        }

        if let panel = panel, panel.isVisible {
            closePopover()
        } else {
            showPopover()
        }
    }

    public func showPopover() {
        guard let button = statusItem?.button else { return }

        PermissionManager.shared.refreshAll()

        if panel == nil {
            setupPanel()
        }

        guard let panel = panel else { return }

        positionPanel(panel, relativeTo: button)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startMonitoring()
    }

    private func positionPanel(_ panel: NSPanel, relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.bounds)
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let fittingSize = panel.contentViewController?.view.fittingSize ?? NSSize(width: 320, height: 380)
        let panelWidth = max(320, fittingSize.width)
        let panelHeight = fittingSize.height > 50 ? fittingSize.height : 380

        var x = buttonRect.midX - (panelWidth / 2.0)
        if x + panelWidth > screenFrame.maxX - 8 {
            x = screenFrame.maxX - panelWidth - 8
        }
        if x < screenFrame.minX + 8 {
            x = screenFrame.minX + 8
        }

        let y = buttonRect.minY - panelHeight - 4
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }

    private func startMonitoring() {
        stopMonitoring()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.panel, panel.isVisible else { return }
            let mouseLocation = NSEvent.mouseLocation

            if panel.frame.contains(mouseLocation) {
                return
            }

            if let button = self.statusItem?.button, let buttonWindow = button.window {
                let buttonRect = buttonWindow.convertToScreen(button.bounds)
                if buttonRect.contains(mouseLocation) {
                    return
                }
            }

            self.closePopover()
        }
    }

    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    public func closePopover() {
        stopMonitoring()
        panel?.orderOut(nil)
    }

    public func openSettingsWindow(tab: SettingsTab = .thermal) {
        self.selectedSettingsTab = tab
        closePopover()

        if let window = settingsWindow, window.isVisible {
            positionWindowInUpperCenter(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let defaultWidth: CGFloat = 800
        let defaultHeight: CGFloat = 580

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = tab.titleZH
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 700, height: 500)
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false

        positionWindowInUpperCenter(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    public func updateSettingsWindowTitle(_ title: String) {
        settingsWindow?.title = title
    }

    /// 将偏好设置窗口定位在当前屏幕水平居中、垂直靠上半部分（与命令窗口位置完全一致：距离顶部 18% 屏幕高度）
    private func positionWindowInUpperCenter(_ window: NSWindow) {
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen = targetScreen else {
            window.center()
            return
        }

        let panelWidth: CGFloat = window.frame.width > 0 ? window.frame.width : 840
        let panelHeight: CGFloat = window.frame.height > 0 ? window.frame.height : 580
        let screenFrame = screen.visibleFrame

        // 1. 水平严格居中 (相对于当前屏幕可见区域)
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2.0

        // 2. 垂直靠上半部分：与命令窗口完全一致（顶部距离屏幕可见区域顶边缘 18% 屏幕高度）
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
