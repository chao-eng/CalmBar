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

        // 计划状态 chip 验证：临时创建一条不影响真实配置的计划，截图后删除
        var visualScheduleID: UUID?
        let demoStart = Calendar.current.date(bySettingHour: 4, minute: 0, second: 0,
                                              of: Date().addingTimeInterval(86_400)) ?? Date().addingTimeInterval(86_400)
        let demoSchedule = RecorderSchedule(
            name: "视觉回归计划",
            repeatRule: .once(start: demoStart, end: demoStart.addingTimeInterval(30 * 60)),
            source: .display(displayID: CGMainDisplayID()),
            profile: RecorderCaptureProfile()
        )
        if RecorderScheduleCoordinator.shared.save(demoSchedule) == nil {
            visualScheduleID = demoSchedule.id
            M1Trace.log("visual schedule demo summary=\(RecorderScheduleCoordinator.shared.nextScheduleSummary ?? "nil")")
        } else {
            M1Trace.log("visual schedule demo skipped due to conflict")
        }

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

        // 录制计划窗口：列表、编辑器与参数布局
        RecorderScheduleWindowController.shared.show()
        try? await Task.sleep(for: .milliseconds(800))
        if let scheduleWindow = NSApp.windows.first(where: { $0.title == "录制计划" }) {
            _ = M1Trace.capture(scheduleWindow, to: "/tmp/calmbar_visual/light_recorder_schedule.png")
            scheduleWindow.orderOut(nil)
        } else {
            M1Trace.log("visual recorder schedule window not found")
        }

        // 设置窗口：默认页 + 新增音频/录制页，浅深各截一张
        NSApp.appearance = NSAppearance(named: .aqua)
        try? await Task.sleep(for: .milliseconds(400))
        manager.closePopover()

        // AI 网关：注入与用户截图同构的示例数据（长别名 + 多渠道），验证窄窗口不横向溢出
        // 仅在显式加 --visual-demo-data 时注入，避免常规视觉回归污染真实配置
        let injectDemoData = CommandLine.arguments.contains("--visual-demo-data")
        let savedChannels = settings.aiGatewayChannels
        let savedModels = settings.aiGatewayModels
        if injectDemoData {
            let demoChannelA = AIGatewayChannel(name: "百炼", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", models: ["qwen-max", "qwen-plus"])
            let demoChannelB = AIGatewayChannel(name: "火山", baseURL: "https://ark.cn-beijing.volces.com/api/v3", models: ["doubao-seed-2-1-pro-20251101"])
            let demoChannelC = AIGatewayChannel(name: "magpie", baseURL: "https://api.magpie.example.com/v1", models: ["deepseek-v4"])
            settings.aiGatewayChannels = [demoChannelA, demoChannelB, demoChannelC]
            settings.aiGatewayModels = [
                AIGatewayModelRoute(alias: "glm-5", channelIDs: [demoChannelA.id]),
                AIGatewayModelRoute(alias: "doubao-seed-2-1-pro-20251101", channelIDs: [demoChannelB.id]),
                AIGatewayModelRoute(alias: "trae-cn/DeepSeek-V4.1-Flash-1017", channelIDs: [demoChannelC.id]),
                AIGatewayModelRoute(alias: "gemini/gemini-3.8-flash", channelIDs: [demoChannelC.id])
            ]
        }

        let settingsPages: [(SettingsTab, String)] = [
            (.thermal, "settings"),
            (.audio, "settings_audio"),
            (.recorder, "settings_recorder"),
            (.lanShare, "settings_lanshare"),
            (.aiGateway, "settings_aigateway")
        ]
        for (tab, name) in settingsPages {
            NSApp.appearance = NSAppearance(named: .aqua)
            manager.openSettingsWindow(tab: tab)
            try? await Task.sleep(for: .milliseconds(900))
            guard let settingsWindow = NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 400 && $0 != panel }) else {
                M1Trace.log("visual settings window not found")
                break
            }
            // AI 网关：额外按窗口最小宽度 700 复现窄窗口挤压问题
            if tab == .aiGateway {
                var frame = settingsWindow.frame
                frame.size.width = 700
                frame.size.height = 560
                settingsWindow.setFrame(frame, display: true)
                try? await Task.sleep(for: .milliseconds(700))
                _ = M1Trace.capture(settingsWindow, to: "/tmp/calmbar_visual/light_\(name)_narrow.png")
                // 加高窗口，让渠道列表进入可视区，验证渠道行的窄窗口表现
                frame.size.height = 1040
                settingsWindow.setFrame(frame, display: true)
                try? await Task.sleep(for: .milliseconds(600))
                _ = M1Trace.capture(settingsWindow, to: "/tmp/calmbar_visual/light_\(name)_narrow_tall.png")
                frame.size.height = 560
                settingsWindow.setFrame(frame, display: true)
                try? await Task.sleep(for: .milliseconds(400))
            }
            _ = M1Trace.capture(settingsWindow, to: "/tmp/calmbar_visual/light_\(name).png")
            NSApp.appearance = NSAppearance(named: .darkAqua)
            try? await Task.sleep(for: .milliseconds(600))
            _ = M1Trace.capture(settingsWindow, to: "/tmp/calmbar_visual/dark_\(name).png")
            settingsWindow.orderOut(nil)
            try? await Task.sleep(for: .milliseconds(300))
        }
        NSApp.appearance = NSAppearance(named: .aqua)

        // 还原示例数据，避免污染真实配置
        if injectDemoData {
            settings.aiGatewayChannels = savedChannels
            settings.aiGatewayModels = savedModels
        }
        if let visualScheduleID {
            _ = RecorderScheduleCoordinator.shared.delete(id: visualScheduleID)
        }

        M1Trace.log("visual summary tabs=\(tabs.map(\.rawValue).joined(separator: ",")) done")

        restoreSettings()
        NSApp.appearance = nil
        NSApp.terminate(nil)
    }
}
