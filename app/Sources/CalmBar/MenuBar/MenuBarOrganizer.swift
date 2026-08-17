import AppKit
import Combine

@MainActor
public final class MenuBarOrganizer: ObservableObject {
    public static let shared = MenuBarOrganizer()

    @Published public private(set) var isCollapsed: Bool = false

    // 1. Permanent toggle button (< / >) - NEVER expanded so it ALWAYS stays visible on the menu bar
    private let btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    // 2. Separator item (/) - expands to 10,000pt when collapsed, pushing all items to its left off-screen
    private let btnSeparate = NSStatusBar.system.statusItem(withLength: 20.0)

    private let normalLength: CGFloat = 20.0
    private var collapseLength: CGFloat = 10_000.0

    private var autoCollapseTimer: Timer?
    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?
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
                self?.updateCollapseLength()
                if self?.isCollapsed == true {
                    self?.btnSeparate.length = self?.collapseLength ?? 10_000
                }
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
            button.toolTip = "CalmBar 展开/收起按钮 (点击展开/折叠，按住 ⌘ 拖动)"
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
            button.toolTip = "CalmBar 收纳分隔符：按住 ⌘ 将需要隐藏的图标拖到此分隔符左侧"
        }
        btnSeparate.autosaveName = "calmbar_separate"
        btnSeparate.isVisible = true
        btnSeparate.length = normalLength
    }

    private func setupObservers() {
        AppSettings.shared.$hoverToExpand
            .sink { [weak self] enabled in
                Task { @MainActor in
                    self?.setupHoverMonitor(enabled: enabled)
                }
            }
            .store(in: &cancellables)
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
        if isCollapsed {
            expandMenuBar()
        } else {
            collapseMenuBar()
        }
    }

    public func collapseMenuBar() {
        guard !isCollapsed else { return }
        updateCollapseLength()

        // Expand separator to 10,000pt to push all items to its left off-screen
        btnSeparate.length = collapseLength

        // Toggle button stays permanently visible in place and updates arrow to >
        if let button = btnExpandCollapse.button {
            let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Expand Menu Bar")
            img?.isTemplate = true
            button.image = img
        }

        isCollapsed = true
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    public func expandMenuBar() {
        guard isCollapsed else { return }

        // Restore separator width to 20pt
        btnSeparate.length = normalLength

        // Update toggle button arrow back to <
        if let button = btnExpandCollapse.button {
            let img = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Collapse Menu Bar")
            img?.isTemplate = true
            button.image = img
        }

        isCollapsed = false
        startAutoCollapseTimerIfNeeded()
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

    private func setupHoverMonitor(enabled: Bool) {
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
            hoverMonitor = nil
        }
        hoverDwellTimer?.invalidate()
        hoverDwellTimer = nil

        guard enabled else { return }

        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.isCollapsed && self.isMouseInMenuBar() else {
                    self.hoverDwellTimer?.invalidate()
                    self.hoverDwellTimer = nil
                    return
                }
                guard self.hoverDwellTimer == nil else { return }
                self.hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if self.isCollapsed && self.isMouseInMenuBar() {
                            self.expandMenuBar()
                        }
                    }
                }
            }
        }
    }
}
