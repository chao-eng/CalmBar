import AppKit
import Combine

@MainActor
public final class MenuBarOrganizer: ObservableObject {
    public static let shared = MenuBarOrganizer()

    @Published public private(set) var isCollapsed: Bool = false

    // 1. Permanent toggle button (< / >) - NEVER expanded so it ALWAYS stays visible on the menu bar
    private let btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    // 2. 分隔符（/）— 收纳时加宽，把左侧图标移出菜单栏布局
    private let btnSeparate = NSStatusBar.system.statusItem(withLength: 20.0)

    private let normalLength: CGFloat = 20.0
    private var collapseLength: CGFloat = 10_000.0
    private var calibratedCollapseLength: CGFloat?
    private var restingSeparatorArrowGap: CGFloat?
    private var collapseCalibrationGeneration = 0
    private var isCollapseCalibrating = false
    private var isRecalibrationScheduled = false
    private let collapseCalibrationInterval: TimeInterval = 0.25
    private let collapseCalibrationTolerance: CGFloat = 8

    private var autoCollapseTimer: Timer?
    private var hoverMonitor: Any?
    private var hoverLocalMonitor: Any?
    private var hoverDwellTimer: Timer?

    // 悬停感应区以收纳箭头为中心，向左右各放宽的像素数
    private let hoverTriggerHorizontalPadding: CGFloat = 16.0
    private var cancellables = Set<AnyCancellable>()
    private var isToggling = false

