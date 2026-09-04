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

    /// 点击命令窗口外部区域时自动关闭的鼠标监听。
    /// 全局监听捕获点击其他 App / Finder / 桌面；本地监听捕获点击 CalmBar 自身其它窗口。
    private var globalDismissMonitor: Any?
    private var localDismissMonitor: Any?

    /// App 失活监听：⌘Tab 切到其他 App、或应用整体被切走时关闭面板
    private var deactivateObserver: NSObjectProtocol?

    /// 防止 orderOut / 外部点击 / 失活通知三路触发时的重复关闭
    private var isHiding = false

    init() {}

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
            installDismissMonitors()
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
        installDismissMonitors()
    }

    public func hideWindow() {
        guard !isHiding else { return }
        isHiding = true
        removeDismissMonitors()
        window?.orderOut(nil)
        window?.contentViewController = nil
        hideCount += 1
        isHiding = false
    }

    /// 单元测试观测点：`hideWindow` 被成功执行的次数（含无窗口 no-op 的成功调用）
    private(set) var hideCount: Int = 0

    // MARK: - 点击窗口外部 / App 失活自动关闭

    private func installDismissMonitors() {
        removeDismissMonitors()

        // 本地监听：捕获本 App（菜单栏图标 / 设置窗口 / 其它）的点击
        localDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self = self, let panel = self.window, panel.isVisible else { return event }
            // 点击在面板自身内部（例如点击搜索框以重新聚焦）时不关闭
            if panel.frame.contains(NSEvent.mouseLocation) {
                return event
            }
            self.hideWindow()
            return event
        }

        // 全局监听：捕获点击其它 App / 桌面。注意回调在 AppKit 后台线程派发，
        // 而 hideWindow 涉及 AppKit UI 操作，因此切回 @MainActor 再执行。
        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let panel = self.window, panel.isVisible else { return }
                if panel.frame.contains(NSEvent.mouseLocation) {
                    return
                }
                self.hideWindow()
            }
        }

        // App 失活监听：⌘Tab 切到其他 App、点 Dock 其它图标、Mission Control 等
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDeactivation()
            }
        }
    }

    /// App 失活时关闭面板。作为独立方法便于单元测试直接触发，避免依赖真实系统通知时序。
    func handleAppDeactivation() {
        hideWindow()
    }

    private func removeDismissMonitors() {
        if let monitor = localDismissMonitor {
            NSEvent.removeMonitor(monitor)
            localDismissMonitor = nil
        }
        if let monitor = globalDismissMonitor {
            NSEvent.removeMonitor(monitor)
            globalDismissMonitor = nil
        }
        if let observer = deactivateObserver {
            NotificationCenter.default.removeObserver(observer)
            deactivateObserver = nil
        }
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
