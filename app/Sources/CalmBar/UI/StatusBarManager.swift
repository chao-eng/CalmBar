import AppKit
import SwiftUI
import Combine

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        StatusBarManager.shared.closePopover()
    }

    override func keyDown(with event: NSEvent) {
        if StatusBarManager.shared.handlePopoverKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        // 窗口高度恒为最大值，内容下方是透明区：点击该区域等价于点击面板外部
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            let activeHeight = PopoverTabRoute
                .route(for: StatusBarManager.shared.currentPopoverTab).totalHeight
            if event.locationInWindow.y < frame.height - activeHeight {
                StatusBarManager.shared.closePopover()
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
public final class StatusBarManager: ObservableObject {
    public static let shared = StatusBarManager()

    @Published public var selectedSettingsTab: SettingsTab = .thermal

    private var statusItem: NSStatusItem?
    private var panel: StatusPanel?
    private var popoverModel: PopoverPanelModel?
    private var settingsWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastMenuBarRefresh = Date.distantPast

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
            contentRect: NSRect(x: 0, y: 0, width: PopoverLayout.panelWidth, height: PopoverLayout.maxPanelHeight),
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

        let model = PopoverPanelModel()
        model.onTabChange = { [weak self] _ in
            // 窗口尺寸不变但内容高度变化，需让系统重算圆角卡片的投影
            self?.panel?.invalidateShadow()
        }
        popoverModel = model

        panel.contentViewController = NSHostingController(
            rootView: PopoverPanelView(
                model: model,
                openSettingsAction: { [weak self] tab in
                    self?.openSettingsWindow(tab: tab)
                },
                closePanel: { [weak self] in
                    self?.closePopover()
                }
            )
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

        AppSettings.shared.$systemMonitorEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarDemand(AppSettings.shared.menuBarReadoutItems)
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)

        AppSettings.shared.$menuBarReadoutItems
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.updateMenuBarDemand(items)
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)

        SystemMonitorService.shared.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleMenuBarRefresh()
            }
            .store(in: &cancellables)

        ScreenRecorderService.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)

        updateMenuBarDemand(AppSettings.shared.menuBarReadoutItems)
    }

    /// 菜单栏读数 3s 刷新一次，避免 1s 采样直接驱动状态栏
    private func scheduleMenuBarRefresh() {
        let now = Date()
        guard now.timeIntervalSince(lastMenuBarRefresh) >= 3 else { return }
        lastMenuBarRefresh = now
        updateStatusItemTitle()
    }

    private func updateMenuBarDemand(_ items: [String]) {
        let needsSample = AppSettings.shared.systemMonitorEnabled && items.contains { $0 != "temperature" }
        SystemMonitorService.shared.setMenuBarDemand(needsSample)
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        let settings = AppSettings.shared
        let baseTitle = MenuBarReadout.title(
            sample: SystemMonitorService.shared.snapshot,
            temperature: Double(ThermalMonitor.shared.primaryTemp),
            thermalEnabled: settings.thermalEnabled,
            items: settings.menuBarReadoutItems,
            monitorEnabled: settings.systemMonitorEnabled
        )

        // 录制进行中：在菜单栏读数前叠加红点，无读数时直接显示「录制中」
        let recording = ScreenRecorderService.shared.state.isActive
        let title = recording ? "● \(baseTitle.isEmpty ? "录制中" : baseTitle)" : baseTitle
        button.title = title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
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

        // 命令面板与控制中心面板互斥：打开一方先收起另一方
        CommandPaletteWindowController.shared.hideWindow()

        PermissionManager.shared.refreshAll()

        if panel == nil {
            setupPanel()
        }

        guard let panel = panel else { return }

        // BR-04：分区先按持久化值恢复，再做任何异步刷新
        popoverModel?.syncWithPersistedSelection()

        SystemMonitorService.shared.acquire(.panel)

        let height = PopoverLayout.maxPanelHeight
        positionPanel(panel, relativeTo: button, height: height)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startMonitoring()
    }

    private func positionPanel(_ panel: NSPanel, relativeTo button: NSStatusBarButton, height: CGFloat) {
        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.bounds)
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // BR-01 / BR-03：宽度与高度均由路由常量表驱动，不使用 fittingSize
        let panelWidth = PopoverLayout.panelWidth
        let panelHeight = height

        var x = buttonRect.midX - (panelWidth / 2.0)
        if x + panelWidth > screenFrame.maxX - 8 {
            x = screenFrame.maxX - panelWidth - 8
        }
        if x < screenFrame.minX + 8 {
            x = screenFrame.minX + 8
        }

        // BR-02：面板顶边恒等于状态栏按钮下沿 - 4pt
        let y = buttonRect.minY - panelHeight - 4
        let frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        panel.setFrame(frame, display: true)
    }

    // MARK: - 分区切换与高度动画（顶边不变量）

    /// 当前面板分区（无面板时回退温控）
    var currentPopoverTab: PopoverTab {
        popoverModel?.currentTab ?? .thermal
    }

    /// 供隔离回归使用的面板窗口
    var popoverWindow: NSWindow? {
        panel
    }

    @discardableResult
    func selectPopoverTab(_ tab: PopoverTab) -> Bool {
        popoverModel?.select(tab) ?? false
    }

    /// 键盘映射：⌘1–⌘6 固定顺序，←/→ 环内移动；未启用分区不响应（BR-10）
    func handlePopoverKey(_ event: NSEvent) -> Bool {
        guard let model = popoverModel else { return false }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let index = Int(characters) {
            return model.selectByShortcutIndex(index - 1)
        }

        switch event.keyCode {
        case 116, 121, 115, 119:
            return scrollPopover(keyCode: event.keyCode)
        case 123:
            return model.move(by: -1)
        case 124:
            return model.move(by: 1)
        default:
            return false
        }
    }

    /// PageUp / PageDown / Home / End：滚动当前分区的长内容，不切换分区
    private func scrollPopover(keyCode: UInt16) -> Bool {
        guard let panel, let scrollView = firstScrollView(in: panel.contentView) else { return true }
        guard let documentView = scrollView.documentView else { return true }

        let viewHeight = scrollView.contentView.bounds.height
        let maxOffset = max(0, documentView.bounds.height - viewHeight)
        let current = scrollView.contentView.bounds.origin.y
        let target: CGFloat
        switch keyCode {
        case 116: target = current - viewHeight
        case 121: target = current + viewHeight
        case 115: target = 0
        case 119: target = maxOffset
        default: return false
        }

        let clamped = min(max(target, 0), maxOffset)
        guard abs(clamped - current) > 0.5 else { return true }
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: clamped))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }

    private func firstScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    private func startMonitoring() {
        stopMonitoring()
        // 无人值守 M8/视觉验收回归期间不启用外部点击关闭，避免幽灵点击打断用例
        guard !CommandLine.arguments.contains("--m8"), !CommandLine.arguments.contains("--visual") else { return }
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
        SystemMonitorService.shared.release(.panel)
        panel?.orderOut(nil)
    }

    public func openSettingsWindow(tab: SettingsTab = .thermal) {
        self.selectedSettingsTab = tab
        closePopover()
        // 命令面板与控制中心面板互斥：打开设置窗也先收起命令面板
        CommandPaletteWindowController.shared.hideWindow()

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
