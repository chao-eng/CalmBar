import AppKit
import SwiftUI
import QuartzCore

// MARK: - 高度常量（§5.6 / §6.5.2）

enum SpikePanelMetrics {
    static let width: CGFloat = 320
    static let verticalPadding: CGFloat = 12
    static let headerHeight: CGFloat = 24
    static let sectionGap: CGFloat = 8
    static let tabBarHeight: CGFloat = 30
    static let footerHeight: CGFloat = 18
    static let chromeHeight: CGFloat = 120          // 12+24+8+30+8+8+18+12
    static let viewportMin: CGFloat = 200
    static let viewportMax: CGFloat = 400
    static let totalMin: CGFloat = 320              // chrome + 200
    static let totalMax: CGFloat = 520              // chrome + 400
    static let animationDuration: Double = 0.16
    static let anchorGap: CGFloat = 4               // 等价于现网 button.minY - height - 4
}

enum SpikeHeightCase: String, CaseIterable, Identifiable {
    case thermal
    case guardian
    case tools
    case overflow
    case compact

    var id: String { rawValue }

    var viewportHeight: CGFloat {
        switch self {
        case .thermal: return 300
        case .guardian: return 220
        case .tools: return 250
        case .overflow: return 460
        case .compact: return 160
        }
    }

    var clampedViewport: CGFloat {
        min(max(viewportHeight, SpikePanelMetrics.viewportMin), SpikePanelMetrics.viewportMax)
    }

    var totalHeight: CGFloat {
        SpikePanelMetrics.chromeHeight + clampedViewport
    }

    var baseTabID: String {
        switch self {
        case .thermal, .compact: return "thermal"
        case .guardian: return "guardian"
        case .tools, .overflow: return "tools"
        }
    }

    var hudLabel: String {
        switch self {
        case .thermal: return "温控"
        case .guardian: return "守护"
        case .tools: return "工具"
        case .overflow: return "超限"
        case .compact: return "紧凑"
        }
    }
}

// MARK: - 被测面板

final class SpikeStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        SpikeHeightDriver.shared.close()
    }
}

// MARK: - 高度驱动

@MainActor
final class SpikeHeightDriver: ObservableObject {
    static let shared = SpikeHeightDriver()

    @Published private(set) var currentCase: SpikeHeightCase = .thermal
    @Published private(set) var animationEnabled = true
    @Published private(set) var switchCount = 0
    @Published private(set) var frameReadout = "等待首次布局"

    private var panel: SpikeStatusPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var captureToken = 0
    private var screenIndex = 0
    private var isStressing = false
    private var stressStats: [ResizeStat] = []
    private var clickMonitorReadyAt: CFTimeInterval = 0
    private var autoMode = false

    private struct ResizeStat {
        let topDelta: CGFloat
        let durationMS: Double
        let failed: Bool
    }

    private init() {}

    // MARK: 生命周期

