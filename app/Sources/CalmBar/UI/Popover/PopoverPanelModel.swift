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
        let restored = saved.flatMap { tabs.contains($0) ? $0 : nil } ?? .thermal
        currentTab = restored
        if settings.popoverSelectedTab != restored.rawValue {
            // BR-08：上次分区不可用时回退温控并纠正持久化值
            settings.popoverSelectedTab = restored.rawValue
        }
        observeAvailability()
    }

    var route: PopoverTabRoute {
        PopoverTabRoute.route(for: currentTab)
    }

    /// BR-10 / BR-34：未上线分区不占位
    static func availableTabs(from settings: AppSettings) -> [PopoverTab] {
        PopoverTab.allCases.filter { tab in
            switch tab {
            case .thermal, .guardian, .tools:
                return true
            case .monitor:
                return settings.popoverShowMonitor && settings.systemMonitorEnabled
            case .audio:
                return settings.popoverShowAudio
            }
        }
    }

    @discardableResult
    func select(_ tab: PopoverTab) -> Bool {
        guard availableTabs.contains(tab), tab != currentTab else { return false }
        switchTo(tab)
        return true
    }

    /// ⌘1–⌘5 的固定顺序映射，未启用分区返回 false（BR-10）
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

    /// 打开面板时按持久化值恢复；持久化值失效则回退温控
    func syncWithPersistedSelection() {
        let saved = PopoverTab(rawValue: settings.popoverSelectedTab)
        guard let saved, availableTabs.contains(saved) else {
            if currentTab != .thermal {
                switchTo(.thermal)
            }
            if settings.popoverSelectedTab != PopoverTab.thermal.rawValue {
                settings.popoverSelectedTab = PopoverTab.thermal.rawValue
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
            settings.$popoverShowAudio,
            settings.$systemMonitorEnabled
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.refreshAvailability()
            }
            .store(in: &cancellables)
    }

    private func refreshAvailability() {
        let next = Self.availableTabs(from: settings)
        guard next != availableTabs else { return }
        availableTabs = next
        guard !next.contains(currentTab) else { return }
        // 当前分区被模块下线或关闭时回退温控
        if currentTab != .thermal {
            switchTo(.thermal)
        }
    }
}
