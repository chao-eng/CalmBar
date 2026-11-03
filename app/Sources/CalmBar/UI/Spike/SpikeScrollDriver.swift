import AppKit
import SwiftUI
import QuartzCore

// MARK: - 常量（§6.5.1 Spike 3）

enum SpikeScrollMetrics {
    static let width: CGFloat = 320
    static let verticalPadding: CGFloat = 12
    static let headerHeight: CGFloat = 24
    static let sectionGap: CGFloat = 8
    static let tabBarHeight: CGFloat = 30
    static let footerHeight: CGFloat = 18
    static let viewportHeight: CGFloat = 400
    static let contentHeight: CGFloat = 600
    static let totalHeight: CGFloat = 520   // 120 chrome + 400 视口
    static let anchorGap: CGFloat = 4
    static let pageStep: CGFloat = 360
}

// MARK: - 面板（记录未被 ScrollView 消费的滚轮，验证不穿透）

final class SpikeScrollPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        SpikeScrollDriver.shared.close()
    }

    override func scrollWheel(with event: NSEvent) {
        SpikeScrollDriver.shared.noteBareScroll()
        super.scrollWheel(with: event)
    }
}

// MARK: - 滚动驱动

@MainActor
final class SpikeScrollDriver: ObservableObject {
    static let shared = SpikeScrollDriver()

    @Published private(set) var currentTab = "thermal"
    @Published private(set) var offsetReadout = "offset=0 max=0 wheel=0 key=0"
    @Published private(set) var wheelCount = 0
    @Published private(set) var keyConsumed = 0
    @Published private(set) var bareScrollCount = 0
    @Published private(set) var clickCloseCount = 0

    private var panel: SpikeScrollPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var captureToken = 0
    private var clickMonitorReadyAt: CFTimeInterval = 0
    private var autoMode = false

    private init() {}

    // MARK: 生命周期

    func present() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        let panel = SpikeScrollPanel(
            contentRect: NSRect(x: 0, y: 0, width: SpikeScrollMetrics.width, height: SpikeScrollMetrics.totalHeight),
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
        panel.contentViewController = NSHostingController(rootView: SpikeScrollScene(driver: self))
        // 首帧 SwiftUI 尚未测量，必须显式回写尺寸，否则窗口会被压成 0 宽
        panel.setContentSize(NSSize(width: SpikeScrollMetrics.width, height: SpikeScrollMetrics.totalHeight))
        self.panel = panel

        reposition()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        startMonitors()

        log("present total=\(Int(SpikeScrollMetrics.totalHeight)) frame=\(describe(panel.frame)) screen=\(screenName())")
        captureToken += 1
        scheduleCapture(to: "/tmp/spike3_initial.png", token: captureToken)

        if CommandLine.arguments.contains("--auto") {
            autoMode = true
            autoRun(exitWhenDone: CommandLine.arguments.contains("--exit"))
        }
    }

    func close() {
        stopMonitors()
        panel?.orderOut(nil)
        log("close")
    }

    func selectTab(_ id: String) {
        guard SpikeTab.phaseOne.contains(where: { $0.id == id }) else { return }
        currentTab = id
        log("tab select \(id) offset=\(Int(currentOffset()))")
    }

    // MARK: 滚动定位

    private func scrollView() -> NSScrollView? {
        findScrollView(in: panel?.contentView)
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    private func currentOffset() -> CGFloat {
        scrollView()?.contentView.bounds.origin.y ?? 0
    }

    /// 返回 (实际 offset, 最大 offset)
    @discardableResult
    private func setOffset(_ requested: CGFloat, label: String) -> (actual: CGFloat, max: CGFloat) {
        guard let scroll = scrollView() else {
            log("scroll label=\(label) scrollView=missing")
            return (0, 0)
        }
        let docHeight = scroll.documentView?.frame.height ?? 0
        let viewportHeight = scroll.contentView.bounds.height
        let maxOffset = max(0, docHeight - viewportHeight)
        let clamped = min(max(requested, 0), maxOffset)
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: clamped))
        scroll.reflectScrolledClipView(scroll.contentView)