    func present() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        let panel = SpikeStatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: SpikePanelMetrics.width, height: SpikeHeightCase.thermal.totalHeight),
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
        panel.contentViewController = NSHostingController(rootView: SpikeHeightScene(driver: self))
        // 首帧 SwiftUI 尚未测量，必须显式回写尺寸，否则窗口会被压成 0 宽
        panel.setContentSize(NSSize(width: SpikePanelMetrics.width, height: SpikeHeightCase.thermal.totalHeight))
        self.panel = panel

        reposition(animated: false)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        startClickMonitor()
        startKeyMonitor()

        log("present case=thermal total=\(Int(SpikeHeightCase.thermal.totalHeight)) frame=\(describe(panel.frame)) screen=\(screenName())")
        frameReadout = readout(for: .thermal, frame: panel.frame)
        captureToken += 1
        scheduleCapture(for: .thermal, token: captureToken)

        if CommandLine.arguments.contains("--auto") {
            autoMode = true
            autoRun(exitWhenDone: CommandLine.arguments.contains("--exit"))
        }
    }

    // `--auto` 无人值守自检：逐档切换 + 20 次压力测试，结束后可选退出
    func autoRun(exitWhenDone: Bool) {
        log("auto start exitWhenDone=\(exitWhenDone)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(400))
            for item in SpikeHeightCase.allCases {
                self.select(item)
                try? await Task.sleep(for: .milliseconds(600))
            }
            try? await Task.sleep(for: .milliseconds(400))

            self.stressTest()
            while self.isStressing {
                try? await Task.sleep(for: .milliseconds(200))
            }
            self.log("auto complete currentCase=\(self.currentCase.rawValue) switches=\(self.switchCount)")
            if exitWhenDone {
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            }
        }
    }

    func close() {
        stopClickMonitor()
        stopKeyMonitor()
        panel?.orderOut(nil)
        log("close")
    }

    // MARK: 高度切换

    func select(_ target: SpikeHeightCase, animated: Bool? = nil) {
        guard let panel, panel.isVisible, !isStressing else { return }
        resize(to: target, animated: animated ?? animationEnabled)
    }

    func selectTab(_ tabID: String) {
        switch tabID {
        case "guardian": select(.guardian)
        case "tools": select(.tools)
        default: select(.thermal)
        }
    }

    func toggleAnimation() {
        animationEnabled.toggle()
        log("animationEnabled=\(animationEnabled)")
    }

    func cycleScreen() {
        guard !isStressing, !NSScreen.screens.isEmpty else { return }
        screenIndex = (screenIndex + 1) % NSScreen.screens.count
        reposition(animated: false)
        if let panel {
            frameReadout = readout(for: currentCase, frame: panel.frame)
            log("screen switch index=\(screenIndex) name=\(screenName()) frame=\(describe(panel.frame))")
        }
        scheduleCapture(for: currentCase, token: captureToken)
    }

    func stressTest() {
        guard let panel, panel.isVisible, !isStressing else { return }
        isStressing = true
        stressStats.removeAll()
        switchCount = 0
        log("stress start animation=\(animationEnabled)")

        let sequence: [SpikeHeightCase] = [.thermal, .guardian, .tools, .overflow, .compact]
        Task { @MainActor [weak self] in
            guard let self else { return }
            for index in 0..<20 {
                self.resize(to: sequence[index % sequence.count], animated: self.animationEnabled)
                try? await Task.sleep(for: .milliseconds(320))
            }
            try? await Task.sleep(for: .milliseconds(400))

            let maxDelta = self.stressStats.map(\.topDelta).max() ?? 0
            let maxDuration = self.stressStats.map(\.durationMS).max() ?? 0
            let failures = self.stressStats.filter(\.failed).count
            self.log("stress summary count=\(self.stressStats.count) maxTopDelta=\(maxDelta) maxDurationMS=\(Int(maxDuration)) failures=\(failures)")
            self.isStressing = false
            if let panel = self.panel {
                self.frameReadout = self.readout(for: self.currentCase, frame: panel.frame)
            }
            self.scheduleCapture(for: self.currentCase, token: self.captureToken)
        }
    }

    // MARK: 核心 resize：顶边是唯一不变量

    private func resize(to target: SpikeHeightCase, animated: Bool) {
        guard let panel else { return }

        let topBefore = panel.frame.maxY
        let expectedHeight = target.totalHeight
        let start = CACurrentMediaTime()
        let fittingBefore = panel.contentViewController?.view.fittingSize ?? .zero

        // 先换内容，再改 frame（避免先收缩窗口造成内容裁切闪烁）
        // 同时作废尚未触发的旧截图，避免旧档位任务拍到新内容
        captureToken += 1
        currentCase = target
        switchCount += 1
        panel.contentViewController?.preferredContentSize = NSSize(width: SpikePanelMetrics.width, height: expectedHeight)

        var frame = panel.frame
        frame.size = NSSize(width: SpikePanelMetrics.width, height: expectedHeight)
        frame.origin.y = topBefore - expectedHeight

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SpikePanelMetrics.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.finishResize(
                        target: target,
                        expectedHeight: expectedHeight,
                        topBefore: topBefore,
                        start: start,
                        fittingBefore: fittingBefore,
                        animated: true
                    )
                }
            }
        } else {
            panel.setFrame(frame, display: true)
            finishResize(
                target: target,
                expectedHeight: expectedHeight,
                topBefore: topBefore,
                start: start,
                fittingBefore: fittingBefore,
                animated: false
            )
        }
    }

    private func finishResize(
        target: SpikeHeightCase,
        expectedHeight: CGFloat,
        topBefore: CGFloat,
        start: CFTimeInterval,
        fittingBefore: NSSize,
        animated: Bool
    ) {
        guard let panel else { return }

        let frame = panel.frame
        let topAfter = frame.maxY
        let topDelta = abs(topAfter - topBefore)
        let durationMS = (CACurrentMediaTime() - start) * 1000
        let fittingAfter = panel.contentViewController?.view.fittingSize ?? .zero
        let failed = topDelta > 0.5 || abs(frame.height - expectedHeight) > 0.5
        let responder = panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"

        log("case=\(target.rawValue) target=\(Int(expectedHeight)) actual=\(Int(frame.height)) topBefore=\(topBefore) topAfter=\(topAfter) delta=\(topDelta) durationMS=\(Int(durationMS)) animated=\(animated) fitBefore=\(Int(fittingBefore.width))x\(Int(fittingBefore.height)) fitAfter=\(Int(fittingAfter.width))x\(Int(fittingAfter.height)) firstResponder=\(responder)")
        frameReadout = readout(for: target, frame: frame)

        if isStressing {
            stressStats.append(ResizeStat(topDelta: topDelta, durationMS: durationMS, failed: failed))
        }

        if !isStressing {
            scheduleCapture(for: target, token: captureToken)
        }
    }

    private func readout(for target: SpikeHeightCase, frame: NSRect) -> String {
        "case=\(target.rawValue) total=\(Int(frame.height)) topY=\(Int(frame.maxY)) switches=\(switchCount)"
    }

    // MARK: 位置

    private func reposition(animated: Bool) {
        guard let panel, let screen = resolvedScreen() else { return }
        let frame = targetFrame(on: screen)
        if animated {
            panel.animator().setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let anchor = anchorPoint(on: screen)
        let width = SpikePanelMetrics.width
        let minX = screen.visibleFrame.minX + 8
        let maxX = screen.visibleFrame.maxX - width - 8
        let x = max(minX, min(anchor.x - width / 2, maxX))
        let height = currentCase.totalHeight
        let y = anchor.y - SpikePanelMetrics.anchorGap - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func anchorPoint(on screen: NSScreen) -> CGPoint {
        // 用屏幕右上角模拟状态栏按钮，等价于 buttonRect.minY
        CGPoint(x: screen.visibleFrame.maxX - 60, y: screen.visibleFrame.maxY)
    }

    private var anchorRect: NSRect {
        guard let screen = resolvedScreen() else { return .zero }
        let anchor = anchorPoint(on: screen)
        return NSRect(x: anchor.x - 24, y: anchor.y - 24, width: 48, height: 24)
    }

    private func resolvedScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        return screens[min(screenIndex, screens.count - 1)]
    }

    private func screenName() -> String {
        resolvedScreen()?.localizedName ?? "nil"
    }

    // MARK: 外部点击

    private func startClickMonitor() {
        stopClickMonitor()
        // 启动瞬间可能收到坐标非法的幽灵事件，留 300ms 宽限期
        clickMonitorReadyAt = CACurrentMediaTime() + 0.3
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleGlobalClick()
            }
        }
    }

    private func stopClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func handleGlobalClick() {
        guard let panel, panel.isVisible else { return }
        let location = NSEvent.mouseLocation

        if CACurrentMediaTime() < clickMonitorReadyAt {
            log("click ignored during grace at \(describePoint(location))")
            return
        }
        // 坐标不落在任何屏幕上的事件视为幽灵事件，不参与关闭判定
        guard NSScreen.screens.contains(where: { $0.frame.contains(location) }) else {
            log("click ignored invalid location \(describePoint(location))")
            return
        }

        if panel.frame.contains(location) {
            log("click inside panel at \(describePoint(location)) keep")
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
        log("click outside at \(describePoint(location)) close")
        close()
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
        let isCommand = event.modifierFlags.contains(.command)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == 53 {
            log("esc during visible panel close")
            close()
            return true
        }

        guard isCommand else { return false }
        switch characters {
        case "1": select(.thermal)
        case "2": select(.guardian)
        case "3": select(.tools)
        case "4": select(.overflow)
        case "5": select(.compact)
        case "r": stressTest()
        default: return false
        }
        return true
    }

    // MARK: 自截图

    private func scheduleCapture(for target: SpikeHeightCase, token: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, token == self.captureToken, let panel = self.panel else { return }
            SpikeTrace.capture(panel, to: "/tmp/spike2_\(target.rawValue).png", mode: "height")
        }
    }

    // MARK: 日志辅助

    private func log(_ message: String) {
        SpikeTrace.log(message, mode: "height")
    }

    private func describe(_ frame: NSRect) -> String {
        "x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width)) h=\(Int(frame.height))"
    }

    private func describePoint(_ point: NSPoint) -> String {
        "x=\(Int(point.x)) y=\(Int(point.y))"
    }
}
