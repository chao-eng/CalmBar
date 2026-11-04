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
        let savedAudioHub = settings.audioHubEnabled
        let savedTab = settings.popoverSelectedTab
        func restoreSettings() {
            settings.popoverShowMonitor = savedMonitor
            settings.systemMonitorEnabled = savedMonitorEnabled
            settings.audioHubEnabled = savedAudioHub
            settings.popoverSelectedTab = savedTab
        }
        settings.popoverShowMonitor = true
        settings.systemMonitorEnabled = true
        settings.audioHubEnabled = false

        try? await Task.sleep(for: .milliseconds(800))
        manager.showPopover()
        try? await Task.sleep(for: .milliseconds(600))

        // 复现用户路径：面板打开后再开启音频控制，声音分区应立即出现
        settings.audioHubEnabled = true
        try? await Task.sleep(for: .milliseconds(600))
        let audioSelectable = manager.selectPopoverTab(.audio)
        M1Trace.log("visual audio enabled after open, selectable=\(audioSelectable)")

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

        // 音频混音窗口（验证音量百分比与滑块刻度换算）
        NSApp.appearance = NSAppearance(named: .aqua)
        AudioMixerWindowController.shared.show()
        try? await Task.sleep(for: .milliseconds(1500))
        if let mixerWindow = NSApp.windows.first(where: { $0.title == "CalmBar 音频控制" }) {
            _ = M1Trace.capture(mixerWindow, to: "/tmp/calmbar_visual/light_audio_mixer.png")
            mixerWindow.orderOut(nil)
        } else {
            let frames = NSApp.windows.map { "\($0.title)|visible=\($0.isVisible)|\(Int($0.frame.width))x\(Int($0.frame.height))" }
            M1Trace.log("visual audio mixer window not found: \(frames.joined(separator: ", "))")
        }

        // 录制准备面板：验证去掉重复关闭按钮、录制文件夹入口与底部按钮布局
        RecorderPreparationWindowController.shared.show()
        try? await Task.sleep(for: .milliseconds(800))
        if let prep = NSApp.windows.first(where: { $0.title == "屏幕录制" }) {
            _ = M1Trace.capture(prep, to: "/tmp/calmbar_visual/light_recorder_prep.png")
        }
        RecorderPreparationWindowController.shared.cancelAndClose()

        // 设置窗口：默认页 + 新增音频/录制页，浅深各截一张
        NSApp.appearance = NSAppearance(named: .aqua)
        try? await Task.sleep(for: .milliseconds(400))
        manager.closePopover()
        let settingsPages: [(SettingsTab, String)] = [
            (.thermal, "settings"),
            (.audio, "settings_audio"),
            (.recorder, "settings_recorder")
        ]
        for (tab, name) in settingsPages {
            NSApp.appearance = NSAppearance(named: .aqua)
            manager.openSettingsWindow(tab: tab)
            try? await Task.sleep(for: .milliseconds(900))
            guard let settingsWindow = NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 400 && $0 != panel }) else {
                M1Trace.log("visual settings window not found")
                break
            }
            _ = M1Trace.capture(settingsWindow, to: "/tmp/calmbar_visual/light_\(name).png")
            NSApp.appearance = NSAppearance(named: .darkAqua)
            try? await Task.sleep(for: .milliseconds(600))
            _ = M1Trace.capture(settingsWindow, to: "/tmp/calmbar_visual/dark_\(name).png")
            settingsWindow.orderOut(nil)
            try? await Task.sleep(for: .milliseconds(300))
        }
        NSApp.appearance = NSAppearance(named: .aqua)

        M1Trace.log("visual summary tabs=\(tabs.map(\.rawValue).joined(separator: ",")) done")

        restoreSettings()
        NSApp.appearance = nil
        NSApp.terminate(nil)
    }
}
