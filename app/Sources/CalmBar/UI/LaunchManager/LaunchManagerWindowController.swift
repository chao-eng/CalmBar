import AppKit
import SwiftUI

public enum LaunchManagerTab: String, CaseIterable, Identifiable {
    case all = "all"
    case userAgents = "userAgents"
    case globalAgents = "globalAgents"
    case daemons = "daemons"
    case crontab = "crontab"
    case crashLooping = "crashLooping"
    case backups = "backups"
    case services = "services"

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .all: return "全部自启项"
        case .userAgents: return "用户自启项"
        case .globalAgents: return "全局自启项"
        case .daemons: return "系统守护服务"
        case .crontab: return "Crontab 计划任务"
        case .crashLooping: return "异常崩溃告警"
        case .backups: return "快照恢复中心"
        case .services: return "服务监听"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .userAgents: return "person.crop.circle"
        case .globalAgents: return "network"
        case .daemons: return "gearshape.2"
        case .crontab: return "clock"
        case .crashLooping: return "exclamationmark.triangle.fill"
        case .backups: return "clock.arrow.circlepath"
        case .services: return "antenna.radiowaves.left.and.right"
        }
    }
}

@MainActor
public final class LaunchManagerWindowController: ObservableObject {
    public static let shared = LaunchManagerWindowController()

    private var window: NSWindow?
    @Published public var activeTab: LaunchManagerTab = .all

    private init() {}

    public func show(initialTab: LaunchManagerTab = .all) {
        self.activeTab = initialTab

        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "CalmBar 启动项与常驻服务管理"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.minSize = NSSize(width: 940, height: 580)
        win.center()
        win.contentViewController = NSHostingController(rootView: LaunchManagerMainContainerView(initialTab: initialTab))
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win

        // 异步全量刷新
        Task {
            await LaunchManager.shared.refreshAll()
            if initialTab == .services {
                await LaunchManager.shared.refreshListeningPorts()
            }
        }
    }

    public func close() {
        window?.close()
        window = nil
    }
}