    private init() {
        updateCollapseLength()
        setupUI()
        setupObservers()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenParametersChanged()
            }
        }

        // 切换前台应用会改变菜单栏可用空间；若分隔符被系统移出布局，重新校准。
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.recalibrateCollapsedMenuBarIfSeparatorMoved()
            }
        }

        // Default to collapsed state on app launch after initial layout settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            Task { @MainActor in
                self?.collapseMenuBar()
            }
        }
    }

    private func updateCollapseLength() {
        let maxScreenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 2000.0
        collapseLength = max(2000.0, min(maxScreenWidth * 3, 10_000.0))
    }

    private func setupUI() {
        // 1. Setup Toggle Button (< / >)
        if let button = btnExpandCollapse.button {
            let img = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Toggle Menu Bar")
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(handleExpandCollapseClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "檐下展开/收起按钮 (点击展开/折叠，按住 ⌘ 拖动)"
        }
        btnExpandCollapse.autosaveName = "calmbar_expandcollapse"
        btnExpandCollapse.isVisible = true

        // 2. Setup Separator Item (/)
        if let button = btnSeparate.button {
            let img = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Separator")
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(handleExpandCollapseClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "檐下收纳分隔符：按住 ⌘ 将需要隐藏的图标拖到此分隔符左侧"
        }
        btnSeparate.autosaveName = "calmbar_separate"
        btnSeparate.isVisible = true
        btnSeparate.length = normalLength
    }

    private func setupObservers() {
        AppSettings.shared.$menuBarOrganizerEnabled
            .sink { [weak self] enabled in
                Task { @MainActor in
                    self?.updateOrganizerEnabled(enabled)
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$hoverToExpand
            .sink { [weak self] enabled in
                Task { @MainActor in
                    self?.setupHoverMonitor(enabled: enabled)
                }
            }
            .store(in: &cancellables)
    }

    private func updateOrganizerEnabled(_ enabled: Bool) {
        if !enabled {
            expandMenuBar()
            btnExpandCollapse.isVisible = false
            btnSeparate.isVisible = false
        } else {
            btnExpandCollapse.isVisible = true
            btnSeparate.isVisible = true
            collapseMenuBar()
        }
    }

    @objc private func handleExpandCollapseClick() {
        guard !isToggling else { return }
        isToggling = true

        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            StatusBarManager.shared.openSettingsWindow()
            isToggling = false
            return
        }

        toggleExpandCollapse()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.isToggling = false
        }
    }

    public func toggleExpandCollapse() {
        guard AppSettings.shared.menuBarOrganizerEnabled else { return }
        if isCollapsed {
            expandMenuBar()
        } else {
            collapseMenuBar()
        }
    }

    public func collapseMenuBar() {
        guard AppSettings.shared.menuBarOrganizerEnabled, !isCollapsed else { return }
        updateCollapseLength()
        cancelCollapseCalibration()

        // macOS 27 会移除超长状态项；首次收纳先保持展开宽度，再探测系统接受的上限。
        btnSeparate.length = calibratedCollapseLength ?? (needsCollapseLengthCalibration ? normalLength : collapseLength)
        setCollapseButtonImage(collapsed: true)

        isCollapsed = true
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        if needsCollapseLengthCalibration && calibratedCollapseLength == nil {
            beginCollapseCalibration()
        }
    }

    public func expandMenuBar() {
        guard isCollapsed else { return }
        cancelCollapseCalibration()

        btnSeparate.length = normalLength
        setCollapseButtonImage(collapsed: false)
        isCollapsed = false
        startAutoCollapseTimerIfNeeded()
    }

    private var needsCollapseLengthCalibration: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }

    private func setCollapseButtonImage(collapsed: Bool) {
        guard let button = btnExpandCollapse.button else { return }
        let symbol = collapsed ? "chevron.right" : "chevron.left"
        let description = collapsed ? "Expand Menu Bar" : "Collapse Menu Bar"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
    }

    private func beginCollapseCalibration() {
        cancelCollapseCalibration()
        Task { [weak self] in
            await self?.calibrateCollapseLength()
        }
    }

    private func calibrateCollapseLength() async {
        let generation = collapseCalibrationGeneration
        var restingGap: CGFloat?

        // 刚启动或切换屏幕时，状态项可能还没拿到菜单栏位置；短暂重试而不是从 x=0 误判。
        for _ in 0..<12 {
            guard isCollapseCalibrationCurrent(generation) else { return }
            if let gap = separatorArrowGap(), isSeparatorPlaced() {
                restingGap = gap
                break
            }
            await waitForMenuBarLayout()
        }

        guard let restingGap else {
            finishCollapseCalibrationWithoutAcceptedLength(reason: "separator is not laid out")
            return
        }

        restingSeparatorArrowGap = restingGap
        var search = MenuBarCollapseLengthSearch(expandedLength: normalLength, upperBound: collapseLength)
        isCollapseCalibrating = true

        while let probe = search.nextProbe() {
            btnSeparate.length = probe
            await waitForMenuBarLayout()
            guard isCollapseCalibrationCurrent(generation), isCollapseCalibrating else { return }

            let accepted: Bool
            if let gap = separatorArrowGap() {
                accepted = abs(gap - restingGap) <= collapseCalibrationTolerance
            } else {
                accepted = false
            }
            search.record(accepted: accepted)
        }

        await finishCollapseCalibration(search: search, generation: generation)
    }

    private func finishCollapseCalibration(search: MenuBarCollapseLengthSearch, generation: Int) async {
        isCollapseCalibrating = false

        guard search.foundInflatedLength else {
            finishCollapseCalibrationWithoutAcceptedLength(reason: "all inflated lengths were rejected")
            return
        }

        let length = search.calibratedLength
        calibratedCollapseLength = length
        btnSeparate.length = length

        // 最终安全余量也要复核一次；若刚好被拒绝则恢复展开并重新校准。
        await waitForMenuBarLayout()
        guard isCollapseCalibrationCurrent(generation),
              let gap = separatorArrowGap(),
              let restingGap = restingSeparatorArrowGap else { return }

        if abs(gap - restingGap) <= collapseCalibrationTolerance {
            NSLog("[MenuBarOrganizer] macOS 27 收纳宽度校准完成：%.1fpt，探测 %d 次", length, search.probeCount)
        } else {
            calibratedCollapseLength = nil
            recalibrateCollapsedMenuBar()
        }
    }

    private func waitForMenuBarLayout() async {
        try? await Task.sleep(nanoseconds: UInt64(collapseCalibrationInterval * 1_000_000_000))
    }

    private func isCollapseCalibrationCurrent(_ generation: Int) -> Bool {
        needsCollapseLengthCalibration && collapseCalibrationGeneration == generation && isCollapsed
    }

    private func finishCollapseCalibrationWithoutAcceptedLength(reason: String) {
        cancelCollapseCalibration()
        calibratedCollapseLength = nil
        restingSeparatorArrowGap = nil
        btnSeparate.length = normalLength
        setCollapseButtonImage(collapsed: false)
        isCollapsed = false
        NSLog("[MenuBarOrganizer] macOS 27 收纳宽度校准失败：%@", reason)
        startAutoCollapseTimerIfNeeded()
    }

    private func cancelCollapseCalibration() {
        collapseCalibrationGeneration += 1
        isCollapseCalibrating = false
    }

    private func separatorArrowGap() -> CGFloat? {
        guard let separatorFrame = btnSeparate.button?.window?.frame,
              let arrowFrame = btnExpandCollapse.button?.window?.frame,
              separatorFrame.width > 0,
              arrowFrame.width > 0 else { return nil }

        if NSApp.userInterfaceLayoutDirection == .leftToRight {
            return abs(separatorFrame.maxX - arrowFrame.minX)
        }
        return abs(arrowFrame.maxX - separatorFrame.minX)
    }

    private func isSeparatorPlaced() -> Bool {
        guard let frame = btnSeparate.button?.window?.frame else { return false }
        return NSScreen.screens.contains { screen in
            frame.minX >= screen.frame.minX + max(frame.width, 1)
                && frame.maxX <= screen.frame.maxX + collapseCalibrationTolerance
                && frame.minY >= screen.visibleFrame.maxY - collapseCalibrationTolerance
                && frame.midY <= screen.frame.maxY + collapseCalibrationTolerance
        }
    }

    private func handleScreenParametersChanged() {
        updateCollapseLength()
        guard needsCollapseLengthCalibration, AppSettings.shared.menuBarOrganizerEnabled else { return }
        calibratedCollapseLength = nil
        restingSeparatorArrowGap = nil
        recalibrateCollapsedMenuBar()
    }

    private func recalibrateCollapsedMenuBarIfSeparatorMoved() {
        guard needsCollapseLengthCalibration,
              AppSettings.shared.menuBarOrganizerEnabled,
              isCollapsed,
              !isCollapseCalibrating,
              !isRecalibrationScheduled,
              let gap = separatorArrowGap(),
              let restingGap = restingSeparatorArrowGap,
              abs(gap - restingGap) > collapseCalibrationTolerance else { return }

        recalibrateCollapsedMenuBar()
    }

    private func recalibrateCollapsedMenuBar() {
        guard needsCollapseLengthCalibration,
              AppSettings.shared.menuBarOrganizerEnabled,
              !isRecalibrationScheduled else { return }

        isRecalibrationScheduled = true
        calibratedCollapseLength = nil
        restingSeparatorArrowGap = nil
        if isCollapsed {
            expandMenuBar()
        } else {
            cancelCollapseCalibration()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isRecalibrationScheduled = false
                guard AppSettings.shared.menuBarOrganizerEnabled else { return }
                self.collapseMenuBar()
            }
        }
    }

    public func startAutoCollapseTimerIfNeeded() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        guard AppSettings.shared.autoCollapseEnabled else { return }
        let delay = max(1.0, AppSettings.shared.autoCollapseDelay)

        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, AppSettings.shared.autoCollapseEnabled, !self.isCollapsed else { return }
                if !self.isMouseInMenuBar() {
                    self.collapseMenuBar()
                } else {
                    self.startAutoCollapseTimerIfNeeded()
                }
            }
        }
    }

    private func isMouseInMenuBar() -> Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    /// 收纳箭头的悬停感应区：以箭头按钮自身窗口为基准，左右各放宽一段距离
    private func hoverTriggerRect() -> NSRect? {
        guard btnExpandCollapse.isVisible, let window = btnExpandCollapse.button?.window else { return nil }
        return window.frame.insetBy(dx: -hoverTriggerHorizontalPadding, dy: 0)
    }

    private func isMouseNearExpandTrigger() -> Bool {
        guard let rect = hoverTriggerRect() else { return false }
        return rect.contains(NSEvent.mouseLocation)
    }

    private func cancelHoverDwell() {
        hoverDwellTimer?.invalidate()
        hoverDwellTimer = nil
    }

    /// 仅在鼠标移动到收纳箭头附近时才计时展开，避免整个菜单栏任意位置都触发
    private func handleHoverMove() {
        guard AppSettings.shared.menuBarOrganizerEnabled,
              isCollapsed,
              isMouseNearExpandTrigger() else {
            cancelHoverDwell()
            return
        }
        guard hoverDwellTimer == nil else { return }

        hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.hoverDwellTimer = nil
                if self.isCollapsed && self.isMouseNearExpandTrigger() {
                    self.expandMenuBar()
                }
            }
        }
    }

    private func setupHoverMonitor(enabled: Bool) {
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
            hoverMonitor = nil
        }
        if let monitor = hoverLocalMonitor {
            NSEvent.removeMonitor(monitor)
            hoverLocalMonitor = nil
        }
        cancelHoverDwell()

        guard enabled else { return }

        // 全局监听覆盖其他应用占用的菜单栏区域
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.handleHoverMove()
            }
        }

        // 本地监听覆盖光标落在本应用状态栏按钮上的情况（全局监听收不到发给自身的事件）
        hoverLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleHoverMove()
            }
            return event
        }
    }
}
