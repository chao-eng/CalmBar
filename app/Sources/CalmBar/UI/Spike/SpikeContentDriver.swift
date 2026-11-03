import AppKit
import SwiftUI

// MARK: - 内容骨架驱动（§6.5 项 4–7）

@MainActor
final class SpikeContentDriver: ObservableObject {
    static let shared = SpikeContentDriver()

    @Published private(set) var currentTab = "thermal"
    @Published private(set) var english = false
    @Published private(set) var largeText = false
    @Published private(set) var gridWidth: CGFloat = 0
    @Published private(set) var statusReadout = "grid=-- appears=t0/g0/o0"

    let a11yMode: Bool
    let reduceMotion: Bool
    let increaseContrast: Bool

    private(set) var fontScale: CGFloat = 1.0
    private var appearCounts: [String: Int] = [:]
    private var dataRefreshCount = 0
    private var switchCount = 0

    private var panel: SpikeStatusPanel?
    private var keyMonitor: Any?
    private let isDarkLaunch = CommandLine.arguments.contains("--dark")

    private init() {
        let args = CommandLine.arguments
        a11yMode = args.contains("--a11y")
        reduceMotion = args.contains("--reduce-motion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        increaseContrast = args.contains("--increase-contrast") || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        if let index = args.firstIndex(of: "--lang"), index + 1 < args.count, args[index + 1] == "en" {
            english = true
        }
        if args.contains("--large-text") {
            largeText = true
            fontScale = 1.25
        }
    }

    // MARK: 生命周期

    func present() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        if isDarkLaunch {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        let panel = SpikeStatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: SpikeContentMetrics.width, height: SpikeContentMetrics.totalHeight),
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
        panel.contentViewController = NSHostingController(rootView: SpikeContentScene(driver: self))
        // 首帧 SwiftUI 尚未测量，必须显式回写尺寸，否则窗口会被压成 0 宽
        panel.setContentSize(NSSize(width: SpikeContentMetrics.width, height: SpikeContentMetrics.totalHeight))
        self.panel = panel

        reposition()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        startKeyMonitor()

        log("present total=\(Int(SpikeContentMetrics.totalHeight)) viewport=\(Int(SpikeContentMetrics.viewportHeight)) frame=\(describe(panel.frame)) screen=\(screenName()) dark=\(isDarkLaunch) english=\(english) largeText=\(largeText) a11y=\(a11yMode) reduceMotion=\(reduceMotion) increaseContrast=\(increaseContrast)")
        log("grid expected=\(Int(SpikeContentMetrics.gridWidth)) tile=\(Int(SpikeContentMetrics.tileWidth))x\(Int(SpikeContentMetrics.tileHeight)) cols=\(SpikeContentMetrics.columns) spacing=\(Int(SpikeContentMetrics.tileSpacing))")
        refreshReadout()

