import AppKit

// MARK: - 色彩令牌视觉验收驱动（临时：--visual 打开真实面板，截取 5 分区 × 浅/深色，验收后删除）

@MainActor
final class VisualCheckDriver {
    static let shared = VisualCheckDriver()

    private var started = false

    private init() {}

    func startIfRequested() {
        guard CommandLine.arguments.contains("--visual"), !started else { return }
        started = true
        Task { await run() }
    }

    private func run() async {
        try? FileManager.default.createDirectory(atPath: "/tmp/calmbar_visual", withIntermediateDirectories: true)

        let manager = StatusBarManager.shared
        let settings = AppSettings.shared

        // 强制全分区可见（验收后还原）
        let savedMonitor = settings.popoverShowMonitor
        let savedMonitorEnabled = settings.systemMonitorEnabled
        let savedAudio = settings.popoverShowAudio
        let savedTab = settings.popoverSelectedTab
        func restoreSettings() {
            settings.popoverShowMonitor = savedMonitor
            settings.systemMonitorEnabled = savedMonitorEnabled
            settings.popoverShowAudio = savedAudio
            settings.popoverSelectedTab = savedTab
        }
        settings.popoverShowMonitor = true
        settings.systemMonitorEnabled = true
        settings.popoverShowAudio = true

        try? await Task.sleep(for: .milliseconds(800))
        manager.showPopover()
        try? await Task.sleep(for: .milliseconds(600))

        guard let panel = manager.popoverWindow else {
            M1Trace.log("visual open failed")
            restoreSettings()
            NSApp.terminate(nil)
            return
        }

        let tabs = PopoverTab.allCases
        M1Trace.log("visual open tab=\(manager.currentPopoverTab.rawValue) frame=\(Int(panel.frame.width))x\(Int(panel.frame.height))")

        // 浅色外观
        NSApp.appearance = NSAppearance(named: .aqua)
        try? await Task.sleep(for: .milliseconds(500))
        for tab in tabs {
            _ = manager.selectPopoverTab(tab)
            // 监控分区等待真实采样积累出走势图
            try? await Task.sleep(for: .milliseconds(tab == .monitor ? 3500 : 450))
            _ = M1Trace.capture(panel, to: "/tmp/calmbar_visual/light_\(tab.rawValue).png")
        }

        // 深色外观
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? await Task.sleep(for: .milliseconds(600))
        for tab in tabs {
            _ = manager.selectPopoverTab(tab)
            try? await Task.sleep(for: .milliseconds(450))
            _ = M1Trace.capture(panel, to: "/tmp/calmbar_visual/dark_\(tab.rawValue).png")
        }

        M1Trace.log("visual summary tabs=\(tabs.map(\.rawValue).joined(separator: ",")) done")

        restoreSettings()
        NSApp.appearance = nil
        NSApp.terminate(nil)
    }
}
