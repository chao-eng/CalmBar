import Combine
import Foundation

// MARK: - 生产面板状态（分区可用性 / 选中持久化 / 回退规则）

@MainActor
final class PopoverPanelModel: ObservableObject {
    @Published private(set) var currentTab: PopoverTab
    @Published private(set) var availableTabs: [PopoverTab]

    /// 分区切换完成后通知宿主刷新面板高度（由 StatusBarManager 接线）
    var onTabChange: ((PopoverTab) -> Void)?

    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        let tabs = Self.availableTabs(from: settings)
        availableTabs = tabs
        let saved = PopoverTab(rawValue: settings.popoverSelectedTab)
        let restored = saved.flatMap { tabs.contains($0) ? $0 : nil } ?? Self.fallbackTab(from: tabs)
        currentTab = restored
        if settings.popoverSelectedTab != restored.rawValue {
            // BR-08：上次分区不可用时回退到首个可用分区并纠正持久化值
            settings.popoverSelectedTab = restored.rawValue
        }
        observeAvailability()
    }

    var route: PopoverTabRoute {
        PopoverTabRoute.route(for: currentTab)
    }

    /// BR-10 / BR-34：未上线分区不占位；关闭温控时不展示温控分区
    static func availableTabs(from settings: AppSettings) -> [PopoverTab] {
        PopoverTab.allCases.filter { tab in
            switch tab {
            case .thermal:
                return settings.thermalEnabled
            case .guardian, .tools:
                return true
            case .monitor:
                return settings.popoverShowMonitor && settings.systemMonitorEnabled
            case .audio:
                // 音频控制总开关是唯一入口：启用后才出现声音分区
                return settings.audioHubEnabled
            case .gateway:
                // 只在网关启用时展示分区，关闭后从面板移除
                return settings.aiGatewayEnabled
            }
        }
    }

    /// 当前分区不可用时的回退目标：按分区顺序取首个可用项
    static func fallbackTab(from tabs: [PopoverTab]) -> PopoverTab {
        tabs.first ?? .guardian
    }

    @discardableResult
    func select(_ tab: PopoverTab) -> Bool {
        guard availableTabs.contains(tab), tab != currentTab else { return false }
        switchTo(tab)
        return true
    }

    /// ⌘1–⌘6 的固定顺序映射，未启用分区返回 false（BR-10）
    @discardableResult
    func selectByShortcutIndex(_ index: Int) -> Bool {
        guard PopoverTab.allCases.indices.contains(index) else { return false }
        return select(PopoverTab.allCases[index])
    }

    @discardableResult
    func move(by delta: Int) -> Bool {
        guard let index = availableTabs.firstIndex(of: currentTab) else { return false }
        let next = (index + delta + availableTabs.count) % availableTabs.count
        return select(availableTabs[next])
    }

    /// 打开面板时按持久化值恢复；持久化值失效则回退首个可用分区
    func syncWithPersistedSelection() {
        let saved = PopoverTab(rawValue: settings.popoverSelectedTab)
        guard let saved, availableTabs.contains(saved) else {
            let fallback = Self.fallbackTab(from: availableTabs)
            if currentTab != fallback {
                switchTo(fallback)
            }
            if settings.popoverSelectedTab != fallback.rawValue {
                settings.popoverSelectedTab = fallback.rawValue
            }
            return
        }
        if saved != currentTab {
            switchTo(saved)
        }
    }

    private func switchTo(_ tab: PopoverTab) {
        currentTab = tab
        settings.popoverSelectedTab = tab.rawValue
        onTabChange?(tab)
    }

    private func observeAvailability() {
        Publishers.CombineLatest3(
            settings.$popoverShowMonitor,
            settings.$systemMonitorEnabled,
            settings.$thermalEnabled
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.refreshAvailability()
            }
            .store(in: &cancellables)

        // 音频控制总开关切换后立即刷新分区可用性
        settings.$audioHubEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAvailability()
            }
            .store(in: &cancellables)

        // AI 网关开关切换后立即刷新分区可用性
        settings.$aiGatewayEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAvailability()
            }
            .store(in: &cancellables)
    }

    private func refreshAvailability() {
        let next = Self.availableTabs(from: settings)
        guard next != availableTabs else { return }
        availableTabs = next
        guard !next.contains(currentTab) else { return }
        // 当前分区被模块下线或关闭时回退首个可用分区
        let fallback = Self.fallbackTab(from: next)
        if currentTab != fallback {
            switchTo(fallback)
        }
    }
}
