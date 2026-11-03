import AppKit

// MARK: - M8 生产面板接入回归（真实状态栏面板路径）

@MainActor
final class M8SmokeDriver {
    static let shared = M8SmokeDriver()

    private var started = false
    private let tag: String

    private init() {
        tag = CommandLine.arguments.contains("--dark") ? "m8_dark" : "m8"
    }

    func startIfRequested() {
        guard CommandLine.arguments.contains("--m8"), !started else { return }
        started = true
        Task { await run() }
    }

    private func run() async {
        let manager = StatusBarManager.shared
        try? await Task.sleep(for: .milliseconds(700))
        // M8 阶段一面板仅含温控/守护/工具，监控已上线后需显式关闭以保持原回归语义
        let originalMonitorTab = AppSettings.shared.popoverShowMonitor
        let originalTab = AppSettings.shared.popoverSelectedTab
        let originalGauges = AppSettings.shared.popoverShowGauges
        func restoreSettings() {
            AppSettings.shared.popoverShowMonitor = originalMonitorTab
            AppSettings.shared.popoverSelectedTab = originalTab
            AppSettings.shared.popoverShowGauges = originalGauges
        }
        AppSettings.shared.popoverShowMonitor = false

        manager.showPopover()
        try? await Task.sleep(for: .milliseconds(600))

        guard let panel = manager.popoverWindow else {
            M1Trace.log("m8 open failed")
            restoreSettings()
            NSApp.terminate(nil)
            return
        }

        let tabs = [PopoverTab.thermal, .guardian, .tools]
        let heights = tabs.map { "\($0.rawValue):\(Int(PopoverTabRoute.route(for: $0).totalHeight))" }.joined(separator: " ")
        M1Trace.log("m8 open tab=\(manager.currentPopoverTab.rawValue) frame=\(describe(panel.frame)) heights=\(heights) tabs=\(manager.tabSummary)")

        // 各分区截图
        for tab in tabs {
            _ = manager.selectPopoverTab(tab)
            try? await Task.sleep(for: .milliseconds(350))
            _ = M1Trace.capture(panel, to: "/tmp/\(tag)_\(tab.rawValue).png")
        }

        // 30 次切换 + 顶边漂移
        var switches = 0
        var driftMax: CGFloat = 0
        var failures = 0
        for index in 1...30 {
            let tab = tabs[index % tabs.count]
            let topBefore = panel.frame.maxY
            _ = manager.selectPopoverTab(tab)
            try? await Task.sleep(for: .milliseconds(260))
            let topAfter = panel.frame.maxY
            let delta = abs(topAfter - topBefore)
            switches += 1
            driftMax = max(driftMax, delta)
            if delta > 0.5 { failures += 1 }
            M1Trace.log("m8 switch n=\(index) tab=\(tab.rawValue) height=\(Int(panel.frame.height)) drift=\(String(format: "%.2f", delta))")
        }

        // AX 树与朗读顺序
        let ax = M1A11yProbe.dumpAX(to: "/tmp/\(tag)_ax.txt")
        let order = M1A11yProbe.orderReport()
        let axText = (try? String(contentsOfFile: "/tmp/\(tag)_ax.txt", encoding: .utf8)) ?? ""
        let tabNodes = axText.components(separatedBy: "个分区中第").count - 1
        M1Trace.log("m8 ax status=\(ax.status) nodes=\(ax.nodes) tabNodes=\(tabNodes) order=\(order)")

        // 键盘：⌘1–⌘3 生效，⌘4/⌘5 未启用必须 no-op，←/→ 环内移动
        // 前置切到工具分区，避免 ⌘1 落在已是温控的状态而误判为未生效
        _ = manager.selectPopoverTab(.tools)
        try? await Task.sleep(for: .milliseconds(240))
        var keyResults: [String] = []
        for (chars, code) in [("1", UInt16(18)), ("2", UInt16(19)), ("3", UInt16(20))] {
            if let event = keyEvent(chars, keyCode: code, flags: .command) {
                let handled = manager.handlePopoverKey(event)
                keyResults.append("cmd\(chars)=\(handled ? "ok" : "no")/\(manager.currentPopoverTab.rawValue)")
                try? await Task.sleep(for: .milliseconds(240))
            }
        }
        for (chars, code) in [("4", UInt16(21)), ("5", UInt16(23))] {
            if let event = keyEvent(chars, keyCode: code, flags: .command) {
                let handled = manager.handlePopoverKey(event)
                keyResults.append("cmd\(chars)=\(handled ? "ok" : "noop")/\(manager.currentPopoverTab.rawValue)")
            }
        }
        if let event = keyEvent("", keyCode: 124, flags: []) {
            let handled = manager.handlePopoverKey(event)
            keyResults.append("right=\(handled ? "ok" : "no")/\(manager.currentPopoverTab.rawValue)")
            try? await Task.sleep(for: .milliseconds(240))
        }
        if let event = keyEvent("", keyCode: 123, flags: []) {
            let handled = manager.handlePopoverKey(event)
            keyResults.append("left=\(handled ? "ok" : "no")/\(manager.currentPopoverTab.rawValue)")
            try? await Task.sleep(for: .milliseconds(240))
        }
        M1Trace.log("m8 keyboard \(keyResults.joined(separator: " | "))")

        // 空状态生产接线
        AppSettings.shared.popoverShowGauges = false
        _ = manager.selectPopoverTab(.thermal)
        try? await Task.sleep(for: .milliseconds(400))
        _ = M1Trace.capture(panel, to: "/tmp/\(tag)_empty_thermal.png")
        let emptyOK = M1A11yProbe.containsValue("温控未显示")
        AppSettings.shared.popoverShowGauges = true
        try? await Task.sleep(for: .milliseconds(300))
        M1Trace.log("m8 empty thermal=\(emptyOK ? "ok" : "missing")")

        // 选中持久化：关闭后重开仍停留在守护
        _ = manager.selectPopoverTab(.guardian)
        try? await Task.sleep(for: .milliseconds(300))
        manager.closePopover()
        try? await Task.sleep(for: .milliseconds(250))
        manager.showPopover()
        try? await Task.sleep(for: .milliseconds(500))
        let persistedOK = manager.currentPopoverTab == .guardian
        M1Trace.log("m8 persistence tab=\(manager.currentPopoverTab.rawValue) result=\(persistedOK ? "ok" : "failed")")

        // BR-08：持久化值指向未启用分区时必须回退温控
        AppSettings.shared.popoverSelectedTab = "monitor"
        manager.closePopover()
        try? await Task.sleep(for: .milliseconds(250))
        manager.showPopover()
        try? await Task.sleep(for: .milliseconds(500))
        let fallbackOK = manager.currentPopoverTab == .thermal
        M1Trace.log("m8 fallback tab=\(manager.currentPopoverTab.rawValue) result=\(fallbackOK ? "ok" : "failed")")

        _ = M1Trace.capture(panel, to: "/tmp/\(tag)_final.png")
        M1Trace.log("m8 summary tabs=3 switches=\(switches) driftMax=\(String(format: "%.2f", driftMax)) failures=\(failures) width=\(Int(panel.frame.width)) finalHeight=\(Int(panel.frame.height)) ax=\(ax.nodes) tabNodes=\(tabNodes) empty=\(emptyOK ? "ok" : "missing") persistence=\(persistedOK ? "ok" : "failed") fallback=\(fallbackOK ? "ok" : "failed")")

        restoreSettings()
        NSApp.terminate(nil)
    }

    private func describe(_ frame: NSRect) -> String {
        "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)) top=\(Int(frame.maxY))"
    }

    private func keyEvent(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

private extension StatusBarManager {
    var tabSummary: String {
        PopoverPanelModel.availableTabs(from: AppSettings.shared).map(\.rawValue).joined(separator: ",")
    }
}
