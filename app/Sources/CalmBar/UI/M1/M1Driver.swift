import AppKit
import CalmBarKit
import SwiftUI

// MARK: - M1 骨架驱动（独立窗口，不接现有面板）

@MainActor
final class M1Driver: ObservableObject {
    static let shared = M1Driver()

    @Published private(set) var currentTab: PopoverTab = .thermal
    @Published private(set) var statusReadout = "appears=t0/g0/o0"

    let reduceMotion: Bool
    let increaseContrast: Bool
    let isM5: Bool
    let stressMode: Bool
    let isM6: Bool
    let m6Empty: Bool
    let isM7: Bool
    let m7Empty: Bool
    let useRealThermal: Bool
    let useRealGuardian: Bool
    let useRealTools: Bool
    let useRealMonitor: Bool
    let useRealAudio: Bool
    let isDark: Bool

    /// 当前可用分区：M7 强制放开 5 个，其余阶段仍只开放前三
    var availableTabs: [PopoverTab] { isM7 ? PopoverTab.allCases : PopoverTab.phaseOne }

    private var appearCounts: [String: Int] = [:]
    private var switchCount = 0
    private var heightSwitchCount = 0
    private var heightDriftMax: CGFloat = 0
    private var heightDriftFailures = 0
    private var lastThermalHeight: CGFloat = 0
    private var lastGuardianHeight: CGFloat = 0
    private var lastToolHeight: CGFloat = 0
    private var lastToolWidth: CGFloat = 0
    private var lastMonitorHeight: CGFloat = 0
    private var lastAudioHeight: CGFloat = 0
    private var lastTabBarWidth: CGFloat = 0
    private var stressScrollSummary = "n/a"
    private var stressResetSummary = "n/a"
    private var panel: M1Panel?
    private var keyMonitor: Any?