        let actual = scroll.contentView.bounds.origin.y
        log("scroll label=\(label) request=\(Int(requested)) clamped=\(Int(clamped)) actual=\(Int(actual)) max=\(Int(maxOffset)) docH=\(Int(docHeight)) viewportH=\(Int(viewportHeight))")
        refreshReadout()
        return (actual, maxOffset)
    }

    private func refreshReadout() {
        let maxOffset = max(0, (scrollView()?.documentView?.frame.height ?? 0)
            - (scrollView()?.contentView.bounds.height ?? 0))
        offsetReadout = "offset=\(Int(currentOffset())) max=\(Int(maxOffset)) wheel=\(wheelCount) key=\(keyConsumed)"
    }

    func noteBareScroll() {
        bareScrollCount += 1
        log("bare scroll panel-level n=\(bareScrollCount)")
    }

    // MARK: 自动自检

    func autoRun(exitWhenDone: Bool) {
        log("auto start exitWhenDone=\(exitWhenDone)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 等 SwiftUI 完成首帧与 ScrollView 装配
            try? await Task.sleep(for: .milliseconds(800))

            let probes: [(label: String, value: CGFloat, path: String)] = [
                ("clampUnder", -50, "/tmp/spike3_clamp_under.png"),
                ("top", 0, "/tmp/spike3_top.png"),
                ("mid", 100, "/tmp/spike3_mid.png"),
                ("bottom", 600, "/tmp/spike3_bottom.png"),
                ("clampOver", 650, "/tmp/spike3_clamp_over.png")
            ]
            var maxOffsetSeen: CGFloat = 0
            var clampedOK = true

            for probe in probes {
                let result = self.setOffset(probe.value, label: probe.label)
                maxOffsetSeen = max(maxOffsetSeen, result.max)
                let expected = min(max(probe.value, 0), result.max)
                if abs(result.actual - expected) > 0.5 { clampedOK = false }
                try? await Task.sleep(for: .milliseconds(350))
                self.captureToken += 1
                SpikeTrace.capture(self.panel!, to: probe.path, mode: "scroll")
            }

            self.setOffset(0, label: "restoreTop")
            self.log("scroll summary probes=\(probes.count) maxOffset=\(Int(maxOffsetSeen)) clamp=\(clampedOK ? "ok" : "failed") wheelEvents=\(self.wheelCount) bareScroll=\(self.bareScrollCount) clickClose=\(self.clickCloseCount) keyConsumed=\(self.keyConsumed)")
            self.log("auto complete currentTab=\(self.currentTab) offset=\(Int(self.currentOffset()))")

            if exitWhenDone {
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: 位置

    private func reposition() {
        guard let panel, let screen = resolvedScreen() else { return }
        let width = SpikeScrollMetrics.width
        let height = SpikeScrollMetrics.totalHeight
        let anchor = CGPoint(x: screen.visibleFrame.maxX - 60, y: screen.visibleFrame.maxY)
        let minX = screen.visibleFrame.minX + 8
        let maxX = screen.visibleFrame.maxX - width - 8
        let x = max(minX, min(anchor.x - width / 2, maxX))
        let y = anchor.y - SpikeScrollMetrics.anchorGap - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private var anchorRect: NSRect {
        guard let screen = resolvedScreen() else { return .zero }
        let anchor = CGPoint(x: screen.visibleFrame.maxX - 60, y: screen.visibleFrame.maxY)
        return NSRect(x: anchor.x - 24, y: anchor.y - 24, width: 48, height: 24)
    }

    private func resolvedScreen() -> NSScreen? {
        NSScreen.screens.first
    }

    private func screenName() -> String {
        resolvedScreen()?.localizedName ?? "nil"
    }

    // MARK: 监听

    private func startMonitors() {
        stopMonitors()

        clickMonitorReadyAt = CACurrentMediaTime() + 0.3
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleGlobalClick()
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // NSEvent 非 Sendable，assumeIsolated 不能回传事件；用本地标记在同步闭包内取结果
            var consumed = false
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                consumed = self.handleKey(event)
            }
            return consumed ? nil : event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleScrollEvent(event)
            }
            return event
        }
    }

    private func stopMonitors() {
        for monitor in [clickMonitor, keyMonitor, scrollMonitor] where monitor != nil {
            NSEvent.removeMonitor(monitor!)
        }
        clickMonitor = nil
        keyMonitor = nil
        scrollMonitor = nil
    }

    private func handleGlobalClick() {
        guard let panel, panel.isVisible else { return }
        let location = NSEvent.mouseLocation

        if CACurrentMediaTime() < clickMonitorReadyAt {
            log("click ignored during grace at \(describePoint(location))")
            return
        }
        guard NSScreen.screens.contains(where: { $0.frame.contains(location) }) else {
            log("click ignored invalid location \(describePoint(location))")
            return
        }
        if panel.frame.contains(location) {
            log("click inside panel at \(describePoint(location)) keep offset=\(Int(currentOffset()))")
            return
        }
        if anchorRect.contains(location) {
            log("click anchor at \(describePoint(location)) keep")
            return
        }
        if autoMode {
            log("click ignored in auto mode at \(describePoint(location))")
            return
        }
        clickCloseCount += 1
        log("click outside at \(describePoint(location)) close")
        close()
    }

    private func handleScrollEvent(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }
        guard event.window === panel else {
            log("wheel other window=\(String(describing: event.window)) deltaY=\(Int(event.scrollingDeltaY))")
            return
        }
        wheelCount += 1
        if wheelCount <= 40 {
            log("wheel n=\(wheelCount) phase=\(event.phase.rawValue) momentum=\(event.momentumPhase.rawValue) deltaY=\(Int(event.scrollingDeltaY)) inverted=\(event.isDirectionInvertedFromDevice)")
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            self?.refreshReadout()
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let isCommand = event.modifierFlags.contains(.command)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == 53 {
            keyConsumed += 1
            log("esc during visible panel close offset=\(Int(currentOffset()))")
            close()
            return true
        }

        if isCommand {
            switch characters {
            case "1":
                keyConsumed += 1
                setOffset(0, label: "cmd1-top")
                return true
            case "2":
                keyConsumed += 1
                setOffset(SpikeScrollMetrics.contentHeight / 2, label: "cmd2-mid")
                return true
            case "3":
                keyConsumed += 1
                setOffset(SpikeScrollMetrics.contentHeight, label: "cmd3-bottom")
                return true
            default:
                return false
            }
        }

        switch event.keyCode {
        case 116: // PageUp
            keyConsumed += 1
            setOffset(currentOffset() - SpikeScrollMetrics.pageStep, label: "pageUp")
            return true
        case 121: // PageDown
            keyConsumed += 1
            setOffset(currentOffset() + SpikeScrollMetrics.pageStep, label: "pageDown")
            return true
        case 115: // Home
            keyConsumed += 1
            setOffset(0, label: "home")
            return true
        case 119: // End
            keyConsumed += 1
            setOffset(SpikeScrollMetrics.contentHeight, label: "end")
            return true
        default:
            return false
        }
    }

    // MARK: 自截图

    private func scheduleCapture(to path: String, token: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, token == self.captureToken, let panel = self.panel else { return }
            SpikeTrace.capture(panel, to: path, mode: "scroll")
        }
    }

    // MARK: 日志辅助

    private func log(_ message: String) {
        SpikeTrace.log(message, mode: "scroll")
    }

    private func describe(_ frame: NSRect) -> String {
        "x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width)) h=\(Int(frame.height))"
    }

    private func describePoint(_ point: NSPoint) -> String {
        "x=\(Int(point.x)) y=\(Int(point.y))"
    }
}