        if CommandLine.arguments.contains("--auto") {
            if a11yMode {
                autoA11yRun(exitWhenDone: CommandLine.arguments.contains("--exit"))
            } else {
                autoRun(exitWhenDone: CommandLine.arguments.contains("--exit"))
            }
        }
    }

    func close() {
        stopKeyMonitor()
        panel?.orderOut(nil)
        log("close")
    }

    // MARK: 分区切换与计数

    func selectTab(_ id: String) {
        guard SpikeTab.phaseOne.contains(where: { $0.id == id }), currentTab != id else { return }
        currentTab = id
        switchCount += 1
        log("tab select \(id) n=\(switchCount)")
        refreshReadout()
    }

    func noteAppear(_ id: String) {
        appearCounts[id, default: 0] += 1
        log("appear \(id) count=\(appearCounts[id, default: 0])")
        refreshReadout()
    }

    func noteGridWidth(_ width: CGFloat) {
        gridWidth = width
        log("grid measured width=\(Int(width)) expected=\(Int(SpikeContentMetrics.gridWidth)) overflow=\(width > SpikeContentMetrics.gridWidth + 0.5 ? "yes" : "no")")
        refreshReadout()
    }

    // MARK: 自动自检

    func autoRun(exitWhenDone: Bool) {
        log("auto start exitWhenDone=\(exitWhenDone)")
        Task { @MainActor [weak self] in
            guard let self, let panel = self.panel else { return }
            // 等首帧测量与网格宽度回传
            try? await Task.sleep(for: .milliseconds(800))

            let tabs = ["thermal", "guardian", "tools"]
            for index in 0..<30 {
                self.selectTab(tabs[index % tabs.count])
                try? await Task.sleep(for: .milliseconds(220))
            }
            try? await Task.sleep(for: .milliseconds(300))

            let appears = self.appearCountsString()
            let truncation = self.measureTruncation()
            self.log("appear counts \(appears) switches=\(self.switchCount) samplingDelta=\(self.dataRefreshCount)")
            self.log("truncation zh=\(truncation.zh) en=\(truncation.en) generated=true scale=\(self.fontScale)")

            let prefix = self.isDarkLaunch ? "/tmp/spike4_dark" : "/tmp/spike4"
            var largeTruncation = (zh: 0, en: 0)

            // 三入口截图
            self.selectTab("thermal")
            try? await Task.sleep(for: .milliseconds(350))
            SpikeTrace.capture(panel, to: "\(prefix)_thermal.png", mode: "content")

            self.selectTab("guardian")
            try? await Task.sleep(for: .milliseconds(350))
            SpikeTrace.capture(panel, to: "\(prefix)_guardian.png", mode: "content")

            self.selectTab("tools")
            try? await Task.sleep(for: .milliseconds(350))
            SpikeTrace.capture(panel, to: "\(prefix)_tools.png", mode: "content")

            // 英文标签
            self.english = true
            try? await Task.sleep(for: .milliseconds(350))
            SpikeTrace.capture(panel, to: "\(prefix)_en.png", mode: "content")
            self.english = false

            // 放大文字
            self.largeText = true
            self.fontScale = 1.25
            largeTruncation = self.measureTruncation()
            try? await Task.sleep(for: .milliseconds(350))
            SpikeTrace.capture(panel, to: "\(prefix)_large.png", mode: "content")
            self.largeText = false
            self.fontScale = 1.0
            self.log("truncation large zh=\(largeTruncation.zh) en=\(largeTruncation.en) scale=1.25")

            // 深色外观
            if self.isDarkLaunch {
                self.selectTab("thermal")
                try? await Task.sleep(for: .milliseconds(350))
                SpikeTrace.capture(panel, to: "/tmp/spike4_dark.png", mode: "content")
            }

            self.dumpAccessibility()

            let overflow = self.gridWidth > SpikeContentMetrics.gridWidth + 0.5
            self.log("content summary gridWidth=\(Int(self.gridWidth)) expected=\(Int(SpikeContentMetrics.gridWidth)) cols=\(SpikeContentMetrics.columns) overflow=\(overflow ? 1 : 0) switches=\(self.switchCount) appearCounts=\(appears) samplingDelta=\(self.dataRefreshCount) truncationZh=\(truncation.zh) truncationEn=\(truncation.en) truncationLargeZh=\(largeTruncation.zh) truncationLargeEn=\(largeTruncation.en)")
            self.log("auto complete currentTab=\(self.currentTab)")

            if exitWhenDone {
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: 无障碍自动自检

    func autoA11yRun(exitWhenDone: Bool) {
        log("a11y auto start exitWhenDone=\(exitWhenDone)")
        Task { @MainActor [weak self] in
            guard let self, let panel = self.panel else { return }
            try? await Task.sleep(for: .milliseconds(900))
            self.selectTab("tools")
            try? await Task.sleep(for: .milliseconds(400))

            let ax = SpikeA11yProbe.dumpAX(to: "/tmp/spike5_ax.txt")
            self.log("ax dump \(ax.status) nodes=\(ax.nodes) path=/tmp/spike5_ax.txt")
            let order = SpikeA11yProbe.orderReport()
            self.log("order \(order)")

            var orderOK = false
            if order.contains("ok=true") { orderOK = true }

            // 通过 AX 聚焦：胶囊 → 磁贴 → 关闭按钮，验证系统焦点环
            let focusTargets: [(label: String, description: String, path: String)] = [
                ("pill", "温控，", "/tmp/spike5_focus_pill.png"),
                ("tile", "应用去隔离", "/tmp/spike5_focus_tile.png"),
                ("close", "关闭面板", "/tmp/spike5_focus_close.png")
            ]
            var focusStatuses: [String] = []
            for target in focusTargets {
                let status = SpikeA11yProbe.focus(descriptionPrefix: target.description)
                try? await Task.sleep(for: .milliseconds(420))
                self.logFocusState(target.label)
                self.log("ax focus label=\(target.label) desc=\(target.description) status=\(status)")
                focusStatuses.append("\(target.label):\(status)")
                SpikeTrace.capture(panel, to: target.path, mode: "a11y")
            }

            // 合成按键直接走 handleKey，验证映射逻辑（不含系统路由）
            var keyResults: [String] = []
            if let event = self.makeKey("2", keyCode: 18, flags: .command) {
                keyResults.append("cmd2=\(self.handleKey(event)) tab=\(self.currentTab)")
            }
            if let event = self.makeKey("", keyCode: 124) {
                keyResults.append("right=\(self.handleKey(event)) tab=\(self.currentTab)")
            }
            if let event = self.makeKey(" ", keyCode: 49) {
                keyResults.append("space=\(self.handleKey(event))")
            }
            if let event = self.makeKey("", keyCode: 48) {
                let before = self.responderName()
                let consumed = self.handleKey(event)
                // handleKey 返回 false 时按系统路由真实派发，观察焦点是否移动
                self.panel?.sendEvent(event)
                keyResults.append("tab=\(consumed)(system) responder=\(before)->\(self.responderName())")
            }
            self.log("keyboard \(keyResults.joined(separator: " | "))")

            self.log("reduceMotion=\(self.reduceMotion) pillDuration=\(self.reduceMotion ? "0ms" : "120ms")")
            self.log("increaseContrast=\(self.increaseContrast) borderOpacity=\(self.increaseContrast ? "0.32" : "0.12")")
            if self.reduceMotion || self.increaseContrast {
                SpikeTrace.capture(panel, to: "/tmp/spike5_prefs.png", mode: "a11y")
            }

            // Esc 最后执行，会关闭面板
            var escConsumed = false
            if let event = self.makeKey("\u{1b}", keyCode: 53) {
                escConsumed = self.handleKey(event)
            }
            self.log("esc consumed=\(escConsumed) visible=\(self.panel?.isVisible ?? false)")

            self.log("a11y summary axStatus=\(ax.status) axNodes=\(ax.nodes) order=\(orderOK ? "ok" : "failed") focusShots=3 keys=\(keyResults.count) reduceMotion=\(self.reduceMotion) contrast=\(self.increaseContrast) esc=\(escConsumed ? "ok" : "failed")")
            self.log("a11y auto complete")

            if exitWhenDone {
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            }
        }
    }

    private func logFocusState(_ label: String) {
        log("focus label=\(label) firstResponder=\(responderName()) keyWindow=\(panel?.isKeyWindow ?? false)")
    }

    private func responderName() -> String {
        panel?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
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

    // MARK: 文本截断量算

    private func measureTruncation() -> (zh: Int, en: Int) {
        let available = SpikeContentMetrics.labelAvailableWidth
        // 标签最小可缩到 0.7 倍，仍超过可用宽则视为截断
        let minScale: CGFloat = 0.7
        func count(english: Bool) -> Int {
            SpikeToolTile.all.filter { tile in
                let text: String = english ? tile.titleEN : tile.titleZH
                let font = NSFont.systemFont(ofSize: 10 * fontScale)
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                return width * minScale > available
            }.count
        }
        return (count(english: false), count(english: true))
    }

    private func appearCountsString() -> String {
        let tabs = ["thermal", "guardian", "tools"]
        return tabs.map { "\($0):\(appearCounts[$0, default: 0])" }.joined(separator: ",")
    }

    private func refreshReadout() {
        statusReadout = "grid=\(Int(gridWidth)) appears=t\(appearCounts["thermal", default: 0])/g\(appearCounts["guardian", default: 0])/o\(appearCounts["tools", default: 0])"
    }

    // MARK: 无障碍树导出

    private func dumpAccessibility() {
        guard let root = panel?.contentView else { return }
        var lines: [String] = []
        collectAX(root, depth: 0, lines: &lines)
        let text = lines.prefix(240).joined(separator: "\n")
        let path = "/tmp/spike4_ax.txt"
        do {
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            log("ax dump path=\(path) lines=\(lines.count)")
        } catch {
            log("ax dump failed: \(error)")
        }
    }

    private func collectAX(_ element: Any, depth: Int, lines: inout [String]) {
        guard depth < 6, let view = element as? NSView else { return }
        let role = view.accessibilityRole()?.rawValue ?? "-"
        let label = view.accessibilityLabel() ?? ""
        let value = view.accessibilityValue().map { String(describing: $0) } ?? ""
        lines.append(String(repeating: "  ", count: depth) + "role=\(role) label=\(label) value=\(value)")
        for sub in view.subviews {
            collectAX(sub, depth: depth + 1, lines: &lines)
        }
        if let children = view.accessibilityChildren() {
            for child in children {
                collectAX(child, depth: depth + 1, lines: &lines)
            }
        }
    }

    // MARK: 键盘

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // NSEvent 非 Sendable，assumeIsolated 不能回传事件；用本地标记在同步闭包内取结果
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
            log("esc during visible panel close")
            close()
            return true
        }

        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "1": selectTab("thermal"); return true
            case "2": selectTab("guardian"); return true
            case "3": selectTab("tools"); return true
            default: return false
            }
        }

        switch event.keyCode {
        case 123, 124: // ← / →
            moveTab(by: event.keyCode == 124 ? 1 : -1)
            return true
        case 49, 36: // Space / Return：激活 AX 当前焦点元素
            let focused = SpikeA11yProbe.focusedDescription()
            log("activate via \(event.keyCode == 49 ? "space" : "return") focused=\(focused)")
            return focused != "none"
        case 48: // Tab / Shift-Tab：交给系统移动焦点
            let responder = panel?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            log("tab key system-handled firstResponder=\(responder)")
            return false
        default:
            return false
        }
    }

    private func moveTab(by delta: Int) {
        let tabs = SpikeTab.phaseOne
        guard let index = tabs.firstIndex(where: { $0.id == currentTab }) else { return }
        let next = (index + delta + tabs.count) % tabs.count
        selectTab(tabs[next].id)
    }

    // MARK: 位置

    private func reposition() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let width = SpikeContentMetrics.width
        let height = SpikeContentMetrics.totalHeight
        let anchor = CGPoint(x: screen.visibleFrame.maxX - 60, y: screen.visibleFrame.maxY)
        let minX = screen.visibleFrame.minX + 8
        let maxX = screen.visibleFrame.maxX - width - 8
        let x = max(minX, min(anchor.x - width / 2, maxX))
        let y = anchor.y - 4 - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func screenName() -> String {
        NSScreen.screens.first?.localizedName ?? "nil"
    }

    // MARK: 日志辅助

    private func log(_ message: String) {
        SpikeTrace.log(message, mode: "content")
    }

    private func describe(_ frame: NSRect) -> String {
        "x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width)) h=\(Int(frame.height))"
    }
}