    private init() {
        let args = CommandLine.arguments
        reduceMotion = args.contains("--reduce-motion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        increaseContrast = args.contains("--increase-contrast") || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        isM5 = args.contains("--m5") || args.contains("--m5-stress")
        stressMode = args.contains("--m5-stress")
        isM6 = args.contains("--m6") || args.contains("--m6-empty")
        m6Empty = args.contains("--m6-empty")
        isM7 = args.contains("--m7") || args.contains("--m7-empty")
        m7Empty = args.contains("--m7-empty")
        useRealTools = args.contains("--m4") || isM5 || isM6 || isM7
        useRealGuardian = args.contains("--m3") || useRealTools
        useRealThermal = args.contains("--m2") || useRealGuardian
        useRealMonitor = isM7
        useRealAudio = isM7
        isDark = args.contains("--dark")
        if isDark {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    var skeletonLabel: String {
        if isM7 { return m7Empty ? "M7 · 空状态" : "M7" }
        if isM6 { return m6Empty ? "M6 · 空状态" : "M6" }
        if isM5 { return "M5" }
        if useRealTools { return "M4" }
        if useRealGuardian { return "M3" }
        return useRealThermal ? "M2" : "M1"
    }

    private var runTag: String {
        let base: String
        if isM7 {
            base = m7Empty ? "m7_empty" : "m7"
        } else if isM6 {
            base = m6Empty ? "m6_empty" : "m6"
        } else if isM5 {
            base = "m5"
        } else if useRealTools {
            base = "m4"
        } else if useRealGuardian {
            base = "m3"
        } else if useRealThermal {
            base = "m2"
        } else {
            base = "m1"
        }
        return isDark ? "\(base)_dark" : base
    }

    private var currentViewportHeight: CGFloat {
        PopoverTabRoute.route(for: currentTab).viewportHeight
    }

    // MARK: 生命周期

    func present() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        let initialHeight = PopoverTabRoute.route(for: currentTab).totalHeight
        let panel = M1Panel(
            contentRect: NSRect(x: 0, y: 0, width: PopoverLayout.panelWidth, height: initialHeight),
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
        panel.hidesOnDeactivate = false
        panel.contentViewController = NSHostingController(rootView: M1Scene(driver: self))
        panel.setContentSize(NSSize(width: PopoverLayout.panelWidth, height: initialHeight))
        self.panel = panel

        reposition()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        startKeyMonitor()

        let heightTable = PopoverTab.allCases
            .map { tab in
                let route = PopoverTabRoute.route(for: tab)
                return "\(tab.rawValue):\(Int(route.totalHeight))/\(Int(route.viewportHeight))"
            }
            .joined(separator: ",")
        M1Trace.log("present total=\(Int(initialHeight)) content=\(Int(currentViewportHeight)) frame=\(describe(panel.frame)) chrome=\(Int(PopoverLayout.chromeHeight)) heights=\(heightTable) stress=\(stressMode) reduceMotion=\(reduceMotion) increaseContrast=\(increaseContrast) realThermal=\(useRealThermal) realGuardian=\(useRealGuardian) realTools=\(useRealTools)")
        let clampOK = PopoverLayout.clampedViewport(PopoverLayout.minViewportHeight - 40) == PopoverLayout.minViewportHeight
            && PopoverLayout.clampedViewport(PopoverLayout.maxViewportHeight + 40) == PopoverLayout.maxViewportHeight
        M1Trace.log("height clamp viewport=[\(Int(PopoverLayout.minViewportHeight)),\(Int(PopoverLayout.maxViewportHeight))] total=[\(Int(PopoverLayout.chromeHeight + PopoverLayout.minViewportHeight)),\(Int(PopoverLayout.chromeHeight + PopoverLayout.maxViewportHeight))] clamp=\(clampOK ? "ok" : "failed")")
        if isM6 {
            let groupSummary = PopoverVisibilityGroup.allCases
                .map { group in
                    let enabled = group.items.filter { $0.isEnabled(AppSettings.shared) }.count
                    return "\(group.rawValue):\(enabled)/\(group.items.count)"
                }
                .joined(separator: " ")
            M1Trace.log("m6 groups \(groupSummary) total=\(PopoverVisibilityItem.allCases.count) empty=\(m6Empty)")
            let commandIDs = ["popover.thermal", "popover.guardian", "popover.tools"]
            let commandSummary = commandIDs
                .map { "\($0)=\(CommandCenter.shared.command(id: $0) != nil ? "ok" : "missing")" }
                .joined(separator: " ")
            M1Trace.log("m6 commands \(commandSummary)")
        }
        if isM7 {
            let tabSummary = availableTabs.map(\.rawValue).joined(separator: ",")
            let viewportSummary = availableTabs
                .map { "\($0.rawValue):\(Int(PopoverTabRoute.route(for: $0).viewportHeight))" }
                .joined(separator: " ")
            let barExpected = PopoverLayout.pillSelectedWidth
                + PopoverLayout.pillIdleWidth * CGFloat(availableTabs.count - 1)
                + PopoverLayout.pillSpacing * CGFloat(availableTabs.count - 1)
            M1Trace.log("m7 tabs=\(availableTabs.count) list=\(tabSummary) viewports=\(viewportSummary) barExpected=\(Int(barExpected)) empty=\(m7Empty) monitorDefault=\(AppSettings.shared.popoverShowMonitor)")
        }
        refreshReadout()

        if useRealThermal {
            PermissionManager.shared.refreshAll()
        }

        if CommandLine.arguments.contains("--auto") {
            autoRun(exitWhenDone: CommandLine.arguments.contains("--exit"))
        }
    }

    func close() {
        stopKeyMonitor()
        panel?.orderOut(nil)
        M1Trace.log("close")
    }

    // MARK: 分区切换

    @discardableResult
    func selectTab(_ tab: PopoverTab) -> Bool {
        guard availableTabs.contains(tab), currentTab != tab else { return false }
        let oldTab = currentTab
        let topBefore = panel?.frame.maxY ?? 0
        let heightBefore = panel?.frame.height ?? 0
        currentTab = tab
        switchCount += 1
        M1Trace.log("tab select \(tab.rawValue) n=\(switchCount)")

        if let panel {
            let targetHeight = PopoverTabRoute.route(for: tab).totalHeight
            let target = NSRect(
                x: panel.frame.minX,
                y: topBefore - targetHeight,
                width: PopoverLayout.panelWidth,
                height: targetHeight
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : PopoverLayout.heightAnimation
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, let panel = self.panel else { return }
                    let topAfter = panel.frame.maxY
                    let delta = abs(topAfter - topBefore)
                    self.heightSwitchCount += 1
                    self.heightDriftMax = max(self.heightDriftMax, delta)
                    if delta > 0.5 {
                        self.heightDriftFailures += 1
                    }
                    M1Trace.log("height \(oldTab.rawValue)->\(tab.rawValue) from=\(Int(heightBefore)) target=\(Int(targetHeight)) actual=\(Int(panel.frame.height)) topBefore=\(Int(topBefore)) topAfter=\(Int(topAfter)) delta=\(String(format: "%.2f", delta))")
                }
            }
        }
        refreshReadout()
        return true
    }

    func noteAppear(_ tab: PopoverTab) {
        appearCounts[tab.rawValue, default: 0] += 1
        M1Trace.log("appear \(tab.rawValue) count=\(appearCounts[tab.rawValue, default: 0])")
        refreshReadout()
    }

    /// M2：记录温控内容自然高度，判断是否超出当前路由视口
    func noteThermalHeight(_ height: CGFloat) {
        guard abs(height - lastThermalHeight) > 0.5 else { return }
        lastThermalHeight = height
        let viewport = PopoverTabRoute.route(for: .thermal).viewportHeight
        let overflow = max(0, height - viewport)
        M1Trace.log("thermal naturalHeight=\(Int(height)) viewport=\(Int(viewport)) overflow=\(Int(overflow)) maxOffset=\(Int(overflow))")
    }

    /// M3：记录守护内容自然高度
    func noteGuardianHeight(_ height: CGFloat) {
        guard abs(height - lastGuardianHeight) > 0.5 else { return }
        lastGuardianHeight = height
        let viewport = PopoverTabRoute.route(for: .guardian).viewportHeight
        let overflow = max(0, height - viewport)
        M1Trace.log("guardian naturalHeight=\(Int(height)) viewport=\(Int(viewport)) overflow=\(Int(overflow)) maxOffset=\(Int(overflow))")
    }

    /// M4：记录工具网格自然高度与宽度
    func noteToolHeight(_ height: CGFloat, width: CGFloat) {
        guard abs(height - lastToolHeight) > 0.5 || abs(width - lastToolWidth) > 0.5 else { return }
        lastToolHeight = height
        lastToolWidth = width
        let viewport = PopoverTabRoute.route(for: .tools).viewportHeight
        let overflow = max(0, height - viewport)
        let widthOverflow = max(0, width - PopoverLayout.contentWidth)
        M1Trace.log("tools gridWidth=\(Int(width)) expected=\(Int(PopoverLayout.contentWidth)) widthOverflow=\(Int(widthOverflow)) naturalHeight=\(Int(height)) viewport=\(Int(viewport)) overflow=\(Int(overflow))")
    }

    /// M4：工具动作只记录，不执行真实业务
    func noteToolAction(_ action: String) {
        M1Trace.log("tool action \(action) (read-only harness)")
    }

    /// M7：监控内容自然高度（不启动采样）
    func noteMonitorHeight(_ height: CGFloat) {
        guard abs(height - lastMonitorHeight) > 0.5 else { return }
        lastMonitorHeight = height
        let viewport = PopoverTabRoute.route(for: .monitor).viewportHeight
        let overflow = max(0, height - viewport)
        M1Trace.log("monitor naturalHeight=\(Int(height)) viewport=\(Int(viewport)) overflow=\(Int(overflow))")
    }

    /// M7：声音内容自然高度（不接音频引擎）
    func noteAudioHeight(_ height: CGFloat) {
        guard abs(height - lastAudioHeight) > 0.5 else { return }
        lastAudioHeight = height
        let viewport = PopoverTabRoute.route(for: .audio).viewportHeight
        let overflow = max(0, height - viewport)
        M1Trace.log("audio naturalHeight=\(Int(height)) viewport=\(Int(viewport)) overflow=\(Int(overflow))")
    }

    /// M7：分区栏胶囊总宽实测（5 分区目标 268pt）
    func noteTabBarWidth(_ width: CGFloat) {
        guard abs(width - lastTabBarWidth) > 0.5 else { return }
        lastTabBarWidth = width
        let expectedWidth = PopoverLayout.pillSelectedWidth
            + PopoverLayout.pillIdleWidth * CGFloat(availableTabs.count - 1)
            + PopoverLayout.pillSpacing * CGFloat(availableTabs.count - 1)
        let overflow = max(0, width - PopoverLayout.tabBarInnerWidth)
        M1Trace.log("tabbar pillsWidth=\(Int(width)) expected=\(Int(expectedWidth)) delta=\(String(format: "%.2f", width - expectedWidth)) overflow=\(Int(overflow)) tabs=\(availableTabs.count)")
    }

    /// M7：分区动作只记录，不执行真实业务
    func noteSectionAction(_ tab: PopoverTab, _ action: String) {
        M1Trace.log("section action tab=\(tab.rawValue) action=\(action) (read-only harness)")
    }

    private func refreshReadout() {
        statusReadout = "appears=t\(appearCounts["thermal", default: 0])/g\(appearCounts["guardian", default: 0])/o\(appearCounts["tools", default: 0])/m\(appearCounts["monitor", default: 0])/a\(appearCounts["audio", default: 0])"
    }

    // MARK: 自动回归

    func autoRun(exitWhenDone: Bool) {
        M1Trace.log("auto start exitWhenDone=\(exitWhenDone)")
        Task { @MainActor [weak self] in
            guard let self, let panel = self.panel else { return }
            try? await Task.sleep(for: .milliseconds(800))

            let tabs = self.availableTabs
            for index in 0..<40 {
                self.selectTab(tabs[index % tabs.count])
                try? await Task.sleep(for: .milliseconds(220))
            }
            try? await Task.sleep(for: .milliseconds(300))

            let counts = tabs
                .map { "\($0.rawValue):\(self.appearCounts[$0.rawValue, default: 0])" }
                .joined(separator: ",")
            M1Trace.log("appear counts \(counts) switches=\(self.switchCount)")

            let tag = self.runTag

            // 各分区截图
            for tab in tabs {
                self.selectTab(tab)
                try? await Task.sleep(for: .milliseconds(350))
                M1Trace.capture(panel, to: "/tmp/\(tag)_\(tab.rawValue).png")
            }

            // M2：单独导出温控分区 AX 树
            if self.useRealThermal {
                self.selectTab(.thermal)
                try? await Task.sleep(for: .milliseconds(350))
                let thermalAX = M1A11yProbe.dumpAX(to: "/tmp/\(tag)_ax_thermal.txt")
                M1Trace.log("thermal ax \(thermalAX.status) nodes=\(thermalAX.nodes) path=/tmp/\(tag)_ax_thermal.txt")
            }

            // M3：单独导出守护分区 AX 树
            if self.useRealGuardian {
                self.selectTab(.guardian)
                try? await Task.sleep(for: .milliseconds(350))
                let guardianAX = M1A11yProbe.dumpAX(to: "/tmp/\(tag)_ax_guardian.txt")
                M1Trace.log("guardian ax \(guardianAX.status) nodes=\(guardianAX.nodes) path=/tmp/\(tag)_ax_guardian.txt")
            }

            // M4：单独导出工具分区 AX 树
            if self.useRealTools {
                self.selectTab(.tools)
                try? await Task.sleep(for: .milliseconds(350))
                let toolsAX = M1A11yProbe.dumpAX(to: "/tmp/\(tag)_ax_tools.txt")
                M1Trace.log("tools ax \(toolsAX.status) nodes=\(toolsAX.nodes) path=/tmp/\(tag)_ax_tools.txt")
                // M4：AX 触发一次磁贴，验证 action 闭包只记录不执行
                let press = M1A11yProbe.press(descriptionPrefix: "截屏识字")
                M1Trace.log("tool press=\(press)")
            }

            // M7：监控分区 AX 树（只读指标）
            if self.useRealMonitor {
                self.selectTab(.monitor)
                try? await Task.sleep(for: .milliseconds(350))
                let monitorAX = M1A11yProbe.dumpAX(to: "/tmp/\(tag)_ax_monitor.txt")
                M1Trace.log("monitor ax \(monitorAX.status) nodes=\(monitorAX.nodes) path=/tmp/\(tag)_ax_monitor.txt")
                let alertPress = M1A11yProbe.press(descriptionPrefix: "告警设置")
                M1Trace.log("monitor alert press=\(alertPress)")
            }

            // M7：声音分区 AX 树（最多 4 行）
            if self.useRealAudio {
                self.selectTab(.audio)
                try? await Task.sleep(for: .milliseconds(350))
                let audioAX = M1A11yProbe.dumpAX(to: "/tmp/\(tag)_ax_audio.txt")
                M1Trace.log("audio ax \(audioAX.status) nodes=\(audioAX.nodes) path=/tmp/\(tag)_ax_audio.txt")
            }

            // M7：声音空状态验证
            if self.isM7, self.m7Empty {
                self.selectTab(.audio)
                try? await Task.sleep(for: .milliseconds(350))
                _ = M1Trace.capture(panel, to: "/tmp/\(tag)_empty_audio.png")
                let hit = M1A11yProbe.containsValue("暂无应用发声")
                M1Trace.log("m7 empty state audio=\(hit ? "ok" : "missing")")
            }

            // M6：统一空状态验证（三分区各一张截图 + AX 节点）
            if self.isM6, self.m6Empty {
                var emptyHits: [String] = []
                for (tab, group) in [(PopoverTab.thermal, PopoverVisibilityGroup.thermal),
                                     (.guardian, .guardian),
                                     (.tools, .tools)] {
                    self.selectTab(tab)
                    try? await Task.sleep(for: .milliseconds(350))
                    _ = M1Trace.capture(panel, to: "/tmp/\(tag)_empty_\(tab.rawValue).png")
                    let hit = M1A11yProbe.containsValue(group.emptyTitle)
                    emptyHits.append("\(tab.rawValue):\(hit ? "ok" : "missing")")
                }
                M1Trace.log("m6 empty states \(emptyHits.joined(separator: " "))")
            }

            // M5：压力模式验证滚动夹取与切回重置
            if self.stressMode {
                self.selectTab(.guardian)
                try? await Task.sleep(for: .milliseconds(450))
                M1Trace.capture(panel, to: "/tmp/\(tag)_stress_top.png")
                self.stressScrollSummary = self.scrollReport(toBottom: true)
                M1Trace.log("stress scroll toBottom \(self.stressScrollSummary)")
                try? await Task.sleep(for: .milliseconds(200))
                M1Trace.capture(panel, to: "/tmp/\(tag)_stress_bottom.png")

                self.selectTab(.tools)
                try? await Task.sleep(for: .milliseconds(350))
                self.selectTab(.guardian)
                try? await Task.sleep(for: .milliseconds(450))
                self.stressResetSummary = self.scrollReport(toBottom: false)
                M1Trace.log("stress reset after tab roundtrip \(self.stressResetSummary)")
            }

            // AX 树与顺序
            let ax = M1A11yProbe.dumpAX(to: "/tmp/\(tag)_ax.txt")
            let order = M1A11yProbe.orderReport()
            M1Trace.log("ax dump \(ax.status) nodes=\(ax.nodes) path=/tmp/\(tag)_ax.txt")
            M1Trace.log("order \(order)")

            // 键盘最小集（每次切换后等待高度动画收敛，避免在途动画串扰）
            var keyResults: [String] = []
            if let event = self.makeKey("2", keyCode: 19, flags: .command) {
                keyResults.append("cmd2=\(self.handleKey(event)) tab=\(self.currentTab.rawValue)")
                try? await Task.sleep(for: .milliseconds(240))
            }
            if let event = self.makeKey("4", keyCode: 21, flags: .command) {
                keyResults.append("cmd4=\(self.handleKey(event)) tab=\(self.currentTab.rawValue)")
                try? await Task.sleep(for: .milliseconds(240))
            }
            if let event = self.makeKey("5", keyCode: 23, flags: .command) {
                keyResults.append("cmd5=\(self.handleKey(event)) tab=\(self.currentTab.rawValue)")
                try? await Task.sleep(for: .milliseconds(240))
            }
            if let event = self.makeKey("", keyCode: 124) {
                keyResults.append("right=\(self.handleKey(event)) tab=\(self.currentTab.rawValue)")
                try? await Task.sleep(for: .milliseconds(240))
            }
            M1Trace.log("keyboard \(keyResults.joined(separator: " | "))")

            // Esc 最后执行，会关闭面板
            var escConsumed = false
            if let event = self.makeKey("\u{1b}", keyCode: 53) {
                escConsumed = self.handleKey(event)
            }
            M1Trace.log("esc consumed=\(escConsumed) visible=\(self.panel?.isVisible ?? false)")

            let orderOK = order.contains("ok=true")
            M1Trace.log("\(tag) summary tabs=\(tabs.count) switches=\(self.switchCount) appearCounts=\(counts) thermalHeight=\(Int(self.lastThermalHeight)) guardianHeight=\(Int(self.lastGuardianHeight)) toolsHeight=\(Int(self.lastToolHeight)) toolsWidth=\(Int(self.lastToolWidth)) monitorHeight=\(Int(self.lastMonitorHeight)) audioHeight=\(Int(self.lastAudioHeight)) tabBarWidth=\(Int(self.lastTabBarWidth)) heightSwitches=\(self.heightSwitchCount) heightDriftMax=\(String(format: "%.2f", self.heightDriftMax)) heightFailures=\(self.heightDriftFailures) stressScroll=\(self.stressScrollSummary) stressReset=\(self.stressResetSummary) ax=\(ax.status) nodes=\(ax.nodes) order=\(orderOK ? "ok" : "failed") esc=\(escConsumed ? "ok" : "failed") reduceMotion=\(self.reduceMotion) contrast=\(self.increaseContrast)")

            // M6：命令深链 → 打开通用设置并定位三组
            if self.isM6 {
                for group in PopoverVisibilityGroup.allCases {
                    PopoverSettingsDeepLink.shared.open(group)
                    try? await Task.sleep(for: .milliseconds(650))
                    let consumed = PopoverSettingsDeepLink.shared.pendingGroup == nil
                    let settingsWindow = NSApp.windows.first { $0.isVisible && $0.title == SettingsTab.general.titleZH }
                    if let settingsWindow {
                        _ = M1Trace.capture(settingsWindow, to: "/tmp/\(tag)_settings_\(group.rawValue).png")
                    }
                    M1Trace.log("m6 deep link group=\(group.rawValue) selected=\(StatusBarManager.shared.selectedSettingsTab.rawValue) scroll=\(consumed ? "consumed" : "pending") window=\(settingsWindow != nil ? "ok" : "missing")")
                }
                NSApp.windows.first { $0.title == SettingsTab.general.titleZH }?.orderOut(nil)
            }

            if exitWhenDone {
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: 键盘

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            var consumed = false
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                consumed = self.handleKey(event)
            }
            return consumed ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            M1Trace.log("esc during visible panel close")
            close()
            return true
        }

        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "1", "2", "3", "4", "5":
                guard let index = Int(characters), index >= 1, index <= PopoverTab.allCases.count else { return false }
                return selectTab(PopoverTab.allCases[index - 1])
            default: return false
            }
        }

        switch event.keyCode {
        case 123, 124:
            moveTab(by: event.keyCode == 124 ? 1 : -1)
            return true
        default:
            return false
        }
    }

    private func moveTab(by delta: Int) {
        let tabs = availableTabs
        guard let index = tabs.firstIndex(of: currentTab) else { return }
        let next = (index + delta + tabs.count) % tabs.count
        selectTab(tabs[next])
    }

    private func makeKey(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    // MARK: 位置

    private func reposition() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let width = PopoverLayout.panelWidth
        let height = PopoverTabRoute.route(for: currentTab).totalHeight
        let anchor = CGPoint(x: screen.visibleFrame.maxX - 60, y: screen.visibleFrame.maxY)
        let minX = screen.visibleFrame.minX + 8
        let maxX = screen.visibleFrame.maxX - width - 8
        let x = max(minX, min(anchor.x - width / 2, maxX))
        let y = anchor.y - 4 - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: M5 滚动探针

    private func scrollReport(toBottom: Bool) -> String {
        guard let root = panel?.contentViewController?.view else { return "no-view" }
        guard let scrollView = firstScrollView(in: root) else { return "no-scrollview" }
        guard let document = scrollView.documentView else { return "no-document" }
        let clip = scrollView.contentView
        let docHeight = document.bounds.height
        let viewHeight = clip.bounds.height
        let maxOffset = max(0, docHeight - viewHeight)
        if toBottom {
            clip.scroll(to: NSPoint(x: 0, y: maxOffset))
            scrollView.reflectScrolledClipView(clip)
        }
        let offset = clip.bounds.origin.y
        let clamped = offset >= -0.5 && offset <= maxOffset + 0.5
        return "docH=\(Int(docHeight)) viewH=\(Int(viewHeight)) max=\(Int(maxOffset)) offset=\(String(format: "%.1f", offset)) clamped=\(clamped ? "ok" : "failed")"
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func describe(_ frame: NSRect) -> String {
        "x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width)) h=\(Int(frame.height))"
    }
}

private final class M1Panel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        M1Driver.shared.close()
    }
}
